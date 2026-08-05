package com.ashbash.vidoxproject.util

import android.content.Context
import java.io.File
import java.util.UUID

/**
 * Manages on-disk locations for downloaded videos and optional thumbnails.
 * Downloads stay inside app-private storage until the user exports a copy.
 */
class FileStorage(context: Context) {
    private val root: File = context.filesDir

    val videosDirectory: File
        get() = File(root, "Videos").also { it.mkdirs() }

    val thumbnailsDirectory: File
        get() = File(root, "Thumbnails").also { it.mkdirs() }

    fun makeVideoFile(preferredName: String, fileExtension: String): File {
        val safeBase = preferredName
            .replace("/", "-")
            .trim()
            .ifEmpty { UUID.randomUUID().toString() }
            .take(80)
        val ext = fileExtension.removePrefix(".")
        val filename = "$safeBase-${UUID.randomUUID().toString().take(8)}.$ext"
        return File(videosDirectory, filename)
    }

    fun storedPath(forFile: File): String {
        val videosPath = videosDirectory.canonicalPath
        val filePath = forFile.canonicalPath
        return if (filePath.startsWith(videosPath + File.separator)) {
            filePath.removePrefix(videosPath + File.separator)
        } else {
            forFile.name
        }
    }

    fun resolvedFile(storedPath: String): File {
        if (!storedPath.startsWith("/")) {
            return File(videosDirectory, storedPath)
        }
        val absolute = File(storedPath)
        if (absolute.exists()) return absolute
        val byName = File(videosDirectory, absolute.name)
        if (byName.exists()) return byName
        return absolute
    }

    fun fileExists(storedPath: String): Boolean = resolvedFile(storedPath).exists()

    fun makeThumbnailFile(): File {
        thumbnailsDirectory
        return File(thumbnailsDirectory, "${UUID.randomUUID()}.jpg")
    }

    fun storedThumbnailPath(file: File): String = file.name

    fun resolvedThumbnail(storedPath: String?): File? {
        if (storedPath.isNullOrBlank()) return null
        val name = File(storedPath).name
        val file = File(thumbnailsDirectory, name)
        return file.takeIf { it.exists() }
    }

    fun removeThumbnailCacheForVideo(videoFile: File) {
        VideoThumbnailLoader.cacheFileFor(videoFile, thumbnailsDirectory).delete()
    }

    fun removeFile(storedPath: String) {
        resolvedFile(storedPath).delete()
        // Thumbnail paths are stored as filenames under Thumbnails/.
        File(thumbnailsDirectory, File(storedPath).name).delete()
    }

    fun fileSize(file: File): Long = if (file.exists()) file.length() else 0L

    fun fileSize(storedPath: String): Long = fileSize(resolvedFile(storedPath))

    fun videosDirectoryByteCount(): Long {
        val dir = videosDirectory
        return dir.walkTopDown()
            .filter { it.isFile }
            .sumOf { it.length() }
    }

    fun formatByteCount(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val kb = bytes / 1024.0
        if (kb < 1024) return "%.1f KB".format(kb)
        val mb = kb / 1024.0
        if (mb < 1024) return "%.1f MB".format(mb)
        return "%.2f GB".format(mb / 1024.0)
    }
}
