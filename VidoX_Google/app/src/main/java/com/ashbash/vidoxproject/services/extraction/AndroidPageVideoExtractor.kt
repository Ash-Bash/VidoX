package com.ashbash.vidoxproject.services.extraction

import com.ashbash.vidoxproject.models.VideoFormat
import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.models.VideoPlatform
import com.ashbash.vidoxproject.util.URLNormalizer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URL
import java.net.URLDecoder
import java.util.regex.Pattern

/**
 * Android page extractor — resolves real media URLs without relying on yt-dlp.
 * Port of Apple [IOSPageVideoExtractor]; uses [HttpClients] for shared UA / timeouts.
 */
class AndroidPageVideoExtractor : VideoExtracting {

    override suspend fun extract(from: URL): VideoMetadata = withContext(Dispatchers.IO) {
        val detected = VideoPlatform.detect(from.toString())
        val platform = if (detected == VideoPlatform.UNKNOWN) VideoPlatform.WEB else detected

        if (platform == VideoPlatform.YOUTUBE) {
            val videoID = youtubeVideoID(from)
            if (videoID != null) {
                return@withContext extractYouTube(videoID, from)
            }
        }

        if (platform == VideoPlatform.INSTAGRAM) {
            return@withContext extractInstagram(from)
        }

        if (platform == VideoPlatform.FACEBOOK) {
            return@withContext extractFacebook(from)
        }

        if (platform == VideoPlatform.TIKTOK) {
            return@withContext extractTikTok(from)
        }

        extractKnownPlatform(from, platform)?.let { return@withContext it }

        extractFromHTMLPage(from, platform)?.let { return@withContext it }

        throw PageExtractionError.NoMediaFound
    }

    // region Facebook

    private suspend fun extractFacebook(from: URL): VideoMetadata {
        val resolvedURL = resolveFacebookURL(from)
        raceFacebookExtractors(resolvedURL, from)?.let { return it }
        throw PageExtractionError.Network(
            "Couldn’t resolve this Facebook video. Public watch/reel links work best — private, friends-only, or expired share links can’t be opened. Try again."
        )
    }

    private suspend fun raceFacebookExtractors(pageURL: URL, sourceURL: URL): VideoMetadata? {
        val blocks = mutableListOf<suspend () -> VideoMetadata?>(
            { extractFacebookViaGetMyFB(pageURL, sourceURL) },
            { extractViaSnapSave(pageURL, sourceURL, VideoPlatform.FACEBOOK) },
            {
                try {
                    extractFacebookFromWebpage(pageURL, sourceURL)
                } catch (_: Exception) {
                    null
                }
            }
        )

        val videoID = URLNormalizer.facebookVideoID(pageURL)
            ?: URLNormalizer.facebookVideoID(sourceURL)
        if (videoID != null) {
            val watchURL = URL("https://www.facebook.com/watch/?v=$videoID")
            if (watchURL.toString() != pageURL.toString()) {
                blocks += { extractFacebookViaGetMyFB(watchURL, sourceURL) }
                blocks += {
                    try {
                        extractFacebookFromWebpage(watchURL, sourceURL)
                    } catch (_: Exception) {
                        null
                    }
                }
            }
        }

        return raceFirst(*blocks.toTypedArray())
    }

    private fun resolveFacebookURL(url: URL): URL {
        val host = url.host?.lowercase().orEmpty()
        val path = url.path.lowercase()
        val needsResolve = host.contains("fb.watch")
            || host == "fb.me"
            || path.contains("/share/")
            || path.contains("/flx/warn")
        if (!needsResolve) return url

        return try {
            HttpClients.get(
                url.toString(),
                userAgent = HttpClients.DESKTOP_UA,
                headers = mapOf(
                    "Accept" to "text/html,application/xhtml+xml",
                    "Accept-Language" to "en-US,en;q=0.9"
                )
            ).use { response ->
                val finalURL = URL(response.request.url.toString())
                val videoID = URLNormalizer.facebookVideoID(finalURL)
                if (videoID != null) {
                    URL("https://www.facebook.com/watch/?v=$videoID")
                } else {
                    finalURL
                }
            }
        } catch (_: Exception) {
            url
        }
    }

