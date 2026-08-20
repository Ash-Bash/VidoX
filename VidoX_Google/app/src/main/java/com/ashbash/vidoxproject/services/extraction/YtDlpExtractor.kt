package com.ashbash.vidoxproject.services.extraction

import android.content.Context
import com.ashbash.vidoxproject.models.VideoFormat
import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.models.VideoPlatform
import com.ashbash.vidoxproject.util.URLNormalizer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.URL

const val YOUTUBE_EXTRACTOR_ARGS =
    "youtube:player_client=android_vr,tv,-web,-mweb,-ios,-android,-android_sdkless"

/** Fetch Info only — fewer clients, no webpage skip (that triggers “page needs to be reloaded”). */
const val YOUTUBE_EXTRACT_ARGS =
    "youtube:player_client=android_vr,tv"

/** Merge video+audio first, then any single file so lookup/download don’t fail empty. */
fun youtubeSelector(maxHeight: Int? = null): String {
    val height = maxHeight?.let { "[height<=$it]" } ?: ""
    return "bv*${height}[ext=mp4]+ba[ext=m4a]/bv*$height+ba/b*$height"
}

const val YOUTUBE_FORMAT_SELECTOR =
    "bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b*"

/** yt-dlp-backed social extractor (Mac-equivalent path). */
class YtDlpExtractor(private val appContext: Context) : VideoExtracting {
    override suspend fun extract(from: URL): VideoMetadata = withContext(Dispatchers.IO) {
        YtDlpTool.ensureInitialized(appContext)
        val detected = VideoPlatform.detect(from.toString())
        val platform = if (detected == VideoPlatform.UNKNOWN) VideoPlatform.WEB else detected

        if (platform == VideoPlatform.FACEBOOK) {
            return@withContext extractFacebook(from)
        }

        val extra = if (platform == VideoPlatform.YOUTUBE) {
            listOf("--extractor-args" to YOUTUBE_EXTRACT_ARGS)
        } else emptyList()

        extractGeneric(
            if (platform == VideoPlatform.INSTAGRAM) URLNormalizer.instagramCanonicalURL(from) else from,
            platform,
            extra
        )
    }

    private suspend fun extractFacebook(url: URL): VideoMetadata {
        val candidates = mutableListOf(url)
        URLNormalizer.facebookVideoID(url)?.let { id ->
            candidates += URL("https://www.facebook.com/watch/?v=$id")
            candidates += URL("https://m.facebook.com/watch/?v=$id&_rdr")
        }
        var last: Exception = YtDlpError.InvalidMetadata
        for (candidate in candidates.distinctBy { it.toString() }) {
            try {
                return extractGeneric(candidate, VideoPlatform.FACEBOOK, emptyList())
            } catch (e: Exception) {
                last = e
            }
        }
        throw last
    }

    private suspend fun extractGeneric(
        url: URL,
        platform: VideoPlatform,
        extra: List<Pair<String, String?>>
    ): VideoMetadata {
        val json = YtDlpTool.fetchJson(url.toString(), extra)
        val title = json.optString("title").trim().ifEmpty { "${platform.displayName} video" }
        val author = json.optString("uploader").ifEmpty { null }
            ?: json.optString("channel").ifEmpty { null }
        val thumbnail = json.optString("thumbnail").ifEmpty { null }?.let { URL(it) }
        val defaultExt = json.optString("ext").ifEmpty { "mp4" }
        val rawFormats = json.optJSONArray("formats") ?: JSONArray()
        var formats = curatedFormats(rawFormats, url, platform)
        if (formats.isEmpty()) {
            formats = listOf(
                VideoFormat(
                    id = "best",
                    label = "Best available",
                    url = url,
                    fileExtension = defaultExt,
                    quality = null,
                    isAudioOnly = false,
                    ytdlpFormatSelector = if (platform == VideoPlatform.YOUTUBE) {
                        youtubeSelector()
                    } else {
                        "bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b"
                    }
                )
            )
        }
        return VideoMetadata(
            title = title,
            author = author,
            thumbnailURL = thumbnail,
            platform = platform,
            sourceURL = url,
            formats = formats,
            allowsRealDownload = true,
            usesYTDLP = true
        )
    }

