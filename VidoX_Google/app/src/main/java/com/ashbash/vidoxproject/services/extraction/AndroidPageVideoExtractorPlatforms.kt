package com.ashbash.vidoxproject.services.extraction

import com.ashbash.vidoxproject.models.VideoFormat
import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.models.VideoPlatform
import com.ashbash.vidoxproject.util.URLNormalizer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URL
import java.net.URLDecoder

/**
 * Dedicated native resolvers for platforms that usually fail generic HTML scraping.
 * Port of Apple [IOSPageVideoExtractor+Platforms].
 */
suspend fun AndroidPageVideoExtractor.extractKnownPlatform(
    url: URL,
    platform: VideoPlatform
): VideoMetadata? = when (platform) {
    VideoPlatform.TWITTER -> extractTwitter(url)
    VideoPlatform.VIMEO -> extractVimeo(url)
    VideoPlatform.DAILYMOTION -> extractDailymotion(url)
    VideoPlatform.REDDIT -> extractReddit(url)
    VideoPlatform.TWITCH -> extractTwitch(url)
    VideoPlatform.STREAMABLE -> extractStreamable(url)
    VideoPlatform.RUMBLE -> extractRumble(url)
    else -> null
}

// region X / Twitter

private suspend fun AndroidPageVideoExtractor.extractTwitter(sourceURL: URL): VideoMetadata {
    val statusID = twitterStatusID(sourceURL)
        ?: throw PageExtractionError.Network(
            "Couldn’t read that X link. Use a post URL like x.com/user/status/…"
        )

    val endpoints = listOf(
        "https://api.fxtwitter.com/status/$statusID",
        "https://api.vxtwitter.com/Twitter/status/$statusID"
    )

    for (endpoint in endpoints) {
        fetchTwitterAPI(endpoint, sourceURL)?.let { return it }
    }

    try {
        val metadata = extractFromHTMLPage(sourceURL, VideoPlatform.TWITTER)
        if (metadata != null && metadata.formats.any { !it.isAudioOnly }) {
            return metadata
        }
    } catch (_: Exception) {
        // fall through
    }

    throw PageExtractionError.Network(
        "Couldn’t resolve this X video. It may be private, deleted, or have no video attached."
    )
}

private fun AndroidPageVideoExtractor.fetchTwitterAPI(
    endpoint: String,
    sourceURL: URL
): VideoMetadata? {
    return try {
        HttpClients.get(
            endpoint,
            userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            headers = mapOf("Accept" to "application/json")
        ).use { response ->
            if (response.code !in 200 until 300) return null
            val json = response.jsonOrNull() ?: return null
            metadataFromTwitterJSON(json, sourceURL)
        }
    } catch (_: Exception) {
        null
    }
}

private fun AndroidPageVideoExtractor.metadataFromTwitterJSON(
    json: JSONObject,
    sourceURL: URL
): VideoMetadata? {
    val tweet = json.optJSONObject("tweet") ?: json
    val media = tweet.optJSONObject("media")
    val videos = media?.optJSONArray("videos")
        ?: media?.optJSONArray("all")
        ?: JSONArray()

    val formats = mutableListOf<VideoFormat>()
    val seen = mutableSetOf<String>()
    var thumbnail: URL? = null

    for (index in 0 until videos.length()) {
        val video = videos.optJSONObject(index) ?: continue
        val type = video.optString("type").lowercase().ifEmpty { "video" }
        if (type.contains("photo") || type.contains("image")) continue

        if (thumbnail == null) {
            thumbnail = video.optString("thumbnail_url").ifEmpty { null }
                ?.let { runCatching { URL(it) }.getOrNull() }
                ?: video.optString("thumbnail").ifEmpty { null }
                    ?.let { runCatching { URL(it) }.getOrNull() }
        }

        val variants = video.optJSONArray("variants")
        if (variants != null && variants.length() > 0) {
            val mp4s = mutableListOf<Pair<Int, URL>>()
            for (i in 0 until variants.length()) {
                val variant = variants.optJSONObject(i) ?: continue
                val contentType = variant.optString("content_type").lowercase()
                val urlString = variant.optString("url")
                if (urlString.isEmpty()) continue
                if (!(contentType.contains("mp4") || urlString.contains(".mp4"))) continue
                val url = try {
                    URL(urlString)
                } catch (_: Exception) {
                    continue
                }
                mp4s += (variant.optInt("bitrate", 0) to url)
            }
            mp4s.sortByDescending { it.first }
            for ((bitrate, url) in mp4s.take(4)) {
                if (!seen.add(url.toString())) continue
                val quality = if (bitrate > 0) minOf(bitrate / 1000, 2160) else null
                formats += VideoFormat(
                    id = "x-$index-${formats.size}",
                    label = quality?.let { "~$it kbps" }
                        ?: if (formats.isEmpty()) "Best available" else "Option ${formats.size + 1}",
                    url = url,
                    fileExtension = "mp4",
                    quality = quality,
                    isAudioOnly = false
                )
            }
        } else {
            val urlString = video.optString("url")
            if (urlString.isEmpty() || !seen.add(urlString)) continue
            val url = try {
                URL(urlString)
            } catch (_: Exception) {
                continue
            }
            val isHls = urlString.lowercase().contains("m3u8")
            formats += VideoFormat(
                id = "x-$index",
                label = if (formats.isEmpty()) "Best available" else "Option ${formats.size + 1}",
                url = url,
                fileExtension = "mp4",
                quality = null,
                isAudioOnly = false,
                isHlsStream = isHls
            )
        }
    }

    if (formats.isEmpty()) return null

    val authorObj = tweet.optJSONObject("author")
    val author = authorObj?.optString("screen_name")?.ifEmpty { null }
        ?: authorObj?.optString("name")?.ifEmpty { null }
        ?: "X"
    val text = tweet.optString("text").trim()
    val shortTitle = when {
        text.isEmpty() -> "X video"
        text.length > 80 -> text.take(77) + "…"
        else -> text
    }

    return VideoMetadata(
        title = shortTitle,
        author = author,
        thumbnailURL = thumbnail,
        platform = VideoPlatform.TWITTER,
        sourceURL = sourceURL,
        formats = formats,
        allowsRealDownload = true,
        usesYTDLP = false
    )
}

