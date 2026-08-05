package com.ashbash.vidoxproject.util

import com.ashbash.vidoxproject.models.VideoPlatform
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder

/** Cleans pasted URLs so extraction is more reliable across platforms. */
object URLNormalizer {
    private val stripQueryKeys = setOf(
        "fbclid", "fb_action_ids", "fb_action_types", "fb_source",
        "mibextid", "rdid", "share_url", "ref", "refsrc", "_rdr",
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "si", "feature", "pp", "s", "refid", "__tn__", "sfnsn"
    )

    fun url(from: String): URL? {
        var trimmed = from.trim()
        if (trimmed.isEmpty()) return null

        if ((trimmed.startsWith("\"") && trimmed.endsWith("\"")) ||
            (trimmed.startsWith("'") && trimmed.endsWith("'")) ||
            (trimmed.startsWith("<") && trimmed.endsWith(">"))
        ) {
            trimmed = trimmed.substring(1, trimmed.length - 1).trim()
        }

        if (!trimmed.contains("://")) {
            trimmed = "https://$trimmed"
        }

        return try {
            val uri = URI(trimmed)
            val scheme = uri.scheme?.lowercase() ?: return null
            if (scheme != "http" && scheme != "https") return null

            var host = uri.host?.lowercase() ?: return null
            host = canonicalizeHost(host)

            val path = uri.path ?: ""
            val query = uri.rawQuery
            val rebuilt = buildString {
                append(scheme).append("://").append(host)
                append(if (path.isEmpty()) "" else path)
                if (!query.isNullOrEmpty()) {
                    val filtered = filterQuery(query, host, path)
                    if (filtered.isNotEmpty()) append('?').append(filtered)
                }
            }
            URL(rebuilt)
        } catch (_: Exception) {
            null
        }
    }

    private fun canonicalizeHost(host: String): String = when (host) {
        "m.facebook.com", "mbasic.facebook.com", "web.facebook.com", "mobile.facebook.com" ->
            "www.facebook.com"
        "fb.com", "www.fb.com" -> "www.facebook.com"
        "www.fb.watch" -> "fb.watch"
        else -> host
    }

    private fun filterQuery(rawQuery: String, host: String, path: String): String {
        val isFacebook = VideoPlatform.detect("https://$host$path") == VideoPlatform.FACEBOOK
        val keepFacebook = setOf("v", "story_fbid", "id", "video_id")
        return rawQuery.split("&").mapNotNull { pair ->
            val parts = pair.split("=", limit = 2)
            val name = parts[0].lowercase()
            if (isFacebook) {
                if (name in keepFacebook || name !in stripQueryKeys) pair else null
            } else {
                if (name in stripQueryKeys) null else pair
            }
        }.joinToString("&")
    }

    fun facebookVideoID(from: URL): String? {
        val query = from.query
        if (!query.isNullOrEmpty()) {
            for (key in listOf("v", "video_id", "story_fbid")) {
                val value = query.split("&")
                    .map { it.split("=", limit = 2) }
                    .firstOrNull { it[0] == key }
                    ?.getOrNull(1)
                    ?.let { URLDecoder.decode(it, "UTF-8") }
                if (value != null && isDigits(value) && value.length >= 5) return value
            }
        }

        val parts = from.path.split('/').filter { it.isNotEmpty() }
        if (parts.isEmpty()) return null

        val marker = parts.indexOfFirst { it == "reel" || it == "videos" || it == "watch" }
        if (marker >= 0 && marker + 1 < parts.size) {
            val candidate = parts[marker + 1].substringBefore('?')
            if (isDigits(candidate) && candidate.length >= 5) return candidate
        }

        if (parts.size >= 3 && parts[1] == "videos" && isDigits(parts[2]) && parts[2].length >= 5) {
            return parts[2]
        }
        return null
    }

    private fun isDigits(value: String): Boolean =
        value.isNotEmpty() && value.all { it.isDigit() }

    fun encodeQuery(value: String): String =
        URLEncoder.encode(value, "UTF-8")
}
