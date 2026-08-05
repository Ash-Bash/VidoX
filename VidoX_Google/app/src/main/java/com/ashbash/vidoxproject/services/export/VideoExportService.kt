package com.ashbash.vidoxproject.services.export

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

sealed class ExportError(message: String) : Exception(message) {
    data object FileMissing : ExportError("The video file is missing from VidoX storage.")
    data object PhotosDenied : ExportError("Permission to save to Gallery was denied.")
    data class PhotosFailed(val detail: String) : ExportError("Couldn’t save to Gallery: $detail")
    data class CopyFailed(val detail: String) : ExportError("Couldn’t copy the file: $detail")
    data object SaveCancelled : ExportError("Save cancelled.")
}

/** Saves library videos to Gallery or shares / writes via SAF. */
class VideoExportService(private val context: Context) {

    suspend fun saveToGallery(file: File, displayName: String): Unit = withContext(Dispatchers.IO) {
        if (!file.exists()) throw ExportError.FileMissing
        try {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Video.Media.MIME_TYPE, mimeFor(file))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/VidoX")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
            }
            val resolver = context.contentResolver
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }
            val uri = resolver.insert(collection, values)
                ?: throw ExportError.PhotosFailed("MediaStore insert failed.")
            resolver.openOutputStream(uri)?.use { output ->
                file.inputStream().use { input -> input.copyTo(output) }
            } ?: throw ExportError.PhotosFailed("Couldn’t open output stream.")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Video.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            }
        } catch (e: ExportError) {
            throw e
        } catch (e: Exception) {
            throw ExportError.PhotosFailed(e.message ?: "Unknown error")
        }
    }

    fun shareIntent(file: File): Intent {
        if (!file.exists()) throw ExportError.FileMissing
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file
        )
        return Intent(Intent.ACTION_SEND).apply {
            type = mimeFor(file)
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    suspend fun copyToUri(file: File, destination: Uri): Unit = withContext(Dispatchers.IO) {
        if (!file.exists()) throw ExportError.FileMissing
        try {
            context.contentResolver.openOutputStream(destination)?.use { output ->
                file.inputStream().use { input -> input.copyTo(output) }
            } ?: throw ExportError.CopyFailed("Couldn’t open destination.")
        } catch (e: ExportError) {
            throw e
        } catch (e: Exception) {
            throw ExportError.CopyFailed(e.message ?: "Unknown error")
        }
    }

    private fun mimeFor(file: File): String = when (file.extension.lowercase()) {
        "mp4", "m4v" -> "video/mp4"
        "mov" -> "video/quicktime"
        "webm" -> "video/webm"
        "mkv" -> "video/x-matroska"
        "mp3" -> "audio/mpeg"
        "m4a" -> "audio/mp4"
        "aac" -> "audio/aac"
        else -> "video/*"
    }
}