private fun twitterStatusID(url: URL): String? {
    val parts = url.path.split('/').filter { it.isNotEmpty() }
    val statusIndex = parts.indexOfFirst { it == "status" || it == "statuses" }
    if (statusIndex >= 0 && statusIndex + 1 < parts.size) {
        val id = parts[statusIndex + 1].substringBefore('?')
        if (id.isNotEmpty() && id.all { it.isDigit() }) return id
    }
    // x.com/i/status/ID
    if (parts.size >= 3 && parts[0] == "i" && parts[1] == "status") {
        val id = parts[2].substringBefore('?')
        if (id.isNotEmpty() && id.all { it.isDigit() }) return id
    }
    return null
}

// endregion

// region Vimeo

private suspend fun AndroidPageVideoExtractor.extractVimeo(sourceURL: URL): VideoMetadata {
    val videoID = vimeoVideoID(sourceURL)
        ?: throw PageExtractionError.Network("Couldn’t read that Vimeo link.")
    val configURL = "https://player.vimeo.com/video/$videoID/config"

    return try {
        HttpClients.get(
            configURL,
            userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            headers = mapOf(
                "Accept" to "application/json",
                "Referer" to "https://vimeo.com/"
            )
        ).use { response ->
            if (response.code !in 200 until 300) throw PageExtractionError.NoMediaFound
            val json = response.jsonOrNull() ?: throw PageExtractionError.NoMediaFound
            metadataFromVimeoConfig(json, sourceURL) ?: throw PageExtractionError.NoMediaFound
        }
    } catch (e: PageExtractionError) {
        throw e
    } catch (_: Exception) {
        try {
            val metadata = extractFromHTMLPage(sourceURL, VideoPlatform.VIMEO)
            if (metadata != null && metadata.formats.any { !it.isAudioOnly }) {
                return metadata
            }
        } catch (_: Exception) {
            // fall through
        }
        throw PageExtractionError.Network(
            "Couldn’t resolve this Vimeo video. It may be private or password-protected."
        )
    }
}

private fun AndroidPageVideoExtractor.metadataFromVimeoConfig(
    json: JSONObject,
    sourceURL: URL
): VideoMetadata? {
    val video = json.optJSONObject("video")
    val request = json.optJSONObject("request")
    val files = request?.optJSONObject("files")
    val progressive = files?.optJSONArray("progressive") ?: JSONArray()

    val formats = mutableListOf<VideoFormat>()
    val seen = mutableSetOf<String>()

    val sorted = (0 until progressive.length())
        .mapNotNull { progressive.optJSONObject(it) }
        .sortedByDescending { it.optInt("height", 0) }

    for (entry in sorted) {
        val urlString = entry.optString("url")
        if (urlString.isEmpty() || !seen.add(urlString)) continue
        val url = try {
            URL(urlString)
        } catch (_: Exception) {
            continue
        }
        val height = entry.optInt("height", 0).takeIf { it > 0 }
        formats += VideoFormat(
            id = "vimeo-${height ?: formats.size}",
            label = height?.let { "${it}p" } ?: "Download",
            url = url,
            fileExtension = "mp4",
            quality = height,
            isAudioOnly = false
        )
        if (formats.size >= 4) break
    }

    if (formats.isEmpty()) {
        val hls = files?.optJSONObject("hls")
        var hlsURL: URL? = null
        val cdns = hls?.optJSONObject("cdns")
        if (cdns != null) {
            val keys = cdns.keys()
            while (keys.hasNext()) {
                val dict = cdns.optJSONObject(keys.next()) ?: continue
                val urlString = dict.optString("url").ifEmpty { null }
                    ?: dict.optString("avc_url").ifEmpty { null }
                    ?: continue
                hlsURL = runCatching { URL(urlString) }.getOrNull()
                if (hlsURL != null) break
            }
        }
        if (hlsURL == null) {
            hlsURL = hls?.optString("url")?.ifEmpty { null }
                ?.let { runCatching { URL(it) }.getOrNull() }
        }
        if (hlsURL != null) {
            formats += VideoFormat(
                id = "vimeo-hls",
                label = "Stream (HLS)",
                url = hlsURL,
                fileExtension = "mp4",
                quality = video?.optInt("height", 0)?.takeIf { it > 0 },
                isAudioOnly = false,
                isHlsStream = true
            )
        }
    }

    if (formats.isEmpty()) return null

    val title = video?.optString("title")?.trim()?.ifEmpty { null }
    val owner = video?.optJSONObject("owner")
    val author = owner?.optString("name")?.ifEmpty { null } ?: "Vimeo"
    val thumbs = video?.optJSONObject("thumbs")
    var thumbnail: URL? = null
    if (thumbs != null) {
        for (key in listOf("1280", "960", "640", "base")) {
            val s = thumbs.optString(key)
            if (s.isNotEmpty()) {
                thumbnail = runCatching { URL(s) }.getOrNull()
                if (thumbnail != null) break
            }
        }
        if (thumbnail == null) {
            val keys = thumbs.keys()
            while (keys.hasNext() && thumbnail == null) {
                val s = thumbs.optString(keys.next())
                if (s.isNotEmpty()) thumbnail = runCatching { URL(s) }.getOrNull()
            }
        }
    }

    return VideoMetadata(
        title = title ?: "Vimeo video",
        author = author,
        thumbnailURL = thumbnail,
        platform = VideoPlatform.VIMEO,
        sourceURL = sourceURL,
        formats = formats,
        allowsRealDownload = true,
        usesYTDLP = false
    )
}

