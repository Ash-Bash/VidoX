package com.ashbash.vidoxproject.services.extraction

import android.content.Context
import com.ashbash.vidoxproject.services.download.httpStatusIn
import com.ashbash.vidoxproject.services.download.httpStatusMessage
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

sealed class YtDlpError(message: String) : Exception(message) {
    data object NotInitialized : YtDlpError("Downloader engine is not ready yet.")
    data object InvalidMetadata : YtDlpError("Couldn’t read video metadata from the download engine.")
    data class Failed(val detail: String) : YtDlpError(
        httpStatusIn(detail)?.let { httpStatusMessage(it) }
            ?: if (detail.contains("ffmpeg", ignoreCase = true)) {
                "Couldn’t combine the video and audio (ffmpeg). Try again, or pick a different quality."
            } else {
                detail
            }
    )
}

/** Thin wrapper around youtubedl-android (yt-dlp + ffmpeg). */
object YtDlpTool {
    private val mutex = Mutex()
    @Volatile private var initialized = false

    suspend fun ensureInitialized(context: Context) = withContext(Dispatchers.IO) {
        if (initialized) return@withContext
        mutex.withLock {
            if (initialized) return@withLock
            try {
                YoutubeDL.getInstance().init(context.applicationContext)
                FFmpeg.getInstance().init(context.applicationContext)
                initialized = true
            } catch (e: Exception) {
                throw YtDlpError.Failed(e.message ?: "Failed to initialize download engine.")
            }
        }
        // Never block lookup on a binary update.
        CoroutineScope(Dispatchers.IO).launch {
            runCatching { YoutubeDL.getInstance().updateYoutubeDL(context.applicationContext) }
        }
    }

    suspend fun fetchJson(pageUrl: String, extraArgs: List<Pair<String, String?>> = emptyList()): JSONObject =
        withContext(Dispatchers.IO) {
            if (!initialized) throw YtDlpError.NotInitialized
            val request = YoutubeDLRequest(pageUrl).apply {
                addOption("-J")
                addOption("--no-playlist")
                addOption("--no-warnings")
                addOption("--socket-timeout", "8")
                addOption("--retries", "1")
                addOption("-f", "all")
                addOption("--ignore-no-formats-error")
                extraArgs.forEach { (key, value) ->
                    if (value == null) addOption(key) else addOption(key, value)
                }
            }
            try {
                val processId = "extract-${UUID.randomUUID()}"
                val response = coroutineScope {
                    val deferred = async {
                        YoutubeDL.getInstance().execute(request, processId, null)
                    }
                    try {
                        withTimeout(12_000) { deferred.await() }
                    } catch (e: CancellationException) {
                        runCatching { YoutubeDL.getInstance().destroyProcessById(processId) }
                        deferred.cancel()
                        if (e is TimeoutCancellationException) {
                            throw YtDlpError.Failed("Timed out looking up this video.")
                        }
                        throw e
                    }
                }
                val out = response.out.trim()
                if (out.isEmpty()) throw YtDlpError.InvalidMetadata
                JSONObject(out)
            } catch (e: CancellationException) {
                throw e
            } catch (e: YtDlpError) {
                throw e
            } catch (e: Exception) {
                throw YtDlpError.Failed(e.message ?: "yt-dlp failed.")
            }
        }

    suspend fun download(
        pageUrl: String,
        formatSelector: String,
        outputTemplate: String,
        onProgress: ((Float) -> Unit)? = null
    ): String = withContext(Dispatchers.IO) {
        if (!initialized) throw YtDlpError.NotInitialized
        val request = YoutubeDLRequest(pageUrl).apply {
            addOption("-f", formatSelector)
            addOption("-o", outputTemplate)
            addOption("--no-playlist")
            addOption("--no-warnings")
            addOption("--merge-output-format", "mp4")
            addOption("--newline")
            val host = pageUrl.lowercase()
            if (host.contains("youtube.com") || host.contains("youtu.be")) {
                addOption("--extractor-args", YOUTUBE_EXTRACTOR_ARGS)
                addOption("--check-formats")
            }
        }
        try {
            val callback: ((Float, Long, String) -> Unit)? =
                onProgress?.let { progressCb ->
                    { progress: Float, _: Long, _: String -> progressCb(progress / 100f) }
                }
            val response = YoutubeDL.getInstance().execute(request, null, callback)
            if (response.exitCode != 0) {
                throw YtDlpError.Failed(response.err.ifEmpty { "Download failed." })
            }
            outputTemplate
        } catch (e: CancellationException) {
            throw e
        } catch (e: YtDlpError) {
            throw e
        } catch (e: Exception) {
            throw YtDlpError.Failed(e.message ?: "Download failed.")
        }
    }
}
