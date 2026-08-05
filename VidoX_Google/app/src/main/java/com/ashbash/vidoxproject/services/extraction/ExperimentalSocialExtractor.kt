package com.ashbash.vidoxproject.services.extraction

import android.content.Context
import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.models.VideoPlatform
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

        if (prefersNative(platform)) {
            runCatching { pageExtractor.extract(from) }.getOrNull()?.let { return it }
        }

        return try {
            ytdlpExtractor.extract(from)
        } catch (ytdlpError: Exception) {
            runCatching { pageExtractor.extract(from) }.getOrNull()
                ?: throw ytdlpError
        }
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