private fun vimeoVideoID(url: URL): String? {
    val parts = url.path.split('/').filter { it.isNotEmpty() }
    // player.vimeo.com/video/ID
    val videoIndex = parts.indexOf("video")
    if (videoIndex >= 0 && videoIndex + 1 < parts.size) {
        val id = parts[videoIndex + 1]
        if (id.all { it.isDigit() }) return id
    }
    // vimeo.com/ID
    val first = parts.firstOrNull()
    if (first != null && first.all { it.isDigit() } && first.length >= 5) return first
    // vimeo.com/channels/x/ID or manage/videos/ID
    val last = parts.lastOrNull()
    if (last != null && last.all { it.isDigit() } && last.length >= 5) return last
    return null
}

// endregion

// region Dailymotion

private suspend fun AndroidPageVideoExtractor.extractDailymotion(sourceURL: URL): VideoMetadata {
    val videoID = dailymotionVideoID(sourceURL)
        ?: throw PageExtractionError.Network("Couldn’t read that Dailymotion link.")
    val metaURL = "https://www.dailymotion.com/player/metadata/video/$videoID"

    return try {
        HttpClients.get(
            metaURL,
            userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            headers = mapOf("Accept" to "application/json")
        ).use { response ->
            if (response.code !in 200 until 300) throw PageExtractionError.NoMediaFound
            val json = response.jsonOrNull() ?: throw PageExtractionError.NoMediaFound
            metadataFromDailymotion(json, sourceURL) ?: throw PageExtractionError.NoMediaFound
        }
    } catch (e: PageExtractionError) {
        throw e
    } catch (_: Exception) {
        throw PageExtractionError.Network(
            "Couldn’t resolve this Dailymotion video. It may be private or geo-blocked."
        )
    }
}

private fun AndroidPageVideoExtractor.metadataFromDailymotion(
    json: JSONObject,
    sourceURL: URL
): VideoMetadata? {
    val qualities = json.optJSONObject("qualities") ?: JSONObject()
    val formats = mutableListOf<VideoFormat>()
    val seen = mutableSetOf<String>()

    val rankedKeys = qualities.keys().asSequence().toList().sortedByDescending { key ->
        key.toIntOrNull() ?: if (key == "auto") 0 else 1
    }

    for (key in rankedKeys) {
        val entries = qualities.optJSONArray(key) ?: continue
        for (i in 0 until entries.length()) {
            val entry = entries.optJSONObject(i) ?: continue
            val urlString = entry.optString("url")
            if (urlString.isEmpty() || !seen.add(urlString)) continue
            val url = try {
                URL(urlString)
            } catch (_: Exception) {
                continue
            }
            val type = entry.optString("type").lowercase()
            val isHls = type.contains("mpegurl") || urlString.lowercase().contains("m3u8")
            val height = key.toIntOrNull()
            formats += VideoFormat(
                id = "dm-$key-${formats.size}",
                label = height?.let { "${it}p" } ?: if (key == "auto") "Auto" else key,
                url = url,
                fileExtension = "mp4",
                quality = height,
                isAudioOnly = false,
                isHlsStream = isHls
            )
        }
        if (formats.size >= 4) break
    }

    if (formats.isEmpty()) return null

    val title = json.optString("title").trim().ifEmpty { null }
    val owner = json.optJSONObject("owner")
    val author = owner?.optString("screenname")?.ifEmpty { null }
        ?: owner?.optString("username")?.ifEmpty { null }
        ?: "Dailymotion"
    val thumbs = json.optJSONObject("thumbnails")
    var thumbnail: URL? = null
    if (thumbs != null) {
        for (key in listOf("1080", "720", "480", "360")) {
            val s = thumbs.optString(key)
            if (s.isNotEmpty()) {
                thumbnail = runCatching { URL(s) }.getOrNull()
                if (thumbnail != null) break
            }
        }
        if (thumbnail == null) {
            val keys = thumbs.keys()
            while (keys.hasNext() && thumbnail == null) {
                val s = thumbs.optString(keys.next())
                if (s.isNotEmpty()) thumbnail = runCatching { URL(s) }.getOrNull()
            }
        }
    }
    if (thumbnail == null) {
        thumbnail = json.optString("poster_url").ifEmpty { null }
            ?.let { runCatching { URL(it) }.getOrNull() }
    }

    // Prefer progressive mp4 over HLS when both exist.
    formats.sortByDescending {
        (if (it.isHlsStream) 0 else 1_000_000) + (it.quality ?: 0)
    }

    return VideoMetadata(
        title = title ?: "Dailymotion video",
        author = author,
        thumbnailURL = thumbnail,
        platform = VideoPlatform.DAILYMOTION,
        sourceURL = sourceURL,
        formats = formats.take(4),
        allowsRealDownload = true,
        usesYTDLP = false
    )
}

