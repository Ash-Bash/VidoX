package com.ashbash.vidoxproject.services.download

import android.app.Application
import com.ashbash.vidoxproject.VidoXApp
import com.ashbash.vidoxproject.data.DownloadedVideo
import com.ashbash.vidoxproject.models.VideoPlatform
import com.ashbash.vidoxproject.services.extraction.ExtractionError
import com.ashbash.vidoxproject.services.extraction.ExtractionRouter
import com.ashbash.vidoxproject.services.extraction.YOUTUBE_FORMAT_SELECTOR
import com.ashbash.vidoxproject.util.URLNormalizer
import com.ashbash.vidoxproject.util.VideoThumbnailLoader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Replaces the on-disk file for an existing library entry without creating a duplicate. */
class VideoRedownloader(application: Application) {
    private val app = application as VidoXApp
    private val router = ExtractionRouter(application)
    private val urlDownloader = OkHttpVideoDownloader()
    private val ytdlpDownloader = YtDlpVideoDownloader(application)

    suspend fun redownload(
        video: DownloadedVideo,
        onProgress: (label: String, fraction: Float?) -> Unit
    ): DownloadedVideo = withContext(Dispatchers.IO) {
        suspend fun report(label: String, fraction: Float?) {
            withContext(Dispatchers.Main) { onProgress(label, fraction) }
        }

        val sourceURL = URLNormalizer.url(video.sourceURL)
            ?: throw ExtractionError.InvalidURL

        report("Looking up…", null)
        val metadata = router.extract(sourceURL)
        if (!metadata.allowsRealDownload) {
            throw IllegalStateException("This source can’t be downloaded automatically right now.")
        }
        val format = metadata.bestVideoFormat
            ?: metadata.formats.firstOrNull { !it.isAudioOnly }
            ?: throw IllegalStateException("No downloadable format was found for this video.")

        report(
            if (metadata.platform == VideoPlatform.YOUTUBE || metadata.usesYTDLP) "Preparing…" else "Starting…",
            null
        )

        var destination = app.fileStorage.makeVideoFile(
            if (metadata.title.isNotBlank()) metadata.title else video.title,
            format.fileExtension
        )

        try {
            if (metadata.platform == VideoPlatform.YOUTUBE ||
                (metadata.usesYTDLP && format.ytdlpFormatSelector != null)
            ) {
                val selector = format.ytdlpFormatSelector ?: YOUTUBE_FORMAT_SELECTOR
                ytdlpDownloader.download(
                    pageURL = metadata.sourceURL,
                    formatSelector = selector,
                    destination = destination
                ).collect { progress ->
                    report(
                        if (progress.totalBytes == null) "Downloading…" else "Finished",
                        progress.fraction
                    )
                }
                destination = ytdlpDownloader.resolveOutputFile(destination)
            } else {
                urlDownloader.download(format.url, destination).collect { progress ->
                    val label = if (progress.totalBytes != null) {
                        val received = app.fileStorage.formatByteCount(progress.bytesReceived)
                        val total = app.fileStorage.formatByteCount(progress.totalBytes)
                        "$received of $total"
                    } else {
                        "${app.fileStorage.formatByteCount(progress.bytesReceived)} downloaded"
                    }
                    report(label, progress.fraction)
                }
            }

            val thumbnailPath = runCatching {
                val remote = metadata.thumbnailURL ?: return@runCatching video.thumbnailPath
                val thumbFile = app.fileStorage.makeThumbnailFile()
                urlDownloader.download(remote, thumbFile).collect { }
                if (thumbFile.exists() && thumbFile.length() > 0L) {
                    video.thumbnailPath?.let { app.fileStorage.removeFile(it) }
                    app.fileStorage.storedThumbnailPath(thumbFile)
                } else {
                    thumbFile.delete()
                    video.thumbnailPath
                }
            }.getOrDefault(video.thumbnailPath)

            runCatching {
                VideoThumbnailLoader.cachedOrGenerate(
                    destination,
                    app.fileStorage.thumbnailsDirectory
                )
            }

            val size = app.fileStorage.fileSize(destination)
            val storedPath = app.fileStorage.storedPath(destination)
            val previousPath = video.localFilePath

            val updated = video.copy(
                title = metadata.title.ifBlank { video.title },
                author = metadata.author ?: video.author,
                platformRaw = metadata.platform.rawValue,
                thumbnailPath = thumbnailPath,
                localFilePath = storedPath,
                fileExtension = destination.extension.ifEmpty { format.fileExtension },
                downloadedAt = System.currentTimeMillis(),
                fileSize = size
            )
            app.repository.update(updated)

            if (previousPath != storedPath) {
                app.fileStorage.removeFile(previousPath)
            }
            updated
        } catch (e: Exception) {
            destination.delete()
            throw e
        }
    }
}
