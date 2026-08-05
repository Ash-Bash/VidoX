package com.ashbash.vidoxproject.services.extraction

import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.models.VideoPlatform
import com.ashbash.vidoxproject.util.URLNormalizer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.net.URL

/** Preview-only metadata for known video page hosts. */
class StubSocialExtractor : VideoExtracting {
    override suspend fun extract(from: URL): VideoMetadata = withContext(Dispatchers.IO) {
        var platform = VideoPlatform.detect(from.toString())
        if (platform == VideoPlatform.UNKNOWN) platform = VideoPlatform.WEB
        val oembed = fetchOEmbed(from, platform)
        VideoMetadata(
            title = oembed?.title ?: "${platform.displayName} video",
            author = oembed?.authorName ?: platform.displayName,
            thumbnailURL = oembed?.thumbnailURL,
            platform = platform,
            sourceURL = from,
            formats = emptyList(),
            allowsRealDownload = false
        )
    }

    private data class OEmbedInfo(
        val title: String?,
        val authorName: String?,
        val thumbnailURL: URL?
    )

    private suspend fun fetchOEmbed(url: URL, platform: VideoPlatform): OEmbedInfo? {
        val endpoint = oEmbedEndpoint(url, platform) ?: run {
            delay(250)
            return null
        }
        return try {
            HttpClients.get(endpoint, headers = mapOf("Accept" to "application/json")).use { response ->
                if (!response.isSuccessful) return null
                val json = response.jsonOrNull() ?: return null
                OEmbedInfo(
                    title = json.optString("title").ifEmpty { null },
                    authorName = json.optString("author_name").ifEmpty { null },
                    thumbnailURL = json.optString("thumbnail_url").ifEmpty { null }?.let { URL(it) }
                )
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun oEmbedEndpoint(url: URL, platform: VideoPlatform): String? {
        val encoded = URLNormalizer.encodeQuery(url.toString())
        return when (platform) {
            VideoPlatform.YOUTUBE -> "https://www.youtube.com/oembed?url=$encoded&format=json"
            VideoPlatform.TWITTER -> "https://publish.twitter.com/oembed?url=$encoded"
            VideoPlatform.TIKTOK -> "https://www.tiktok.com/oembed?url=$encoded"
            VideoPlatform.VIMEO -> "https://vimeo.com/api/oembed.json?url=$encoded"
            VideoPlatform.DAILYMOTION -> "https://www.dailymotion.com/services/oembed?url=$encoded"
            VideoPlatform.REDDIT -> "https://www.reddit.com/oembed?url=$encoded"
            else -> null
        }
    }
}