private fun dailymotionVideoID(url: URL): String? {
    val host = url.host?.lowercase().orEmpty()
    val parts = url.path.split('/').filter { it.isNotEmpty() }

    if (host.contains("dai.ly")) {
        return parts.firstOrNull()?.takeIf { it.isNotEmpty() }
    }
    val videoIndex = parts.indexOfFirst { it == "video" || it == "embed" }
    if (videoIndex >= 0 && videoIndex + 1 < parts.size) {
        return parts[videoIndex + 1].substringBefore('?')
    }
    return null
}

// endregion

// region Reddit

private suspend fun AndroidPageVideoExtractor.extractReddit(sourceURL: URL): VideoMetadata {
    val jsonURL = redditJSONURL(sourceURL)

    return try {
        HttpClients.get(
            jsonURL.toString(),
            userAgent = "VidoX/1.0 (video library; +https://vidox.app)",
            headers = mapOf("Accept" to "application/json")
        ).use { response ->
            if (response.code !in 200 until 300) throw PageExtractionError.NoMediaFound
            val text = response.bodyString() ?: throw PageExtractionError.NoMediaFound
            val metadata = metadataFromRedditJSON(text, sourceURL)
                ?: throw PageExtractionError.NoMediaFound
            metadata
        }
    } catch (e: PageExtractionError) {
        throw e
    } catch (_: Exception) {
        try {
            val metadata = extractFromHTMLPage(sourceURL, VideoPlatform.REDDIT)
            if (metadata != null && metadata.formats.any { !it.isAudioOnly }) {
                return metadata
            }
        } catch (_: Exception) {
            // fall through
        }
        throw PageExtractionError.Network(
            "Couldn’t resolve this Reddit video. Try the full post URL (reddit.com/r/…/comments/…)."
        )
    }
}

private fun redditJSONURL(url: URL): URL {
    val host = (url.host ?: "www.reddit.com").replace("old.", "")
    if (host.contains("redd.it") && !host.contains("reddit.com")) {
        val id = url.path.split('/').firstOrNull { it.isNotEmpty() }
        if (id != null) {
            return URL("https://www.reddit.com/comments/$id.json")
        }
    }

    var path = url.path
    if (path.endsWith("/")) path = path.dropLast(1)
    if (!path.endsWith(".json")) path += ".json"
    val normalizedHost = if (host.contains("reddit.com")) "www.reddit.com" else host
    return URL("https://$normalizedHost$path?raw_json=1")
}

private fun AndroidPageVideoExtractor.metadataFromRedditJSON(
    text: String,
    sourceURL: URL
): VideoMetadata? {
    // Comment pages return [postListing, commentsListing]; single listings return one object.
    val listings = try {
        when {
            text.trimStart().startsWith("[") -> {
                val array = JSONArray(text)
                (0 until array.length()).mapNotNull { array.optJSONObject(it) }
            }
            else -> listOf(JSONObject(text))
        }
    } catch (_: Exception) {
        return null
    }

    for (listing in listings) {
        val children = listing.optJSONObject("data")?.optJSONArray("children") ?: continue
        for (i in 0 until children.length()) {
            val post = children.optJSONObject(i)?.optJSONObject("data") ?: continue
            metadataFromRedditPost(post, sourceURL)?.let { return it }
        }
    }
    return null
}

