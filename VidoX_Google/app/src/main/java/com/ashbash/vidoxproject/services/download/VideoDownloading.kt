package com.ashbash.vidoxproject.services.download

import kotlinx.coroutines.flow.Flow
import java.io.File
import java.net.URL

sealed class DownloadError(message: String) : Exception(message) {
    data object Cancelled : DownloadError("Download cancelled.")
    data object InvalidResponse : DownloadError(
        "The site sent a response VidoX couldn’t use. Try the link again."
    )
    data class HttpStatus(val code: Int) : DownloadError(httpStatusMessage(code))
    data class WriteFailed(val detail: String) : DownloadError("Could not save the file: $detail")
}

fun httpStatusMessage(code: Int): String = when (code) {
    400 -> "The site didn’t understand that request (400). Copy the link again and retry."
    401 -> "This video needs a sign-in (401). Private or members-only videos can’t be downloaded here."
    403 -> "The site blocked this download (403). That usually means this file isn’t allowed to be saved — on YouTube the standard video file is often restricted. Try again, pick another quality, or use a different video. Age-restricted and some music videos also do this."
    404 -> "Nothing was found at that link (404). The video may have been deleted, or the URL is incomplete."
    408 -> "The site took too long to respond (408). Check your connection and try again."
    410 -> "This video is gone (410). It was removed from the site."
    416 -> "The download couldn’t resume (416). Start it again from the beginning."
    429 -> "Too many requests (429). Wait a minute, then try again."
    451 -> "This video isn’t available in your region (451)."
    500, 502, 503, 504 -> "The site had a temporary problem ($code). Try again in a moment."
    else -> if (code in 500..599) {
        "The site had a server problem ($code). Try again in a moment."
    } else {
        "Download failed (HTTP $code). The site refused the request."
    }
}

private val httpStatusRegexes = listOf(
    Regex("""HTTP Error ([0-9]{3})""", RegexOption.IGNORE_CASE),
    Regex("""status(?: code)?[: ]+([0-9]{3})""", RegexOption.IGNORE_CASE),
    Regex("""HTTP/\d(?:\.\d)? ([0-9]{3})""", RegexOption.IGNORE_CASE),
    Regex("""\bHTTP(?: status)?[: ]+([0-9]{3})""", RegexOption.IGNORE_CASE),
    Regex("""\(([0-9]{3})\)""")
)

fun httpStatusIn(text: String): Int? {
    for (regex in httpStatusRegexes) {
        val code = regex.find(text)?.groupValues?.getOrNull(1)?.toIntOrNull() ?: continue
        if (code in 400..599) return code
    }
    return null
}

fun userFacingTransferMessage(error: Throwable): String {
    if (error is DownloadError.Cancelled) return error.message ?: "Download cancelled."
    if (error is DownloadError.HttpStatus) return httpStatusMessage(error.code)
    val text = error.message.orEmpty()
    httpStatusIn(text)?.let { return httpStatusMessage(it) }
    val lower = text.lowercase()
    if ("requested format is not available" in lower || "list-formats" in lower) {
        return "YouTube didn’t offer a matching file for that quality. Try Fetch Info again, or pick another quality."
    }
    if ("page needs to be reloaded" in lower) {
        return "YouTube asked the player to reload. Try Fetch Info again — this is a temporary YouTube block."
    }
    if ("sign in to confirm" in lower || "not a bot" in lower) {
        return "YouTube is asking for a sign-in to confirm this isn’t automated. Try again in a moment, or use a different video."
    }
    if ("forbidden" in lower || "access denied" in lower) return httpStatusMessage(403)
    if ("ffmpeg" in lower) {
        return "Couldn’t combine the video and audio (ffmpeg). Try again, or pick a different quality."
    }
    return text.ifBlank { "Download failed." }
}

data class DownloadProgress(
    val bytesReceived: Long,
    val totalBytes: Long?
) {
    val fraction: Float?
        get() = totalBytes?.takeIf { it > 0 }?.let { bytesReceived.toFloat() / it }
}

interface VideoDownloading {
    fun download(from: URL, to: File): Flow<DownloadProgress>
}
