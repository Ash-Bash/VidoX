package com.ashbash.vidoxproject.ui.downloader

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ashbash.vidoxproject.VidoXApp
import com.ashbash.vidoxproject.data.DownloadedVideo
import com.ashbash.vidoxproject.models.VideoFormat
import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.models.VideoPlatform
import com.ashbash.vidoxproject.services.download.DownloadError
import com.ashbash.vidoxproject.services.download.OkHttpVideoDownloader
import com.ashbash.vidoxproject.services.download.YtDlpVideoDownloader
import com.ashbash.vidoxproject.services.download.userFacingTransferMessage
import com.ashbash.vidoxproject.services.extraction.ExtractionError
import com.ashbash.vidoxproject.services.extraction.ExtractionRouter
import com.ashbash.vidoxproject.services.extraction.PageExtractionError
import com.ashbash.vidoxproject.services.extraction.YOUTUBE_FORMAT_SELECTOR
import com.ashbash.vidoxproject.util.URLNormalizer
import com.ashbash.vidoxproject.util.VideoThumbnailLoader
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

data class DownloaderUiState(
    val urlText: String = "",
    val metadata: VideoMetadata? = null,
    val selectedFormatID: String? = null,
    val isExtracting: Boolean = false,
    val isDownloading: Boolean = false,
    val progressFraction: Float? = null,
    val progressLabel: String = "",
    val errorMessage: String? = null
) {
    val canDownload: Boolean
        get() {
            val meta = metadata ?: return false
            return meta.allowsRealDownload && !isDownloading && !isExtracting && selectedFormat != null
        }

    val selectedFormat: VideoFormat?
        get() {
            val meta = metadata ?: return null
            val id = selectedFormatID ?: return null
            return meta.formats.firstOrNull { it.id == id }
        }
}

class DownloaderViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as VidoXApp
    private val router = ExtractionRouter(application)
    private val urlDownloader = OkHttpVideoDownloader()
    private val ytdlpDownloader = YtDlpVideoDownloader(application)

    private val _state = MutableStateFlow(DownloaderUiState())
    val state: StateFlow<DownloaderUiState> = _state.asStateFlow()

    private var extractJob: Job? = null

    fun updateUrl(text: String) {
        _state.update { it.copy(urlText = text) }
    }

    fun selectFormat(id: String) {
        _state.update { it.copy(selectedFormatID = id) }
    }

    /** Clears the form so the next open starts blank. */
    fun reset() {
        extractJob?.cancel()
        extractJob = null
        _state.value = DownloaderUiState()
    }

    fun fetchMetadata() {
        extractJob?.cancel()
        extractJob = viewModelScope.launch {
            _state.update {
                it.copy(
                    errorMessage = null,
                    metadata = null,
                    selectedFormatID = null,
                    progressFraction = null,
                    isExtracting = true
                )
            }
            val url = URLNormalizer.url(_state.value.urlText)
            if (url == null) {
                _state.update {
                    it.copy(
                        isExtracting = false,
                        errorMessage = ExtractionError.InvalidURL.message
                    )
                }
                return@launch
            }
            _state.update { it.copy(urlText = url.toString()) }

            try {
                val platform = VideoPlatform.detect(url.toString())
                val timeoutMs = when (platform) {
                    VideoPlatform.FACEBOOK, VideoPlatform.REDDIT,
                    VideoPlatform.TWITCH, VideoPlatform.TWITTER -> 28_000L
                    VideoPlatform.INSTAGRAM, VideoPlatform.TIKTOK, VideoPlatform.RUMBLE -> 22_000L
                    VideoPlatform.YOUTUBE -> 12_000L
                    else -> 15_000L
                }

                val result = withTimeout(timeoutMs) { router.extract(url) }

                _state.update {
                    it.copy(
                        metadata = result,
                        selectedFormatID = result.bestVideoFormat?.id ?: result.formats.firstOrNull()?.id,
                        isExtracting = false
                    )
                }
            } catch (_: TimeoutCancellationException) {
                _state.update {
                    it.copy(
                        isExtracting = false,
                        errorMessage = PageExtractionError.Network(
                            "Timed out looking up this video. Check your connection and try again."
                        ).message
                    )
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isExtracting = false,
                        errorMessage = userFacingTransferMessage(e)
                    )
                }
            }
        }
    }

    fun startDownload(onSuccess: () -> Unit) {
        viewModelScope.launch {
            val current = _state.value
            val metadata = current.metadata ?: return@launch
            val format = current.selectedFormat ?: return@launch
            if (!metadata.allowsRealDownload) return@launch

            _state.update {
                it.copy(
                    errorMessage = null,
                    isDownloading = true,
                    progressFraction = null,
                    progressLabel = if (metadata.platform == VideoPlatform.YOUTUBE || metadata.usesYTDLP) {
                        "Preparing…"
                    } else {
                        "Starting…"
                    }
                )
            }

            var destination = app.fileStorage.makeVideoFile(metadata.title, format.fileExtension)
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
                        _state.update {
                            it.copy(
                                progressFraction = progress.fraction,
                                progressLabel = if (progress.totalBytes == null) "Downloading…" else "Finished"
                            )
                        }
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
                        _state.update {
                            it.copy(progressFraction = progress.fraction, progressLabel = label)
                        }
                    }
                }

                val size = app.fileStorage.fileSize(destination)
                val thumbnailPath = runCatching {
                    val remote = metadata.thumbnailURL ?: return@runCatching null
                    val thumbFile = app.fileStorage.makeThumbnailFile()
                    urlDownloader.download(remote, thumbFile).collect { }
                    if (thumbFile.exists() && thumbFile.length() > 0L) {
                        app.fileStorage.storedThumbnailPath(thumbFile)
                    } else {
                        thumbFile.delete()
                        null
                    }
                }.getOrNull()

                // Always warm a local frame cache so list cells show immediately.
                runCatching {
                    VideoThumbnailLoader.cachedOrGenerate(
                        destination,
                        app.fileStorage.thumbnailsDirectory
                    )
                }

                val record = DownloadedVideo(
                    title = metadata.title,
                    author = metadata.author,
                    sourceURL = metadata.sourceURL.toString(),
                    platformRaw = metadata.platform.rawValue,
                    thumbnailPath = thumbnailPath,
                    localFilePath = app.fileStorage.storedPath(destination),
                    fileExtension = destination.extension.ifEmpty { format.fileExtension },
                    fileSize = size
                )
                app.repository.insert(record)
                _state.update { it.copy(isDownloading = false, progressLabel = "Done") }
                onSuccess()
            } catch (e: Exception) {
                destination.delete()
                val message = when (e) {
                    is DownloadError.Cancelled -> null
                    else -> userFacingTransferMessage(e)
                }
                _state.update {
                    it.copy(isDownloading = false, errorMessage = message)
                }
            }
        }
    }
}