private fun AndroidPageVideoExtractor.metadataFromRedditPost(
    post: JSONObject,
    sourceURL: URL
): VideoMetadata? {
    val media = post.optJSONObject("secure_media")
        ?: post.optJSONObject("media")
        ?: JSONObject()
    val redditVideo = media.optJSONObject("reddit_video")
    val cross = post.optJSONArray("crosspost_parent_list")
    val crossFirst = cross?.optJSONObject(0)
    val crossVideo = crossFirst?.optJSONObject("secure_media")?.optJSONObject("reddit_video")
        ?: crossFirst?.optJSONObject("media")?.optJSONObject("reddit_video")

    val video = redditVideo ?: crossVideo
    val formats = mutableListOf<VideoFormat>()

    val fallback = video?.optString("fallback_url")?.ifEmpty { null }
    if (fallback != null) {
        try {
            formats += VideoFormat(
                id = "reddit-progressive",
                label = "Best available",
                url = URL(fallback),
                fileExtension = "mp4",
                quality = video?.optInt("height", 0)?.takeIf { it > 0 },
                isAudioOnly = false
            )
        } catch (_: Exception) {
            // ignore
        }
    }
    val hls = video?.optString("hls_url")?.ifEmpty { null }
    if (hls != null) {
        try {
            formats += VideoFormat(
                id = "reddit-hls",
                label = "Stream (HLS)",
                url = URL(hls),
                fileExtension = "mp4",
                quality = video?.optInt("height", 0)?.takeIf { it > 0 },
                isAudioOnly = false,
                isHlsStream = true
            )
        } catch (_: Exception) {
            // ignore
        }
    }
    val dash = video?.optString("dash_url")?.ifEmpty { null }
    if (dash != null && formats.isEmpty()) {
        try {
            formats += VideoFormat(
                id = "reddit-dash",
                label = "Stream (DASH)",
                url = URL(dash),
                fileExtension = "mp4",
                quality = video?.optInt("height", 0)?.takeIf { it > 0 },
                isAudioOnly = false,
                isHlsStream = true
            )
        } catch (_: Exception) {
            // ignore
        }
    }

    // Direct gifv / external mp4 hosted by Reddit or imgur-style.
    if (formats.isEmpty()) {
        val urlString = post.optString("url_overridden_by_dest").ifEmpty { null }
            ?: post.optString("url").ifEmpty { null }
        if (urlString != null) {
            try {
                var mediaURL = URL(urlString)
                if (DirectMediaExtractor.looksLikeDirectMediaURL(mediaURL) ||
                    urlString.lowercase().contains(".gifv")
                ) {
                    if (mediaURL.path.lowercase().endsWith(".gifv")) {
                        val base = mediaURL.toString().removeSuffix(".gifv").removeSuffix(".GIFV")
                        mediaURL = URL("$base.mp4")
                    }
                    formats += VideoFormat(
                        id = "reddit-direct",
                        label = "Best available",
                        url = mediaURL,
                        fileExtension = "mp4",
                        quality = null,
                        isAudioOnly = false
                    )
                }
            } catch (_: Exception) {
                // ignore
            }
        }
    }

    if (formats.isEmpty()) return null

    val title = post.optString("title").trim().ifEmpty { null }
    val authorRaw = post.optString("author").ifEmpty { "Reddit" }
    val author = if (authorRaw.startsWith("u/")) authorRaw else "u/$authorRaw"
    val images = post.optJSONObject("preview")?.optJSONArray("images")
    val source = images?.optJSONObject(0)?.optJSONObject("source")
    val thumbnail = source?.optString("url")?.ifEmpty { null }
        ?.replace("&amp;", "&")
        ?.let { runCatching { URL(it) }.getOrNull() }

    return VideoMetadata(
        title = title ?: "Reddit video",
        author = author,
        thumbnailURL = thumbnail,
        platform = VideoPlatform.REDDIT,
        sourceURL = sourceURL,
        formats = formats,
        allowsRealDownload = true,
        usesYTDLP = false
    )
}

// endregion

// region Twitch

private suspend fun AndroidPageVideoExtractor.extractTwitch(sourceURL: URL): VideoMetadata {
    val slug = twitchClipSlug(sourceURL)
    if (slug != null) {
        extractTwitchClip(slug, sourceURL)?.let { return it }
    }

    try {
        val metadata = extractFromHTMLPage(sourceURL, VideoPlatform.TWITCH)
        if (metadata != null && metadata.formats.any { !it.isAudioOnly }) {
            return metadata
        }
    } catch (_: Exception) {
        // fall through
    }

    throw PageExtractionError.Network(
        "Couldn’t resolve this Twitch media. Clips work best — VODs may need yt-dlp."
    )
}

private fun AndroidPageVideoExtractor.extractTwitchClip(
    slug: String,
    sourceURL: URL
): VideoMetadata? {
    // Official-ish clip status endpoint.
    val statusURL = "https://clips.twitch.tv/api/v2/clips/$slug/status"
    try {
        HttpClients.get(
            statusURL,
            userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            headers = mapOf("Accept" to "application/json")
        ).use { response ->
            if (response.code in 200 until 300) {
                val json = response.jsonOrNull()
                val options = json?.optJSONArray("quality_options")
                if (options != null && options.length() > 0) {
                    val formats = mutableListOf<VideoFormat>()
                    val seen = mutableSetOf<String>()
                    val sorted = (0 until options.length())
                        .mapNotNull { options.optJSONObject(it) }
                        .sortedByDescending { it.optString("quality").toIntOrNull() ?: 0 }
                    for (entry in sorted) {
                        val urlString = entry.optString("source")
                        if (urlString.isEmpty() || !seen.add(urlString)) continue
                        val url = try {
                            URL(urlString)
                        } catch (_: Exception) {
                            continue
                        }
                        val quality = entry.optString("quality").toIntOrNull()
                        formats += VideoFormat(
                            id = "twitch-${quality ?: formats.size}",
                            label = quality?.let { "${it}p" } ?: "Download",
                            url = url,
                            fileExtension = "mp4",
                            quality = quality,
                            isAudioOnly = false
                        )
                        if (formats.size >= 4) break
                    }
                    if (formats.isNotEmpty()) {
                        return VideoMetadata(
                            title = "Twitch clip",
                            author = "Twitch",
                            thumbnailURL = null,
                            platform = VideoPlatform.TWITCH,
                            sourceURL = sourceURL,
                            formats = formats,
                            allowsRealDownload = true,
                            usesYTDLP = false
                        )
                    }
                }
            }
        }
    } catch (_: Exception) {
        // try GQL
    }

    return extractTwitchClipViaGQL(slug, sourceURL)
}

