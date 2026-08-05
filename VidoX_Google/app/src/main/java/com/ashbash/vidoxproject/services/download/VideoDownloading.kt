package com.ashbash.vidoxproject.services.download

import kotlinx.coroutines.flow.Flow
import java.io.File
import java.net.URL

sealed class DownloadError(message: String) : Exception(message) {
    data object Cancelled : DownloadError("Download cancelled.")
    data object InvalidResponse : DownloadError("Invalid download response.")
    data class HttpStatus(val code: Int) : DownloadError("Download failed with status $code.")
    data class WriteFailed(val detail: String) : DownloadError("Could not save the file: $detail")
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