    private fun extractFacebookViaGetMyFB(pageURL: URL, sourceURL: URL): VideoMetadata? {
        return try {
            HttpClients.postForm(
                "https://getmyfb.com/process",
                form = mapOf(
                    "id" to pageURL.toString(),
                    "locale" to "en_US"
                ),
                userAgent = HttpClients.DESKTOP_UA,
                headers = mapOf(
                    "Origin" to "https://getmyfb.com",
                    "Referer" to "https://getmyfb.com/"
                )
            ).use { response ->
                if (response.code !in 200 until 300) return null
                val html = response.bodyString() ?: return null
                metadataFromGetMyFBHTML(html, sourceURL)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun metadataFromGetMyFBHTML(html: String, sourceURL: URL): VideoMetadata? {
        val formats = mutableListOf<VideoFormat>()
        val seen = mutableSetOf<String>()

        // Prefer labeled rows: "720p(HD)" / "360p(SD)" with proxy download hrefs.
        val labeled = Pattern.compile(
            """(\d{3,4}p\s*\((?:HD|SD)\)|\d{3,4}p|HD|SD)\s*<a[^>]+href=["'](https://ssscdn\.io/getmyfb/[^"']+)["']""",
            Pattern.CASE_INSENSITIVE or Pattern.DOTALL
        )
        val labeledMatcher = labeled.matcher(html)
        while (labeledMatcher.find()) {
            val label = labeledMatcher.group(1).trim()
            val mediaURL = try {
                URL(labeledMatcher.group(2))
            } catch (_: Exception) {
                continue
            }
            if (!seen.add(mediaURL.toString())) continue
            val quality = qualityHint(label)
            formats += VideoFormat(
                id = "fb-getmyfb-${formats.size}",
                label = if (
                    label.contains('p') ||
                    label.contains("HD", ignoreCase = true) ||
                    label.contains("SD", ignoreCase = true)
                ) {
                    label
                } else {
                    quality?.let { "${it}p" } ?: "Download"
                },
                url = mediaURL,
                fileExtension = "mp4",
                quality = quality,
                isAudioOnly = false
            )
        }

        if (formats.isEmpty()) {
            val loose = Pattern.compile(
                """href=["'](https://ssscdn\.io/getmyfb/[^"']+)["']""",
                Pattern.CASE_INSENSITIVE
            )
            val looseMatcher = loose.matcher(html)
            while (looseMatcher.find()) {
                val mediaURL = try {
                    URL(looseMatcher.group(1))
                } catch (_: Exception) {
                    continue
                }
                if (!seen.add(mediaURL.toString())) continue
                formats += VideoFormat(
                    id = "fb-getmyfb-${formats.size}",
                    label = if (formats.isEmpty()) "Best available" else "Option ${formats.size + 1}",
                    url = mediaURL,
                    fileExtension = "mp4",
                    quality = if (formats.isEmpty()) 720 else 360,
                    isAudioOnly = false
                )
            }
        }

        if (formats.isEmpty()) return null
        formats.sortByDescending { it.quality ?: 0 }

        val title = firstMatch(html, """class="results-item-text">\s*([^<]+)""")
            ?.trim()
            ?.let { htmlDecode(it) }
        val thumbnail = firstMatch(html, """class="results-item-image"[^>]*src="([^"]+)"""")
            ?.let { runCatching { URL(it) }.getOrNull() }

        return VideoMetadata(
            title = if (!title.isNullOrEmpty()) title else "Facebook video",
            author = "Facebook",
            thumbnailURL = thumbnail,
            platform = VideoPlatform.FACEBOOK,
            sourceURL = sourceURL,
            formats = formats.take(4),
            allowsRealDownload = true,
            usesYTDLP = false
        )
    }

    private fun extractViaSnapSave(
        pageURL: URL,
        sourceURL: URL,
        platform: VideoPlatform,
        client: OkHttpClient = HttpClients.default
    ): VideoMetadata? {
        return try {
            HttpClients.postForm(
                "https://snapsave.app/action.php",
                form = mapOf("url" to pageURL.toString()),
                client = client,
                userAgent = HttpClients.DESKTOP_UA,
                headers = mapOf(
                    "Origin" to "https://snapsave.app",
                    "Referer" to "https://snapsave.app/"
                )
            ).use { response ->
                if (response.code !in 200 until 300) return null
                val script = response.bodyString() ?: return null
                val decoded = decodeSnapSavePayload(script) ?: return null
                metadataFromSnapSaveHTML(decoded, sourceURL, platform)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun metadataFromSnapSaveHTML(
        html: String,
        sourceURL: URL,
        platform: VideoPlatform
    ): VideoMetadata? {
        val formats = mutableListOf<VideoFormat>()
        val seen = mutableSetOf<String>()

        val labeled = Pattern.compile(
            """<td[^>]*class="[^"]*video-quality[^"]*"[^>]*>\s*([^<]+?)\s*</td>\s*<td[^>]*>.*?<a[^>]+href=["'](https://[^"']+)["']""",
            Pattern.CASE_INSENSITIVE or Pattern.DOTALL
        )
        val labeledMatcher = labeled.matcher(html)
        while (labeledMatcher.find()) {
            val label = labeledMatcher.group(1).trim()
            if (label.contains("audio", ignoreCase = true)) continue
            val raw = htmlDecode(labeledMatcher.group(2))
            val mediaURL = try {
                URL(raw)
            } catch (_: Exception) {
                continue
            }
            if (!seen.add(mediaURL.toString())) continue
            formats += VideoFormat(
                id = "${platform.rawValue}-snapsave-${formats.size}",
                label = label.ifEmpty { "Download" },
                url = mediaURL,
                fileExtension = "mp4",
                quality = qualityHint(label),
                isAudioOnly = false
            )
        }

        if (formats.isEmpty()) {
            val rapid = Pattern.compile(
                """href=["'](https://d\.rapidcdn\.app/[^"']+)["']""",
                Pattern.CASE_INSENSITIVE
            )
            val rapidMatcher = rapid.matcher(html)
            while (rapidMatcher.find()) {
                val mediaURL = try {
                    URL(rapidMatcher.group(1))
                } catch (_: Exception) {
                    continue
                }
                if (mediaURL.path.contains("/thumb")) continue
                if (!seen.add(mediaURL.toString())) continue
                formats += VideoFormat(
                    id = "${platform.rawValue}-snapsave-${formats.size}",
                    label = if (formats.isEmpty()) "Best available" else "Option ${formats.size + 1}",
                    url = mediaURL,
                    fileExtension = "mp4",
                    quality = if (formats.isEmpty()) 720 else null,
                    isAudioOnly = false
                )
            }
        }

        if (formats.isEmpty()) return null

        val title = firstMatch(html, """alt=["']([^"']+)["']""")
            ?: metaContent(html, "og:title")
            ?: "${platform.displayName} video"
        val thumbnail = firstMatch(html, """src=["'](https://d\.rapidcdn\.app/thumb[^"']+)["']""")
            ?.let { runCatching { URL(it) }.getOrNull() }
            ?: metaContent(html, "og:image")?.let { runCatching { URL(it) }.getOrNull() }

        return VideoMetadata(
            title = htmlDecode(title),
            author = platform.displayName,
            thumbnailURL = thumbnail,
            platform = platform,
            sourceURL = sourceURL,
            formats = formats.take(4),
            allowsRealDownload = true,
            usesYTDLP = false
        )
    }

    /** Decode snapsave’s packed `eval(function(h,u,n,t,e,r){...})` response into HTML. */
    private fun decodeSnapSavePayload(script: String): String? {
        val outer = Pattern.compile("""\}\("([^"]+)",(\d+),"([^"]+)",(\d+),(\d+),(\d+)\)\)""")
        val outerMatcher = outer.matcher(script)
        if (!outerMatcher.find()) return null

        val h = outerMatcher.group(1) ?: return null
        val n = outerMatcher.group(3) ?: return null
        val t = outerMatcher.group(4)?.toIntOrNull() ?: return null
        val e = outerMatcher.group(5)?.toIntOrNull() ?: return null
        if (e < 0 || e >= n.length) return null

        val alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/"
        fun intPower(base: Int, exp: Int): Int {
            var result = 1
            repeat(exp) { result *= base }
            return result
        }
        fun decodeToken(d: String, fromBase: Int, toBase: Int): String {
            val source = alphabet.take(fromBase)
            val dest = alphabet.take(toBase)
            var value = 0
            d.reversed().forEachIndexed { index, char ->
                val digit = source.indexOf(char)
                if (digit >= 0) value += digit * intPower(fromBase, index)
            }
            if (value == 0) return "0"
            var out = ""
            var remaining = value
            while (remaining > 0) {
                out = dest[remaining % toBase] + out
                remaining /= toBase
            }
            return out
        }

        val delimiter = n[e]
        val output = StringBuilder()
        var index = 0
        while (index < h.length) {
            val tokenBuilder = StringBuilder()
            while (index < h.length && h[index] != delimiter) {
                tokenBuilder.append(h[index])
                index++
            }
            if (index < h.length) index++
            var token = tokenBuilder.toString()
            n.forEachIndexed { position, character ->
                token = token.replace(character.toString(), position.toString())
            }
            val code = decodeToken(token, e, 10).toIntOrNull() ?: continue
            val scalar = code - t
            if (scalar < 0) continue
            output.append(scalar.toChar())
        }

        val packed = output.toString()
        return try {
            URLDecoder.decode(packed, "UTF-8")
        } catch (_: Exception) {
            packed
        }
    }

    private fun extractFacebookFromWebpage(pageURL: URL, sourceURL: URL): VideoMetadata? {
        HttpClients.get(
            pageURL.toString(),
            userAgent = HttpClients.DESKTOP_UA,
            headers = mapOf(
                "Accept" to "text/html,application/xhtml+xml",
                "Accept-Language" to "en-US,en;q=0.9",
                "Cookie" to "locale=en_US"
            )
        ).use { response ->
            if (response.code !in 200 until 400) return null
            val html = response.bodyString() ?: return null
            val media = facebookMediaURLs(html)
            if (media.isEmpty()) return null

            val title = metaContent(html, "og:title")
                ?: tagContent(html, "title")
                ?: "Facebook video"
            val author = metaContent(html, "og:site_name") ?: "Facebook"
            val thumbnail = metaContent(html, "og:image")?.let { runCatching { URL(it) }.getOrNull() }

            val formats = media.take(4).mapIndexed { index, entry ->
                VideoFormat(
                    id = "fb-page-$index",
                    label = entry.label,
                    url = entry.url,
                    fileExtension = "mp4",
                    quality = entry.quality,
                    isAudioOnly = false,
                    isHlsStream = entry.url.toString().lowercase().contains("m3u8")
                )
            }

            return VideoMetadata(
                title = htmlDecode(title.trim()),
                author = author,
                thumbnailURL = thumbnail,
                platform = VideoPlatform.FACEBOOK,
                sourceURL = sourceURL,
                formats = formats,
                allowsRealDownload = true,
                usesYTDLP = false
            )
        }
    }

    private data class MediaCandidate(val url: URL, val label: String, val quality: Int?)

    private fun facebookMediaURLs(html: String): List<MediaCandidate> {
        val keys = listOf(
            """playable_url_quality_hd"\s*:\s*"([^"]+)"""" to ("HD" to 720),
            """browser_native_hd_url"\s*:\s*"([^"]+)"""" to ("HD" to 720),
            """hd_src_no_ratelimit"\s*:\s*"([^"]+)"""" to ("HD" to 720),
            """hd_src"\s*:\s*"([^"]+)"""" to ("HD" to 720),
            """playable_url"\s*:\s*"([^"]+)"""" to ("SD" to 360),
            """browser_native_sd_url"\s*:\s*"([^"]+)"""" to ("SD" to 360),
            """sd_src_no_ratelimit"\s*:\s*"([^"]+)"""" to ("SD" to 360),
            """sd_src"\s*:\s*"([^"]+)"""" to ("SD" to 360),
            """progressive_url"\s*:\s*"([^"]+)"""" to ("Progressive" to 480)
        )

        val results = mutableListOf<MediaCandidate>()
        val seen = mutableSetOf<String>()

        for ((pattern, meta) in keys) {
            val matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html)
            if (matcher.find()) {
                val cleaned = decodeFacebookURL(matcher.group(1))
                val mediaURL = try {
                    URL(cleaned)
                } catch (_: Exception) {
                    continue
                }
                if (!seen.add(cleaned)) continue
                val lower = cleaned.lowercase()
                if (!(lower.contains(".mp4") || lower.contains("m3u8") ||
                        lower.contains("fbcdn") || lower.contains("video"))
                ) {
                    continue
                }
                results += MediaCandidate(mediaURL, meta.first, meta.second)
            }
        }
        return results
    }

    private fun decodeFacebookURL(raw: String): String =
        htmlDecode(
            raw.replace("\\/", "/")
                .replace("\\u0025", "%")
                .replace("\\u0026", "&")
                .replace("\\u003D", "=")
                .replace("\\u002F", "/")
                .replace("&amp;", "&")
        )

    // endregion

    // region TikTok

    private suspend fun extractTikTok(from: URL): VideoMetadata {
        val resolvedURL = resolveTikTokURL(from)

        extractTikTokViaTikwm(resolvedURL, from)?.let { return it }

        try {
            extractTikTokFromWebpage(resolvedURL, from)?.let { return it }
        } catch (_: Exception) {
            // fall through
        }

        extractTikTokViaCommunityAPI(resolvedURL, from)?.let { return it }

        throw PageExtractionError.Network(
            "Couldn’t resolve this TikTok video. It may be private, region-locked, or deleted. Try again."
        )
    }

    private fun resolveTikTokURL(url: URL): URL {
        val host = url.host?.lowercase().orEmpty()
        if (!host.contains("vm.tiktok.com") && !host.contains("vt.tiktok.com")) {
            return url
        }
        return try {
            HttpClients.get(url.toString(), userAgent = HttpClients.IPHONE_UA).use { response ->
                URL(response.request.url.toString())
            }
        } catch (_: Exception) {
            url
        }
    }

    private fun extractTikTokViaTikwm(pageURL: URL, sourceURL: URL): VideoMetadata? {
        val bases = listOf("https://www.tikwm.com/api/", "https://tikwm.com/api/")
        for (base in bases) {
            val apiURL = "$base?hd=1&url=${URLNormalizer.encodeQuery(pageURL.toString())}"
            try {
                HttpClients.get(
                    apiURL,
                    userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
                    headers = mapOf(
                        "Accept" to "application/json",
                        "Referer" to "https://www.tikwm.com/"
                    )
                ).use { response ->
                    if (response.code !in 200 until 300) return@use
                    val json = response.jsonOrNull() ?: return@use
                    if (json.optInt("code", -1) != 0) return@use
                    val payload = json.optJSONObject("data") ?: return@use
                    metadataFromTikwm(payload, sourceURL)?.let { return it }
                }
            } catch (_: Exception) {
                continue
            }
        }

        // POST form as a second chance (some regions prefer it).
        return try {
            HttpClients.postForm(
                "https://www.tikwm.com/api/",
                form = mapOf(
                    "hd" to "1",
                    "url" to pageURL.toString()
                ),
                userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
                headers = mapOf(
                    "Accept" to "application/json",
                    "Origin" to "https://www.tikwm.com/",
                    "Referer" to "https://www.tikwm.com/"
                )
            ).use { response ->
                if (response.code !in 200 until 300) return null
                val json = response.jsonOrNull() ?: return null
                if (json.optInt("code", -1) != 0) return null
                val payload = json.optJSONObject("data") ?: return null
                metadataFromTikwm(payload, sourceURL)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun metadataFromTikwm(data: JSONObject, sourceURL: URL): VideoMetadata? {
        val title = data.optString("title").trim().ifEmpty { null }
        val authorObj = data.optJSONObject("author")
        val author = authorObj?.optString("unique_id")?.ifEmpty { null }
            ?: authorObj?.optString("nickname")?.ifEmpty { null }
            ?: data.optString("author").ifEmpty { null }
        val thumbnail = data.optString("cover").ifEmpty { null }?.let { runCatching { URL(it) }.getOrNull() }
            ?: data.optString("origin_cover").ifEmpty { null }?.let { runCatching { URL(it) }.getOrNull() }

        val formats = mutableListOf<VideoFormat>()
        // Rank by preference, not file size (HD can be smaller than the default encode).
        val candidates = listOf(
            Triple("hdplay", "HD (no watermark)", 1080),
            Triple("play", "Best (no watermark)", 720),
            Triple("wmplay", "With watermark", 480)
        )
        for ((key, label, rank) in candidates) {
            val urlString = data.optString(key)
            if (urlString.isEmpty()) continue
            val mediaURL = try {
                URL(urlString)
            } catch (_: Exception) {
                continue
            }
            formats += VideoFormat(
                id = "tikwm-$key",
                label = label,
                url = mediaURL,
                fileExtension = "mp4",
                quality = rank,
                isAudioOnly = false
            )
        }
        val music = data.optString("music")
        if (music.isNotEmpty()) {
            try {
                formats += VideoFormat(
                    id = "tikwm-music",
                    label = "Audio only",
                    url = URL(music),
                    fileExtension = "mp3",
                    quality = null,
                    isAudioOnly = true
                )
            } catch (_: Exception) {
                // ignore
            }
        }

        if (formats.none { !it.isAudioOnly }) return null

        return VideoMetadata(
            title = title ?: "TikTok video",
            author = author,
            thumbnailURL = thumbnail,
            platform = VideoPlatform.TIKTOK,
            sourceURL = sourceURL,
            formats = formats,
            allowsRealDownload = true,
            usesYTDLP = false
        )
    }

    private fun extractTikTokFromWebpage(pageURL: URL, sourceURL: URL): VideoMetadata? {
        HttpClients.get(
            pageURL.toString(),
            userAgent = HttpClients.DESKTOP_UA,
            headers = mapOf(
                "Accept" to "text/html,application/xhtml+xml",
                "Accept-Language" to "en-US,en;q=0.9"
            )
        ).use { response ->
            if (response.code !in 200 until 400) return null
            val html = response.bodyString() ?: return null
            val json = tikTokUniversalData(html) ?: return null
            val scope = json.optJSONObject("__DEFAULT_SCOPE__") ?: return null
            val detail = scope.optJSONObject("webapp.video-detail")
                ?: scope.optJSONObject("webapp.reflow.video.detail")
                ?: return null
            val item = detail.optJSONObject("itemInfo")?.optJSONObject("itemStruct") ?: return null
            val video = item.optJSONObject("video") ?: return null

            val title = item.optString("desc").trim().ifEmpty { null }
            val authorObj = item.optJSONObject("author")
            val author = authorObj?.optString("uniqueId")?.ifEmpty { null }
                ?: authorObj?.optString("nickname")?.ifEmpty { null }
            val thumbnail = video.optString("cover").ifEmpty { null }?.let { runCatching { URL(it) }.getOrNull() }
                ?: video.optString("originCover").ifEmpty { null }?.let { runCatching { URL(it) }.getOrNull() }
            val height = video.optInt("height", 0).takeIf { it > 0 }

            val formats = mutableListOf<VideoFormat>()
            val seen = mutableSetOf<String>()

            val bitrateInfo = video.optJSONArray("bitrateInfo")
            if (bitrateInfo != null) {
                for (i in 0 until minOf(bitrateInfo.length(), 5)) {
                    val entry = bitrateInfo.optJSONObject(i) ?: continue
                    val play = entry.optJSONObject("PlayAddr") ?: entry.optJSONObject("playAddr")
                    val urls = play?.optJSONArray("UrlList")
                        ?: play?.optJSONArray("url_list")
                    val first = urls?.optString(0)?.ifEmpty { null } ?: continue
                    if (!seen.add(first)) continue
                    val mediaURL = try {
                        URL(first)
                    } catch (_: Exception) {
                        continue
                    }
                    val h = play?.optInt("Height", 0)?.takeIf { it > 0 }
                        ?: play?.optInt("height", 0)?.takeIf { it > 0 }
                        ?: height
                    formats += VideoFormat(
                        id = "tt-br-$i",
                        label = h?.let { "${it}p" } ?: "Video",
                        url = mediaURL,
                        fileExtension = "mp4",
                        quality = h,
                        isAudioOnly = false
                    )
                }
            }

            for ((key, label) in listOf("downloadAddr" to "Download", "playAddr" to "Play")) {
                val urlString = video.optString(key)
                if (urlString.isEmpty() || !seen.add(urlString)) continue
                try {
                    formats.add(
                        0,
                        VideoFormat(
                            id = "tt-$key",
                            label = label,
                            url = URL(urlString),
                            fileExtension = "mp4",
                            quality = height,
                            isAudioOnly = false
                        )
                    )
                } catch (_: Exception) {
                    // ignore
                }
            }

            if (formats.none { !it.isAudioOnly }) return null

            return VideoMetadata(
                title = title ?: "TikTok video",
                author = author,
                thumbnailURL = thumbnail,
                platform = VideoPlatform.TIKTOK,
                sourceURL = sourceURL,
                formats = formats,
                allowsRealDownload = true,
                usesYTDLP = false
            )
        }
    }

    private fun tikTokUniversalData(html: String): JSONObject? {
        val marker = """id="__UNIVERSAL_DATA_FOR_REHYDRATION__""""
        val markerIndex = html.indexOf(marker)
        if (markerIndex < 0) return null
        val scriptStart = html.indexOf('>', markerIndex)
        if (scriptStart < 0) return null
        val scriptEnd = html.indexOf("</script>", scriptStart)
        if (scriptEnd < 0) return null
        val jsonText = html.substring(scriptStart + 1, scriptEnd).trim()
        return try {
            JSONObject(jsonText)
        } catch (_: Exception) {
            null
        }
    }

    private fun extractTikTokViaCommunityAPI(pageURL: URL, sourceURL: URL): VideoMetadata? {
        val apiURL = "https://tiktok-downbloder.vercel.app/?url=${URLNormalizer.encodeQuery(pageURL.toString())}"
        return try {
            HttpClients.get(
                apiURL,
                userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
                headers = mapOf("Accept" to "application/json")
            ).use { response ->
                if (response.code !in 200 until 300) return null
                val root = response.jsonOrNull() ?: return null
                if (!root.optBoolean("success", false)) return null

                val raw = root.optJSONObject("result")?.optJSONObject("raw")
                val result = raw?.optJSONObject("result")
                    ?: root.optJSONObject("result")
                    ?: JSONObject()

                val videoURLString = result.optString("video").ifEmpty { null }
                    ?: result.optString("play").ifEmpty { null }
                    ?: result.optString("hdplay").ifEmpty { null }
                    ?: return null
                val mediaURL = try {
                    URL(videoURLString)
                } catch (_: Exception) {
                    return null
                }

                val title = result.optString("desc").ifEmpty { null }
                    ?: result.optString("title").ifEmpty { null }
                    ?: "TikTok video"
                val authorObj = result.optJSONObject("author")
                val author = authorObj?.optString("nickname")?.ifEmpty { null }
                    ?: authorObj?.optString("unique_id")?.ifEmpty { null }
                val thumbnail = result.optString("cover").ifEmpty { null }?.let { runCatching { URL(it) }.getOrNull() }
                    ?: authorObj?.optString("avatar")?.ifEmpty { null }?.let { runCatching { URL(it) }.getOrNull() }

                val formats = mutableListOf(
                    VideoFormat(
                        id = "tt-community-video",
                        label = "Best available",
                        url = mediaURL,
                        fileExtension = "mp4",
                        quality = null,
                        isAudioOnly = false
                    )
                )
                val music = result.optString("music")
                if (music.isNotEmpty()) {
                    try {
                        formats += VideoFormat(
                            id = "tt-community-music",
                            label = "Audio only",
                            url = URL(music),
                            fileExtension = "mp3",
                            quality = null,
                            isAudioOnly = true
                        )
                    } catch (_: Exception) {
                        // ignore
                    }
                }

                VideoMetadata(
                    title = title.trim(),
                    author = author,
                    thumbnailURL = thumbnail,
                    platform = VideoPlatform.TIKTOK,
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

    // endregion

    // region Instagram

    private suspend fun extractInstagram(from: URL): VideoMetadata {
        val shortcode = instagramShortcode(from)
            ?: throw PageExtractionError.Network(
                "Couldn’t read that Instagram link. Use a /reel/ or /p/ URL."
            )

        val canonical = URLNormalizer.instagramCanonicalURL(from)
        raceInstagramExtractors(canonical, from, shortcode)?.let { return it }

        throw PageExtractionError.Network(
            "Couldn’t resolve this Instagram video. It may be private, age-restricted, or limited to certain audiences."
        )
    }

    /** SnapSave and public mirrors in parallel; return the first hit and cancel the rest. */
    private suspend fun raceInstagramExtractors(
        canonical: URL,
        sourceURL: URL,
        shortcode: String
    ): VideoMetadata? {
        val blocks = mutableListOf<suspend () -> VideoMetadata?>(
            {
                extractViaSnapSave(
                    canonical,
                    sourceURL,
                    VideoPlatform.INSTAGRAM,
                    client = HttpClients.medium
                )
            }
        )
        for (mirror in instagramMirrorURLs(shortcode)) {
            blocks += {
                try {
                    extractInstagramFromMirror(mirror, sourceURL, shortcode)
                } catch (_: Exception) {
                    null
                }
            }
        }
        return raceFirst(*blocks.toTypedArray())
    }

    private fun instagramShortcode(url: URL): String? {
        val parts = url.path.split('/').filter { it.isNotEmpty() }
        val kindIndex = parts.indexOfFirst { it in setOf("p", "tv", "reel", "reels") }
        if (kindIndex < 0 || kindIndex + 1 >= parts.size) return null
        val code = parts[kindIndex + 1].substringBefore('?')
        if (code.isEmpty() || !code.all { it.isLetterOrDigit() || it == '-' || it == '_' }) return null
        return code
    }

    private fun instagramMirrorURLs(shortcode: String): List<URL> =
        listOf(
            "https://imginn.com/p/$shortcode/",
            "https://imginn.com/reel/$shortcode/",
            "https://www.instagramez.com/p/$shortcode",
            "https://www.instagramez.com/reel/$shortcode"
        ).mapNotNull { runCatching { URL(it) }.getOrNull() }

    private fun extractInstagramFromMirror(
        mirrorURL: URL,
        sourceURL: URL,
        shortcode: String
    ): VideoMetadata? {
        HttpClients.get(
            mirrorURL.toString(),
            client = HttpClients.fast,
            userAgent = HttpClients.IPHONE_UA,
            headers = mapOf(
                "Accept" to "text/html,application/xhtml+xml",
                "Accept-Language" to "en-US,en;q=0.9"
            )
        ).use { response ->
            if (response.code !in 200 until 400) return null
            val html = response.bodyString() ?: return null
            val mediaURLs = instagramMediaURLs(html)
            if (mediaURLs.isEmpty()) return null

            val ogTitle = metaContent(html, "og:title")
                ?: tagContent(html, "title")
                ?: "Instagram video"
            val author = instagramAuthor(ogTitle) ?: "Instagram"
            val title = instagramTitle(ogTitle, shortcode)
            val thumbnail = metaContent(html, "og:image")?.let { runCatching { URL(it) }.getOrNull() }

            val formats = mediaURLs.take(4).mapIndexed { index, media ->
                val isHls = media.toString().lowercase().contains("m3u8")
                VideoFormat(
                    id = "ig-$shortcode-$index",
                    label = if (index == 0) "Best available" else "Option ${index + 1}",
                    url = media,
                    fileExtension = "mp4",
                    quality = null,
                    isAudioOnly = false,
                    isHlsStream = isHls
                )
            }

            return VideoMetadata(
                title = title,
                author = author,
                thumbnailURL = thumbnail,
                platform = VideoPlatform.INSTAGRAM,
                sourceURL = sourceURL,
                formats = formats,
                allowsRealDownload = true,
                usesYTDLP = false
            )
        }
    }

    private fun instagramMediaURLs(html: String): List<URL> {
        val found = mutableListOf<URL>()
        val seen = mutableSetOf<String>()
        val patterns = listOf(
            """<(?:video|source)[^>]+(?:src|data-src)=["'](https://[^"']+)["']""",
            """<a[^>]+download[^>]+href=["'](https://[^"']+)["']""",
            """<a[^>]+href=["'](https://[^"']+)["'][^>]+download""",
            """(https://scontent[^"'<\s]+\.mp4[^"'<\s]*)""",
            """(https://[^"'<\s]*cdninstagram\.com[^"'<\s]*\.mp4[^"'<\s]*)""",
            """(https://[^"'<\s]*fbcdn\.net[^"'<\s]*\.mp4[^"'<\s]*)"""
        )

        for (pattern in patterns) {
            val matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(html)
            while (matcher.find()) {
                val raw = htmlDecode(matcher.group(1))
                    .replace("&amp;", "&")
                    .replace("\\u0026", "&")
                    .replace("\\/", "/")
                val cleaned = raw.substringBefore('#')
                val lower = cleaned.lowercase()
                if (!(lower.contains(".mp4") || lower.contains("m3u8"))) continue
                val url = try {
                    URL(cleaned)
                } catch (_: Exception) {
                    continue
                }
                if (!seen.add(cleaned)) continue
                val host = url.host?.lowercase().orEmpty()
                if (!(host.contains("cdninstagram") || host.contains("fbcdn") || host.contains("scontent"))) {
                    continue
                }
                found += url
            }
        }
        return found
    }

    private fun instagramAuthor(ogTitle: String): String? {
        val at = firstMatch(ogTitle, """@([A-Za-z0-9._]+)""")
        if (at != null) return at
        val by = firstMatch(ogTitle, """Video by\s+([A-Za-z0-9._]+)""")
        return by
    }

    private fun instagramTitle(ogTitle: String, shortcode: String): String {
        var title = ogTitle.replace(Regex("""^[^:]+:\s*"""), "")
        title = title.trim().trim('"', '\'', '“', '”')
        if (title.isEmpty() || title.length < 2) return "Instagram $shortcode"
        if (title.length > 80) return title.take(77) + "…"
        return title
    }

    // endregion

    // region YouTube

    private suspend fun extractYouTube(videoID: String, sourceURL: URL): VideoMetadata {
        // Race ANDROID + IOS Innertube — take the first usable result.
        raceYouTubeInnertube(videoID, sourceURL)?.let { return it }

        extractYouTubeViaPiped(videoID, sourceURL)?.let { return it }

        throw PageExtractionError.Network(
            "Couldn’t resolve this YouTube video quickly. Try again."
        )
    }

    private suspend fun raceYouTubeInnertube(videoID: String, sourceURL: URL): VideoMetadata? {
        val blocks = youtubeClientProfiles.map { profile ->
            suspend {
                try {
                    val json = fetchYouTubePlayerJSON(videoID, profile)
                    if (json == null) null else metadataFromYouTubePlayerJSON(json, sourceURL)
                } catch (_: Exception) {
                    null
                }
            }
        }
        return raceFirst(*blocks.toTypedArray())
    }

    private fun extractYouTubeViaPiped(videoID: String, sourceURL: URL): VideoMetadata? {
        for (base in pipedInstances) {
            val endpoint = "$base/streams/$videoID"
            try {
                HttpClients.get(
                    endpoint,
                    client = HttpClients.fast,
                    userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15",
                    headers = mapOf("Accept" to "application/json")
                ).use { response ->
                    if (response.code !in 200 until 300) return@use null
                    val json = response.jsonOrNull() ?: return@use null

                    val title: String = json.optString("title").ifEmpty { "YouTube video" }
                    val author: String? = json.optString("uploader").takeIf { it.isNotEmpty() }
                    val thumbnail: URL? = json.optString("thumbnailUrl").takeIf { it.isNotEmpty() }
                        ?.let { runCatching { URL(it) }.getOrNull() }
                    val videoStreams = json.optJSONArray("videoStreams") ?: JSONArray()
                    val audioStreams = json.optJSONArray("audioStreams") ?: JSONArray()
                    val hls: URL? = json.optString("hls").takeIf { it.isNotEmpty() }
                        ?.let { runCatching { URL(it) }.getOrNull() }
                        ?.takeIf { isTrustedYouTubeMediaURL(it) }

                    val formats = mutableListOf<VideoFormat>()

                    val muxed = mutableListOf<JSONObject>()
                    for (i in 0 until videoStreams.length()) {
                        val stream = videoStreams.optJSONObject(i) ?: continue
                        if (stream.optBoolean("videoOnly", false)) continue
                        val urlString = stream.optString("url")
                        if (urlString.isEmpty()) continue
                        val mediaURL = try {
                            URL(urlString)
                        } catch (_: Exception) {
                            continue
                        }
                        if (!isTrustedYouTubeMediaURL(mediaURL)) continue
                        muxed += stream
                    }
                    muxed.sortByDescending { pipedQuality(it.optString("quality")) }

                    for ((index, stream) in muxed.take(5).withIndex()) {
                        val urlString = stream.optString("url")
                        val mediaURL = try {
                            URL(urlString)
                        } catch (_: Exception) {
                            continue
                        }
                        val qualityLabel = stream.optString("quality").ifEmpty { "Video" }
                        val height = pipedQuality(qualityLabel)
                        if (height <= 0) continue
                        val mime = stream.optString("mimeType").ifEmpty { "video/mp4" }
                        val isHls = mime.contains("mpegurl") ||
                            mediaURL.path.lowercase().endsWith(".m3u8")
                        val ext = if (mime.contains("webm")) "webm" else "mp4"
                        formats += VideoFormat(
                            id = "piped-$index-$height",
                            label = qualityLabel,
                            url = mediaURL,
                            fileExtension = ext,
                            quality = height,
                            isAudioOnly = false,
                            isHlsStream = isHls
                        )
                    }

                    if (hls != null) {
                        formats.add(
                            0,
                            VideoFormat(
                                id = "piped-hls",
                                label = "Best (stream)",
                                url = hls,
                                fileExtension = "mp4",
                                quality = muxed.firstOrNull()?.let { pipedQuality(it.optString("quality")) },
                                isAudioOnly = false,
                                isHlsStream = true
                            )
                        )
                    }

                    for (i in 0 until audioStreams.length()) {
                        val audio = audioStreams.optJSONObject(i) ?: continue
                        val urlString = audio.optString("url")
                        if (urlString.isEmpty()) continue
                        val mediaURL = try {
                            URL(urlString)
                        } catch (_: Exception) {
                            continue
                        }
                        if (!isTrustedYouTubeMediaURL(mediaURL)) continue
                        val mime = audio.optString("mimeType").ifEmpty { "audio/mp4" }
                        formats += VideoFormat(
                            id = "piped-audio",
                            label = "Audio only",
                            url = mediaURL,
                            fileExtension = if (mime.contains("webm")) "webm" else "m4a",
                            quality = audio.optInt("bitrate", 0).takeIf { it > 0 },
                            isAudioOnly = true
                        )
                        break
                    }

                    if (formats.any { !it.isAudioOnly }) {
                        return@use VideoMetadata(
                            title = title,
                            author = author,
                            thumbnailURL = thumbnail,
                            platform = VideoPlatform.YOUTUBE,
                            sourceURL = sourceURL,
                            formats = formats,
                            allowsRealDownload = true,
                            usesYTDLP = false
                        )
                    }
                    null
                }?.let { return it }
            } catch (_: Exception) {
                continue
            }
        }
        return null
    }

    private fun pipedQuality(label: String?): Int {
        if (label.isNullOrEmpty()) return 0
        return label.filter { it.isDigit() }.toIntOrNull() ?: 0
    }

    /** Accept YouTube CDN / Piped proxy URLs; reject unrelated mirrors. */
    private fun isTrustedYouTubeMediaURL(url: URL): Boolean {
        val host = url.host?.lowercase().orEmpty()
        val absolute = url.toString().lowercase()
        if (host.contains("googlevideo.com")) return true
        if (host.contains("youtube.com") || host.contains("ytimg.com")) return true
        if (host.contains("piped") && (absolute.contains("videoplayback") || absolute.contains("m3u8"))) {
            return true
        }
        if (absolute.contains("/videoplayback")) return true
        if (absolute.contains(".m3u8") && host.contains("googlevideo")) return true
        return false
    }

    private data class YouTubeClientProfile(
        val name: String,
        val version: String,
        val apiKey: String,
        val userAgent: String,
        val clientNameHeader: String,
        val extraClientFields: Map<String, Any>
    )

    private val youtubeClientProfiles = listOf(
        YouTubeClientProfile(
            name = "ANDROID",
            version = "20.10.38",
            apiKey = "AIzaSyA8eiZmM1FaDVzRv56ghNOtmvq96PukvtE",
            userAgent = "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip",
            clientNameHeader = "3",
            extraClientFields = mapOf(
                "androidSdkVersion" to 34,
                "osName" to "Android",
                "osVersion" to "14"
            )
        ),
        YouTubeClientProfile(
            name = "IOS",
            version = "20.10.4",
            apiKey = "AIzaSyB-63vPrdThhKuerbB2N_a6SpUGSj3JdxE",
            userAgent = "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 17_7 like Mac OS X;)",
            clientNameHeader = "5",
            extraClientFields = mapOf(
                "deviceMake" to "Apple",
                "deviceModel" to "iPhone16,2",
                "osName" to "iPhone",
                "osVersion" to "17.7.0.21H16"
            )
        )
    )

    private val pipedInstances = listOf("https://api.piped.private.coffee")

    private fun fetchYouTubePlayerJSON(videoID: String, profile: YouTubeClientProfile): JSONObject? {
        val endpoint =
            "https://www.youtube.com/youtubei/v1/player?key=${profile.apiKey}&prettyPrint=false"

        val client = JSONObject().apply {
            put("clientName", profile.name)
            put("clientVersion", profile.version)
            put("hl", "en")
            put("gl", "US")
            put("userAgent", profile.userAgent)
            for ((key, value) in profile.extraClientFields) {
                put(key, value)
            }
        }

        val body = JSONObject().apply {
            put(
                "context",
                JSONObject().apply {
                    put("client", client)
                    put("thirdParty", JSONObject().put("embedUrl", "https://www.youtube.com/"))
                }
            )
            put("videoId", videoID)
            put("contentCheckOk", true)
            put("racyCheckOk", true)
            put(
                "playbackContext",
                JSONObject().put(
                    "contentPlaybackContext",
                    JSONObject().put("html5Preference", "HTML5_PREF_WANTS")
                )
            )
        }

        return postJson(
            endpoint,
            body.toString(),
            client = HttpClients.fast,
            userAgent = profile.userAgent,
            headers = mapOf(
                "X-YouTube-Client-Name" to profile.clientNameHeader,
                "X-YouTube-Client-Version" to profile.version,
                "Origin" to "https://www.youtube.com",
                "Referer" to "https://www.youtube.com/",
                "Cookie" to "CONSENT=YES+1; SOCS=CAI"
            )
        )
    }

    private fun metadataFromYouTubePlayerJSON(json: JSONObject, sourceURL: URL): VideoMetadata? {
        val streaming = json.optJSONObject("streamingData") ?: JSONObject()
        val progressive = streaming.optJSONArray("formats") ?: JSONArray()
        val adaptive = streaming.optJSONArray("adaptiveFormats") ?: JSONArray()
        val hls = streaming.optString("hlsManifestUrl").ifEmpty { null }
            ?.let { runCatching { URL(it) }.getOrNull() }
        val hasAnyStream = hls != null || progressive.length() > 0 || adaptive.length() > 0

        val playability = json.optJSONObject("playabilityStatus")
        val status = playability?.optString("status")
        if (status != null && status != "OK" && !hasAnyStream) return null

        val details = json.optJSONObject("videoDetails")
        val title = details?.optString("title")?.ifEmpty { null } ?: "YouTube video"
        val author = details?.optString("author")?.ifEmpty { null }
        val thumbs = details?.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
        val thumb = thumbs?.optJSONObject(thumbs.length() - 1)?.optString("url")?.ifEmpty { null }
        val thumbnailURL = thumb?.let { runCatching { URL(it) }.getOrNull() }

        val formats = mutableListOf<VideoFormat>()
        val seenHeights = mutableSetOf<Int>()

        val progressiveList = jsonArrayToList(progressive)
            .sortedByDescending { it.optInt("height", 0) }

        for (entry in progressiveList) {
            val mediaURL = mediaURLFromEntry(entry) ?: continue
            val height = entry.optInt("height", 0).takeIf { it > 0 }
            if (height != null) {
                if (height in seenHeights) continue
                seenHeights += height
            }
            val mime = entry.optString("mimeType")
            val itag = entry.optInt("itag", formats.size)
            formats += VideoFormat(
                id = "yt-$itag",
                label = height?.let { "${it}p" } ?: "Video",
                url = mediaURL,
                fileExtension = if (mime.contains("webm")) "webm" else "mp4",
                quality = height,
                isAudioOnly = false
            )
            if (formats.size >= 6) break
        }

        if (hls != null) {
            val insertAt = if (formats.isEmpty()) 0 else minOf(1, formats.size)
            formats.add(
                insertAt,
                VideoFormat(
                    id = "yt-hls",
                    label = "Best (stream)",
                    url = hls,
                    fileExtension = "mp4",
                    quality = seenHeights.maxOrNull(),
                    isAudioOnly = false,
                    isHlsStream = true
                )
            )
        }

        // Only fall back to adaptive video-only when nothing muxed/HLS exists.
        val hasMuxed = formats.any { !it.isHlsStream && !it.isAudioOnly }
        if (!hasMuxed && hls == null) {
            val adaptiveList = jsonArrayToList(adaptive)
                .sortedByDescending { it.optInt("height", 0) }
            for (entry in adaptiveList) {
                val mime = entry.optString("mimeType")
                if (!mime.contains("video")) continue
                val mediaURL = mediaURLFromEntry(entry) ?: continue
                val height = entry.optInt("height", 0).takeIf { it > 0 }
                val itag = entry.optInt("itag", formats.size)
                formats += VideoFormat(
                    id = "yt-adapt-$itag",
                    label = height?.let { "${it}p (video only)" } ?: "Video only",
                    url = mediaURL,
                    fileExtension = if (mime.contains("webm")) "webm" else "mp4",
                    quality = height,
                    isAudioOnly = false
                )
                if (formats.size >= 4) break
            }
        }

        for (i in 0 until adaptive.length()) {
            val audio = adaptive.optJSONObject(i) ?: continue
            val mime = audio.optString("mimeType")
            if (!mime.startsWith("audio/")) continue
            val mediaURL = mediaURLFromEntry(audio) ?: continue
            formats += VideoFormat(
                id = "yt-audio",
                label = "Audio only",
                url = mediaURL,
                fileExtension = if (mime.contains("mp4")) "m4a" else "webm",
                quality = audio.optInt("averageBitrate", 0).takeIf { it > 0 },
                isAudioOnly = true
            )
            break
        }

        if (formats.none { !it.isAudioOnly }) return null

        return VideoMetadata(
            title = title,
            author = author,
            thumbnailURL = thumbnailURL,
            platform = VideoPlatform.YOUTUBE,
            sourceURL = sourceURL,
            formats = formats,
            allowsRealDownload = true,
            usesYTDLP = false
        )
    }

    private fun mediaURLFromEntry(entry: JSONObject): URL? {
        val urlString = entry.optString("url")
        if (urlString.isEmpty()) return null
        return try {
            URL(urlString)
        } catch (_: Exception) {
            null
        }
    }

    private fun jsonArrayToList(array: JSONArray): List<JSONObject> {
        val list = mutableListOf<JSONObject>()
        for (i in 0 until array.length()) {
            array.optJSONObject(i)?.let { list += it }
        }
        return list
    }

    // endregion

    // region Generic HTML

    /**
     * Scrape og:video / JSON-LD VideoObject / inline mp4|m3u8 from an arbitrary page.
     * Also used by platform-specific fallbacks in [AndroidPageVideoExtractorPlatforms].
     */
    suspend fun extractFromHTMLPage(url: URL, platform: VideoPlatform): VideoMetadata? =
        withContext(Dispatchers.IO) {
            HttpClients.get(
                url.toString(),
                userAgent = HttpClients.IPHONE_UA,
                headers = mapOf("Cookie" to "CONSENT=YES+1; SOCS=CAI")
            ).use { response ->
                if (response.code !in 200 until 400) {
                    throw PageExtractionError.Network("Couldn’t load that page.")
                }
                val html = response.bodyString() ?: return@withContext null

                val title = metaContent(html, "og:title")
                    ?: tagContent(html, "title")
                    ?: url.host
                    ?: "Video"
                val author = metaContent(html, "og:site_name") ?: platform.displayName
                val thumbnail = metaContent(html, "og:image")?.let { runCatching { URL(it) }.getOrNull() }

                val candidates = mutableListOf<URL>()
                for (key in listOf(
                    "og:video:secure_url",
                    "og:video:url",
                    "og:video",
                    "twitter:player:stream"
                )) {
                    val value = metaContent(html, key) ?: continue
                    val media = try {
                        URL(value)
                    } catch (_: Exception) {
                        continue
                    }
                    if (isLikelyMediaURL(media) || value.lowercase().contains("m3u8")) {
                        candidates += media
                    }
                }
                candidates += jsonLDVideoURLs(html)
                candidates += inlineMP4URLs(html)

                val unique = candidates.distinctBy { it.toString() }
                if (unique.isEmpty()) return@withContext null

                val formats = unique.take(4).mapIndexed { index, media ->
                    val lower = media.toString().lowercase()
                    val isHls = lower.contains("m3u8")
                    val pathExt = media.path.substringAfterLast('.', "").lowercase()
                    val ext = when {
                        isHls -> "mp4"
                        pathExt.isEmpty() -> "mp4"
                        else -> pathExt
                    }
                    VideoFormat(
                        id = "page-$index",
                        label = if (index == 0) "Best available" else "Option ${index + 1}",
                        url = media,
                        fileExtension = ext,
                        quality = null,
                        isAudioOnly = ext in setOf("m4a", "mp3", "aac"),
                        isHlsStream = isHls
                    )
                }

                VideoMetadata(
                    title = title.trim(),
                    author = author,
                    thumbnailURL = thumbnail,
                    platform = platform,
                    sourceURL = url,
                    formats = formats,
                    allowsRealDownload = true,
                    usesYTDLP = false
                )
            }
        }

    // endregion

    // region Shared helpers

    private fun isLikelyMediaURL(url: URL): Boolean {
        val lower = url.toString().lowercase()
        if (lower.contains(".m3u8")) return false
        if (DirectMediaExtractor.looksLikeDirectMediaURL(url)) return true
        return lower.contains(".mp4")
            || lower.contains(".mov")
            || lower.contains("mime=video")
            || lower.contains("googlevideo.com")
    }

    private fun jsonLDVideoURLs(html: String): List<URL> {
        val results = mutableListOf<URL>()
        val matcher = Pattern.compile(""""contentUrl"\s*:\s*"(https?[^"]+)"""").matcher(html)
        while (matcher.find()) {
            val raw = matcher.group(1).replace("\\/", "/")
            val url = try {
                URL(raw)
            } catch (_: Exception) {
                continue
            }
            if (isLikelyMediaURL(url) || raw.lowercase().contains("m3u8")) {
                results += url
            }
        }
        return results
    }

    private fun postJson(
        url: String,
        json: String,
        client: OkHttpClient,
        userAgent: String,
        headers: Map<String, String> = emptyMap()
    ): JSONObject? {
        val body = json.toRequestBody(JSON_MEDIA_TYPE)
        val builder = Request.Builder()
            .url(url)
            .header("User-Agent", userAgent)
            .header("Content-Type", "application/json")
            .post(body)
        headers.forEach { (k, v) -> builder.header(k, v) }
        return try {
            client.newCall(builder.build()).execute().use { response ->
                if (response.code !in 200 until 300) return null
                response.jsonOrNull()
            }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Race suspend blocks on [Dispatchers.IO]; return the first non-null result and cancel the rest.
     */
    private suspend fun <T : Any> raceFirst(vararg blocks: suspend () -> T?): T? = coroutineScope {
        val deferreds = blocks.map { block ->
            async(Dispatchers.IO) {
                try {
                    block()
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    null
                }
            }
        }.toMutableList()

        while (deferreds.isNotEmpty()) {
            val winner = select {
                for (d in deferreds.toList()) {
                    d.onAwait { value ->
                        deferreds.remove(d)
                        value
                    }
                }
            }
            if (winner != null) {
                deferreds.forEach { it.cancel() }
                return@coroutineScope winner
            }
        }
        null
    }

    companion object {
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()

        /** Extract an 11-char YouTube id from watch / youtu.be / shorts / embed URLs. */
        fun youtubeVideoID(from: URL): String? {
            val host = from.host?.lowercase().orEmpty()
            if (host.contains("youtu.be")) {
                val id = from.path.split('/').firstOrNull { it.isNotEmpty() }
                    ?.substringBefore('?')
                    .orEmpty()
                return if (id.length >= 11) id.take(11) else null
            }

            val query = from.query
            if (!query.isNullOrEmpty()) {
                val v = query.split('&')
                    .map { it.split('=', limit = 2) }
                    .firstOrNull { it[0] == "v" }
                    ?.getOrNull(1)
                    ?.let { URLDecoder.decode(it, "UTF-8") }
                if (v != null && v.length >= 11) return v.take(11)
            }

            val parts = from.path.split('/').filter { it.isNotEmpty() }
            val embedIndex = parts.indexOfFirst { it in setOf("embed", "shorts", "live", "v") }
            if (embedIndex >= 0 && embedIndex + 1 < parts.size) {
                return parts[embedIndex + 1].take(11)
            }
            return null
        }

        fun qualityHint(from: String): Int? {
            val digits = Regex("""(\d{3,4})""").find(from)?.groupValues?.get(1)?.toIntOrNull()
            if (digits != null) return digits
            val upper = from.uppercase()
            if (upper.contains("HD")) return 720
            if (upper.contains("SD")) return 360
            return null
        }

        fun firstMatch(text: String, pattern: String): String? {
            return try {
                val matcher = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(text)
                if (matcher.find() && matcher.groupCount() >= 1) matcher.group(1) else null
            } catch (_: Exception) {
                null
            }
        }

        fun htmlDecode(value: String): String =
            value.replace("&amp;", "&")
                .replace("&#38;", "&")
                .replace("&quot;", "\"")
                .replace("&#39;", "'")
                .replace("&lt;", "<")
                .replace("&gt;", ">")

        fun metaContent(html: String, property: String): String? {
            val patterns = listOf(
                """property="$property"[^>]*content="([^"]+)"""",
                """content="([^"]+)"[^>]*property="$property"""",
                """name="$property"[^>]*content="([^"]+)"""",
                """content="([^"]+)"[^>]*name="$property""""
            )
            for (pattern in patterns) {
                val match = firstMatch(html, pattern)
                if (!match.isNullOrEmpty()) return htmlDecode(match)
            }
            return null
        }

        fun tagContent(html: String, tag: String): String? {
            val pattern = """<$tag[^>]*>([^<]+)</$tag>"""
            val match = firstMatch(html, pattern) ?: return null
            return htmlDecode(match.trim())
        }

        fun inlineMP4URLs(html: String): List<URL> {
            val results = mutableListOf<URL>()
            val matcher = Pattern.compile(
                """https?://[^\s"'<>]+\.mp4[^\s"'<>]*""",
                Pattern.CASE_INSENSITIVE
            ).matcher(html)
            while (matcher.find()) {
                try {
                    results += URL(matcher.group())
                } catch (_: Exception) {
                    // ignore
                }
            }
            return results
        }
    }

    // Instance wrappers so platform extensions can call helpers without Companion prefix noise.
    fun qualityHint(label: String): Int? = Companion.qualityHint(label)
    fun firstMatch(text: String, pattern: String): String? = Companion.firstMatch(text, pattern)
    fun htmlDecode(value: String): String = Companion.htmlDecode(value)
    fun metaContent(html: String, property: String): String? = Companion.metaContent(html, property)
    fun tagContent(html: String, tag: String): String? = Companion.tagContent(html, tag)
    fun inlineMP4URLs(html: String): List<URL> = Companion.inlineMP4URLs(html)
}