private fun AndroidPageVideoExtractor.extractTwitchClipViaGQL(
    slug: String,
    sourceURL: URL
): VideoMetadata? {
    val body = JSONArray().put(
        JSONObject().apply {
            put("operationName", "VideoAccessToken_Clip")
            put("variables", JSONObject().put("slug", slug))
            put(
                "extensions",
                JSONObject().put(
                    "persistedQuery",
                    JSONObject()
                        .put("version", 1)
                        .put(
                            "sha256Hash",
                            "36b89d2507fce29e5ca84ee7110745d554561589c371bf684938d7a2c6a648c7"
                        )
                )
            )
        }
    )

    val requestBody = body.toString().toRequestBody(
        "application/json; charset=utf-8".toMediaType()
    )
    val request = Request.Builder()
        .url("https://gql.twitch.tv/gql")
        .header("Content-Type", "application/json")
        .header("Client-ID", "kimne78kx3ncx6brgo4mv6wki5h1ko")
        .header("User-Agent", HttpClients.DESKTOP_UA)
        .post(requestBody)
        .build()

    return try {
        HttpClients.default.newCall(request).execute().use { response ->
            if (response.code !in 200 until 300) return null
            val text = response.bodyString() ?: return null
            val array = JSONArray(text)
            val clip = array.optJSONObject(0)
                ?.optJSONObject("data")
                ?.optJSONObject("clip")
                ?: return null

            val title = clip.optString("title").ifEmpty { "Twitch clip" }
            val broadcaster = clip.optJSONObject("broadcaster")
            val author = broadcaster?.optString("displayName")?.ifEmpty { null }
                ?: broadcaster?.optString("login")?.ifEmpty { null }
            val thumbnail = clip.optString("thumbnailURL").ifEmpty { null }
                ?.let { runCatching { URL(it) }.getOrNull() }
                ?: clip.optString("posterURL").ifEmpty { null }
                    ?.let { runCatching { URL(it) }.getOrNull() }

            val formats = mutableListOf<VideoFormat>()
            val qualities = clip.optJSONArray("videoQualities") ?: JSONArray()
            val tokenObj = clip.optJSONObject("playbackAccessToken")
            val token = tokenObj?.optString("value")?.ifEmpty { null }
            val sig = tokenObj?.optString("signature")?.ifEmpty { null }

            for (index in 0 until qualities.length()) {
                val quality = qualities.optJSONObject(index) ?: continue
                var urlString = quality.optString("sourceURL")
                if (urlString.isEmpty()) continue
                if (token != null && sig != null) {
                    val sep = if (urlString.contains('?')) "&" else "?"
                    urlString += "$sep" + "sig=$sig&token=${URLNormalizer.encodeQuery(token)}"
                }
                val url = try {
                    URL(urlString)
                } catch (_: Exception) {
                    continue
                }
                val height = quality.optString("quality").toIntOrNull()
                formats += VideoFormat(
                    id = "twitch-gql-$index",
                    label = height?.let { "${it}p" } ?: "Download",
                    url = url,
                    fileExtension = "mp4",
                    quality = height,
                    isAudioOnly = false
                )
            }

            if (formats.isEmpty()) return null
            formats.sortByDescending { it.quality ?: 0 }

            VideoMetadata(
                title = title,
                author = author ?: "Twitch",
                thumbnailURL = thumbnail,
                platform = VideoPlatform.TWITCH,
                sourceURL = sourceURL,
                formats = formats.take(4),
                allowsRealDownload = true,
                usesYTDLP = false
            )
        }
    } catch (_: Exception) {
        null
    }
}

private fun twitchClipSlug(url: URL): String? {
    val host = url.host?.lowercase().orEmpty()
    val parts = url.path.split('/').filter { it.isNotEmpty() }
    if (host.contains("clips.twitch.tv")) {
        val first = parts.firstOrNull()
        if (first != null && first.isNotEmpty() && first != "embed") {
            return first.substringBefore('?')
        }
    }
    val clipIndex = parts.indexOf("clip")
    if (clipIndex >= 0 && clipIndex + 1 < parts.size) {
        return parts[clipIndex + 1].substringBefore('?')
    }
    return null
}

// endregion

// region Streamable

