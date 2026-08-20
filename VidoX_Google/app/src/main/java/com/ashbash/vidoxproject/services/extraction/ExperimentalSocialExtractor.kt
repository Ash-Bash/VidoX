package com.ashbash.vidoxproject.services.extraction

import android.content.Context
import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.models.VideoPlatform
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import java.net.URL

/**
 * Hybrid social extractor matching Apple's Mac strategy:
 * prefer native page resolvers for hard hosts, yt-dlp otherwise, native as last chance.
 */
class ExperimentalSocialExtractor(
    private val appContext: Context,
    private val pageExtractor: AndroidPageVideoExtractor = AndroidPageVideoExtractor(),
    private val ytdlpExtractor: YtDlpExtractor = YtDlpExtractor(appContext)
) : VideoExtracting {

    override suspend fun extract(from: URL): VideoMetadata {
        val platform = VideoPlatform.detect(from.toString()).let {
            if (it == VideoPlatform.UNKNOWN) VideoPlatform.WEB else it
        }

        if (platform == VideoPlatform.INSTAGRAM) {
            return pageExtractor.extract(from)
        }

        if (platform == VideoPlatform.YOUTUBE) {
            return extractYouTube(from)
        }

        if (prefersNative(platform)) {
            runCatching { pageExtractor.extract(from) }.getOrNull()?.let { return it }
        }

        return try {
            ytdlpExtractor.extract(from)
        } catch (ytdlpError: CancellationException) {
            throw ytdlpError
        } catch (ytdlpError: Exception) {
            runCatching { pageExtractor.extract(from) }.getOrNull()
                ?: throw ytdlpError
        }
    }

    private suspend fun extractYouTube(from: URL): VideoMetadata = coroutineScope {
        val winner = CompletableDeferred<VideoMetadata>()
        val native = async {
            runCatching { stampYouTube(pageExtractor.extract(from)) }.getOrNull()
        }
        val ytdlp = async {
            runCatching { ytdlpExtractor.extract(from) }.getOrNull()
        }
        launch { native.await()?.let { winner.complete(it) } }
        launch { ytdlp.await()?.let { winner.complete(it) } }
        launch {
            native.join()
            ytdlp.join()
            if (!winner.isCompleted) {
                winner.completeExceptionally(
                    PageExtractionError.Network("Couldn’t resolve this YouTube video. Try again.")
                )
            }
        }
        try {
            winner.await()
        } finally {
            native.cancel()
            ytdlp.cancel()
        }
    }

    private fun stampYouTube(metadata: VideoMetadata): VideoMetadata {
        val formats = metadata.formats.map { format ->
            if (format.isAudioOnly) format
            else format.copy(
                fileExtension = "mp4",
                ytdlpFormatSelector = youtubeSelector(format.quality),
                isHlsStream = false
            )
        }
        return metadata.copy(
            allowsRealDownload = true,
            usesYTDLP = true,
            formats = formats
        )
    }

    private fun prefersNative(platform: VideoPlatform): Boolean = when (platform) {
        VideoPlatform.FACEBOOK,
        VideoPlatform.INSTAGRAM,
        VideoPlatform.TWITTER,
        VideoPlatform.TIKTOK,
        VideoPlatform.REDDIT,
        VideoPlatform.STREAMABLE -> true
        else -> false
    }
}
