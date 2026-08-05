package com.ashbash.vidoxproject.services.extraction

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject

sealed class YtDlpError(message: String) : Exception(message) {
    data object NotInitialized : YtDlpError("Downloader engine is not ready yet.")
    data object InvalidMetadata : YtDlpError("Couldn’t read video metadata from the download engine.")
    data class Failed(val detail: String) : YtDlpError(detail)
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
                runCatching { YoutubeDL.getInstance().updateYoutubeDL(context.applicationContext) }
                initialized = true
            } catch (e: Exception) {
                throw YtDlpError.Failed(e.message ?: "Failed to initialize download engine.")
            }
        }
    }

    suspend fun fetchJson(pageUrl: String, extraArgs: List<Pair<String, String?>> = emptyList()): JSONObject =
        withContext(Dispatchers.IO) {
            if (!initialized) throw YtDlpError.NotInitialized
            val request = YoutubeDLRequest(pageUrl).apply {
                addOption("-J")
                addOption("--no-playlist")
                addOption("--no-warnings")
                addOption("--socket-timeout", "10")
                extraArgs.forEach { (key, value) ->
                    if (value == null) addOption(key) else addOption(key, value)
                }
            }
            try {
                val response = YoutubeDL.getInstance().execute(request)
                val out = response.out.trim()
                if (out.isEmpty()) throw YtDlpError.InvalidMetadata
                JSONObject(out)
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
        } catch (e: YtDlpError) {
            throw e
        } catch (e: Exception) {
            throw YtDlpError.Failed(e.message ?: "Download failed.")
        }
    }
}