private suspend fun AndroidPageVideoExtractor.extractStreamable(sourceURL: URL): VideoMetadata {
    val shortcode = streamableShortcode(sourceURL)
        ?: throw PageExtractionError.Network("Couldn’t read that Streamable link.")
    val apiURL = "https://api.streamable.com/videos/$shortcode"

    return try {
        HttpClients.get(
            apiURL,
            userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            headers = mapOf("Accept" to "application/json")
        ).use { response ->
            if (response.code !in 200 until 300) throw PageExtractionError.NoMediaFound
            val json = response.jsonOrNull() ?: throw PageExtractionError.NoMediaFound
            metadataFromStreamable(json, sourceURL) ?: throw PageExtractionError.NoMediaFound
        }
    } catch (e: PageExtractionError) {
        throw e
    } catch (_: Exception) {
        try {
            val metadata = extractFromHTMLPage(sourceURL, VideoPlatform.STREAMABLE)
            if (metadata != null && metadata.formats.any { !it.isAudioOnly }) {
                return metadata
            }
        } catch (_: Exception) {
            // fall through
        }
        throw PageExtractionError.Network("Couldn’t resolve this Streamable video.")
    }
}

private fun AndroidPageVideoExtractor.metadataFromStreamable(
    json: JSONObject,
    sourceURL: URL
): VideoMetadata? {
    val files = json.optJSONObject("files") ?: JSONObject()
    val formats = mutableListOf<VideoFormat>()
    val preferred = listOf("mp4", "mp4-mobile", "original")
    val seen = mutableSetOf<String>()
    val keys = preferred + files.keys().asSequence().toList().filter { it !in preferred }

    for (key in keys) {
        val entry = files.optJSONObject(key) ?: continue
        var urlString = entry.optString("url")
        if (urlString.isEmpty()) continue
        if (urlString.startsWith("//")) urlString = "https:$urlString"
        if (!seen.add(urlString)) continue
        val url = try {
            URL(urlString)
        } catch (_: Exception) {
            continue
        }
        val height = entry.optInt("height", 0).takeIf { it > 0 }
        formats += VideoFormat(
            id = "streamable-$key",
            label = height?.let { "${it}p" } ?: if (key == "mp4") "Best available" else key,
            url = url,
            fileExtension = "mp4",
            quality = height,
            isAudioOnly = false
        )
    }

    if (formats.isEmpty()) return null

    val title = json.optString("title").trim().ifEmpty { null }
    var thumbRaw = json.optString("thumbnail_url")
    if (thumbRaw.startsWith("//")) thumbRaw = "https:$thumbRaw"
    val thumbnail = thumbRaw.ifEmpty { null }?.let { runCatching { URL(it) }.getOrNull() }

    return VideoMetadata(
        title = title ?: "Streamable video",
        author = "Streamable",
        thumbnailURL = thumbnail,
        platform = VideoPlatform.STREAMABLE,
        sourceURL = sourceURL,
        formats = formats,
        allowsRealDownload = true,
        usesYTDLP = false
    )
}

private fun streamableShortcode(url: URL): String? {
    val parts = url.path.split('/').filter { it.isNotEmpty() }
    // streamable.com/abc12 or /e/abc12
    val eIndex = parts.indexOf("e")
    if (eIndex >= 0 && eIndex + 1 < parts.size) return parts[eIndex + 1]

    val first = parts.firstOrNull() ?: return null
    if (first.isEmpty()) return null
    if (first == "o" || first == "s") return parts.getOrNull(1)
    if (!first.all { it.isLetterOrDigit() }) return null
    return first
}

// endregion

// region Rumble

private suspend fun AndroidPageVideoExtractor.extractRumble(sourceURL: URL): VideoMetadata {
    extractRumbleFromPage(sourceURL)?.let { return it }
    val embedID = rumbleEmbedID(sourceURL)
    if (embedID != null) {
        extractRumbleEmbedJS(embedID, sourceURL)?.let { return it }
    }
    throw PageExtractionError.Network(
        "Couldn’t resolve this Rumble video. It may be live-only or unavailable in your region."
    )
}

