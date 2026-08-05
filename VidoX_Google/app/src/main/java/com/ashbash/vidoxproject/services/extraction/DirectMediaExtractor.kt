package com.ashbash.vidoxproject.services.extraction

import com.ashbash.vidoxproject.models.VideoFormat
import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.models.VideoPlatform
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.net.URL

/** Resolves direct media URLs (mp4, mov, m4v, webm, etc.) into downloadable metadata. */
class DirectMediaExtractor : VideoExtracting {
    companion object {
        private val mediaExtensions = setOf(
            "mp4", "mov", "m4v", "webm", "mkv", "avi", "m4a", "mp3", "aac"
        )
        private val mediaContentTypes = setOf(
            "video/mp4", "video/quicktime", "video/webm", "video/x-m4v",
            "video/x-matroska", "audio/mp4", "audio/mpeg", "audio/aac", "application/octet-stream"
        )

        fun looksLikeDirectMediaURL(url: URL): Boolean {
            val pathExt = url.path.substringAfterLast('.', "").lowercase()
            if (pathExt in mediaExtensions) return true
            val last = url.path.substringAfterLast('/').lowercase()
            return mediaExtensions.any { last.contains(".$it") }
        }
    }

    override suspend fun extract(from: URL): VideoMetadata = withContext(Dispatchers.IO) {
        val ext = mediaExtension(from)
        if (ext != null && ext in mediaExtensions) {
            return@withContext makeMetadata(from, ext)
        }

        val probed = probeContentType(from)
        if (probed != null) {
            val resolvedExt = extensionForContentType(probed, ext ?: "mp4")
            if (probed in mediaContentTypes || resolvedExt in mediaExtensions) {
                return@withContext makeMetadata(from, resolvedExt)
            }
        }
        throw ExtractionError.NotDirectMedia
    }

    private fun mediaExtension(url: URL): String? {
        val pathExt = url.path.substringAfterLast('.', "").lowercase()
        if (pathExt in mediaExtensions) return pathExt
        val last = url.path.substringAfterLast('/').lowercase()
        for (candidate in mediaExtensions) {
            if (last.contains(".$candidate")) return candidate
        }
        return pathExt.ifEmpty { null }
    }

    private fun probeContentType(url: URL): String? {
        contentType(url, "HEAD")?.let { return it }
        return contentType(url, "GET", mapOf("Range" to "bytes=0-0"))
    }

    private fun contentType(
        url: URL,
        method: String,
        extraHeaders: Map<String, String> = emptyMap()
    ): String? {
        val builder = Request.Builder().url(url).method(method, null)
            .header("User-Agent", HttpClients.DESKTOP_UA)
        extraHeaders.forEach { (k, v) -> builder.header(k, v) }
        return try {
            HttpClients.default.newCall(builder.build()).execute().use { response ->
                if (response.code !in 200 until 400) {
                    if (response.code == 405 || response.code == 501) return null
                    throw ExtractionError.Network("Server returned status ${response.code}.")
                }
                response.header("Content-Type")
                    ?.substringBefore(';')
                    ?.trim()
                    ?.lowercase()
            }
        } catch (e: ExtractionError) {
            throw e
        } catch (_: Exception) {
            null
        }
    }

    private fun makeMetadata(url: URL, fileExtension: String): VideoMetadata {
        val name = url.path.substringAfterLast('/').substringBeforeLast('.')
        val title = java.net.URLDecoder.decode(name.ifEmpty { "Direct video" }, "UTF-8")
        val isAudio = fileExtension in setOf("m4a", "mp3", "aac")
        val label = if (isAudio) "Audio · ${fileExtension.uppercase()}" else "Video · ${fileExtension.uppercase()}"
        return VideoMetadata(
            title = title,
            author = url.host,
            platform = VideoPlatform.UNKNOWN,
            sourceURL = url,
            formats = listOf(
                VideoFormat(
                    id = "direct-$fileExtension",
                    label = label,
                    url = url,
                    fileExtension = fileExtension,
                    quality = null,
                    isAudioOnly = isAudio
                )
            ),
            allowsRealDownload = true
        )
    }

    private fun extensionForContentType(contentType: String, fallback: String): String = when (contentType) {
        "video/mp4" -> "mp4"
        "video/quicktime" -> "mov"
        "video/webm" -> "webm"
        "video/x-m4v" -> "m4v"
        "video/x-matroska" -> "mkv"
        "audio/mp4" -> "m4a"
        "audio/mpeg" -> "mp3"
        "audio/aac" -> "aac"
        else -> fallback.ifEmpty { "mp4" }
    }
}
