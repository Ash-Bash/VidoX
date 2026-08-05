package com.ashbash.vidoxproject.services.download

import android.content.Context
import com.ashbash.vidoxproject.services.extraction.YtDlpTool
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import java.io.File
import java.net.URL

class YtDlpVideoDownloader(private val appContext: Context) {
    fun download(
        pageURL: URL,
        formatSelector: String,
        destination: File
    ): Flow<DownloadProgress> = flow {
        YtDlpTool.ensureInitialized(appContext)
        destination.parentFile?.mkdirs()
        val template = destination.absolutePath.substringBeforeLast('.') + ".%(ext)s"
        emit(DownloadProgress(0, null))
        YtDlpTool.download(
            pageUrl = pageURL.toString(),
            formatSelector = formatSelector,
            outputTemplate = template
        ) { fraction ->
            // Progress callback from yt-dlp is percentage-based; emit coarse updates.
        }
        val stem = destination.nameWithoutExtension
        val dir = destination.parentFile
        val written = dir?.listFiles()
            ?.filter { it.name.startsWith(stem) }
            ?.minByOrNull { it.name.length }
            ?: destination.takeIf { it.exists() }
        if (written == null || !written.exists()) {
            throw DownloadError.WriteFailed("yt-dlp did not produce an output file.")
        }
        if (written != destination && destination.exists().not()) {
            // Prefer keeping yt-dlp's real extension.
        }
        val size = written.length()
        emit(DownloadProgress(size, size))
    }.flowOn(Dispatchers.IO)

    fun resolveOutputFile(destination: File): File {
        val stem = destination.nameWithoutExtension
        val dir = destination.parentFile ?: return destination
        return dir.listFiles()
            ?.filter { it.name.startsWith(stem) }
            ?.minByOrNull { it.name.length }
            ?: destination
    }
}