private suspend fun AndroidPageVideoExtractor.extractRumbleFromPage(
    sourceURL: URL
): VideoMetadata? = withContext(Dispatchers.IO) {
    try {
        HttpClients.get(
            sourceURL.toString(),
            userAgent = HttpClients.DESKTOP_UA,
            headers = mapOf("Accept" to "text/html,application/xhtml+xml")
        ).use { response ->
            if (response.code !in 200 until 400) return@withContext null
            val html = response.bodyString() ?: return@withContext null

            // Prefer embed id → embedJS for clean mp4 map.
            val embedID = firstMatch(html, """rumble\.com/embed/([A-Za-z0-9_-]+)""")
                ?: firstMatch(html, """"video"\s*:\s*"(v[A-Za-z0-9]+)"""")
                ?: rumbleEmbedID(sourceURL)
            if (embedID != null) {
                extractRumbleEmbedJS(embedID, sourceURL)?.let { return@withContext it }
            }

            // Fallback: scrape mp4 urls from page JSON blobs.
            val media = inlineMP4URLs(html).filter {
                val host = it.host?.lowercase().orEmpty()
                host.contains("rumble") || host.contains("rmbl.ws") || host.contains("cdn")
            }
            if (media.isEmpty()) return@withContext null

            val title = metaContent(html, "og:title")
                ?: tagContent(html, "title")
                ?: "Rumble video"
            val thumbnail = metaContent(html, "og:image")?.let { runCatching { URL(it) }.getOrNull() }
            val formats = media.take(4).mapIndexed { index, url ->
                VideoFormat(
                    id = "rumble-page-$index",
                    label = if (index == 0) "Best available" else "Option ${index + 1}",
                    url = url,
                    fileExtension = "mp4",
                    quality = null,
                    isAudioOnly = false
                )
            }
            VideoMetadata(
                title = htmlDecode(title),
                author = "Rumble",
                thumbnailURL = thumbnail,
                platform = VideoPlatform.RUMBLE,
                sourceURL = sourceURL,
                formats = formats,
                allowsRealDownload = true,
                usesYTDLP = false
            )
        }
    } catch (_: Exception) {
        null
    }
}

private fun AndroidPageVideoExtractor.extractRumbleEmbedJS(
    embedID: String,
    sourceURL: URL
): VideoMetadata? {
    val cleaned = embedID.replace("/", "")
    val apiURL = "https://rumble.com/embedJS/u3/?request=video&ver=2&v=$cleaned"
    return try {
        HttpClients.get(
            apiURL,
            userAgent = HttpClients.DESKTOP_UA,
            headers = mapOf(
                "Accept" to "application/json",
                "Referer" to "https://rumble.com/"
            )
        ).use { response ->
            if (response.code !in 200 until 300) return null
            val json = response.jsonOrNull() ?: return null
            metadataFromRumbleEmbed(json, sourceURL)
        }
    } catch (_: Exception) {
        null
    }
}

private fun AndroidPageVideoExtractor.metadataFromRumbleEmbed(
    json: JSONObject,
    sourceURL: URL
): VideoMetadata? {
    // ua.mp4.{height: url} or u.mp4 / ua.webm
    val ua = json.optJSONObject("ua")
    val mp4Map = ua?.optJSONObject("mp4")
        ?: json.optJSONObject("u")?.optJSONObject("mp4")
    val formats = mutableListOf<VideoFormat>()

    if (mp4Map != null) {
        val ranked = mutableListOf<Triple<Int, String, String>>()
        val keys = mp4Map.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = mp4Map.opt(key)
            val urlString = when (value) {
                is String -> value
                is JSONObject -> value.optString("url").ifEmpty { null }
                else -> null
            } ?: continue
            ranked += Triple(key.toIntOrNull() ?: 0, key, urlString)
        }
        ranked.sortByDescending { it.first }
        for ((height, key, urlString) in ranked) {
            val url = try {
                URL(urlString)
            } catch (_: Exception) {
                continue
            }
            formats += VideoFormat(
                id = "rumble-$key",
                label = if (height > 0) "${height}p" else key,
                url = url,
                fileExtension = "mp4",
                quality = height.takeIf { it > 0 },
                isAudioOnly = false
            )
            if (formats.size >= 4) break
        }
    }

    if (formats.isEmpty()) {
        val hlsRoot = ua?.optJSONObject("hls")
        val hls = hlsRoot?.optJSONObject("auto") ?: hlsRoot
        var urlString = hls?.optString("url")?.ifEmpty { null }
        if (urlString == null && hls != null) {
            val keys = hls.keys()
            while (keys.hasNext() && urlString == null) {
                val nested = hls.optJSONObject(keys.next())
                urlString = nested?.optString("url")?.ifEmpty { null }
            }
        }
        if (urlString != null) {
            try {
                formats += VideoFormat(
                    id = "rumble-hls",
                    label = "Stream (HLS)",
                    url = URL(urlString),
                    fileExtension = "mp4",
                    quality = null,
                    isAudioOnly = false,
                    isHlsStream = true
                )
            } catch (_: Exception) {
                // ignore
            }
        }
    }

    if (formats.isEmpty()) return null

    val title = json.optString("title").trim().ifEmpty { null }
    val author = json.optJSONObject("author")?.optString("name")?.ifEmpty { null }
        ?: json.optJSONObject("channel")?.optString("name")?.ifEmpty { null }
        ?: "Rumble"
    val thumbnail = json.optString("i").ifEmpty { null }?.let { runCatching { URL(it) }.getOrNull() }
        ?: json.optString("thumbnail").ifEmpty { null }?.let { runCatching { URL(it) }.getOrNull() }

    return VideoMetadata(
        title = title ?: "Rumble video",
        author = author,
        thumbnailURL = thumbnail,
        platform = VideoPlatform.RUMBLE,
        sourceURL = sourceURL,
        formats = formats,
        allowsRealDownload = true,
        usesYTDLP = false
    )
}

private fun rumbleEmbedID(url: URL): String? {
    val parts = url.path.split('/').filter { it.isNotEmpty() }
    val embedIndex = parts.indexOf("embed")
    if (embedIndex >= 0 && embedIndex + 1 < parts.size) {
        return parts[embedIndex + 1]
    }
    // Paths like /vXXXXX-title.html sometimes expose v-id in query `v`
    val query = url.query ?: return null
    return query.split('&')
        .map { it.split('=', limit = 2) }
        .firstOrNull { it[0] == "v" }
        ?.getOrNull(1)
        ?.let { URLDecoder.decode(it, "UTF-8") }
}

// endregion