    private fun curatedFormats(raw: JSONArray, pageURL: URL, platform: VideoPlatform): List<VideoFormat> {
        if (platform == VideoPlatform.YOUTUBE) {
            return youtubeDownloadFormats(raw, pageURL)
        }

        val progressive = mutableListOf<Triple<Int, String, String>>()
        for (i in 0 until raw.length()) {
            val entry = raw.optJSONObject(i) ?: continue
            val id = entry.optString("format_id")
            if (id.isEmpty()) continue
            val height = entry.optInt("height", -1)
            val vcodec = entry.optString("vcodec", "none")
            val acodec = entry.optString("acodec", "none")
            if (height < 360 || vcodec == "none" || acodec == "none") continue
            val ext = entry.optString("ext").ifEmpty { "mp4" }
            progressive += Triple(height, id, ext)
        }
        progressive.sortByDescending { it.first }

        val result = mutableListOf<VideoFormat>()
        val seenHeights = mutableSetOf<Int>()
        result += VideoFormat(
            id = "best-mp4",
            label = "Best (single file)",
            url = pageURL,
            fileExtension = "mp4",
            quality = progressive.firstOrNull()?.first,
            isAudioOnly = false,
            ytdlpFormatSelector = "bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b"
        )
        for ((height, id, ext) in progressive) {
            if (!seenHeights.add(height)) continue
            result += VideoFormat(
                id = id,
                label = "${height}p",
                url = pageURL,
                fileExtension = ext,
                quality = height,
                isAudioOnly = false,
                ytdlpFormatSelector = id
            )
            if (result.size >= 5) break
        }
        appendAudioFormat(raw, pageURL, result)
        return result
    }

    private fun youtubeDownloadFormats(raw: JSONArray, pageURL: URL): List<VideoFormat> {
        val heights = mutableSetOf<Int>()
        for (i in 0 until raw.length()) {
            val entry = raw.optJSONObject(i) ?: continue
            val id = entry.optString("format_id")
            if (id == "18" || id.startsWith("18-") || id == "22" || id.startsWith("22-")) continue
            val height = entry.optInt("height", -1)
            val vcodec = entry.optString("vcodec", "none")
            if (height < 360 || vcodec == "none") continue
            heights += height
        }
        val sortedHeights = heights.sortedDescending()
        val result = mutableListOf<VideoFormat>()
        val bestHeight = sortedHeights.firstOrNull()
        if (bestHeight != null) {
            result += VideoFormat(
                id = "yt-$bestHeight",
                label = "${bestHeight}p",
                url = pageURL,
                fileExtension = "mp4",
                quality = bestHeight,
                isAudioOnly = false,
                ytdlpFormatSelector = youtubeSelector()
            )
            for (height in sortedHeights.drop(1).take(3)) {
                result += VideoFormat(
                    id = "yt-$height",
                    label = "${height}p",
                    url = pageURL,
                    fileExtension = "mp4",
                    quality = height,
                    isAudioOnly = false,
                    ytdlpFormatSelector = youtubeSelector(height)
                )
            }
        } else {
            result += VideoFormat(
                id = "best-mp4",
                label = "Best quality",
                url = pageURL,
                fileExtension = "mp4",
                quality = null,
                isAudioOnly = false,
                ytdlpFormatSelector = youtubeSelector()
            )
        }
        appendAudioFormat(raw, pageURL, result)
        return result
    }

    private fun appendAudioFormat(raw: JSONArray, pageURL: URL, result: MutableList<VideoFormat>) {
        for (i in 0 until raw.length()) {
            val entry = raw.optJSONObject(i) ?: continue
            val vcodec = entry.optString("vcodec", "none")
            val acodec = entry.optString("acodec", "none")
            val id = entry.optString("format_id")
            if (vcodec == "none" && acodec != "none" && id.isNotEmpty()) {
                result += VideoFormat(
                    id = "audio-$id",
                    label = "Audio only",
                    url = pageURL,
                    fileExtension = entry.optString("ext").ifEmpty { "m4a" },
                    quality = entry.optInt("abr", 0).takeIf { it > 0 },
                    isAudioOnly = true,
                    ytdlpFormatSelector = id
                )
                return
            }
        }
    }

    private fun JSONObject.optString(key: String): String =
        if (has(key) && !isNull(key)) optString(key) else ""
}
