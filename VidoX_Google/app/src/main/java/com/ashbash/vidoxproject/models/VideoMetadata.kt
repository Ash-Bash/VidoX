package com.ashbash.vidoxproject.models

import java.net.URL

/** A selectable media stream or file offered by an extractor. */
data class VideoFormat(
    val id: String,
    val label: String,
    val url: URL,
    val fileExtension: String,
    val quality: Int?,
    val isAudioOnly: Boolean,
    val ytdlpFormatSelector: String? = null,
    val isHlsStream: Boolean = false
)

/** Result of URL extraction — used by the downloader UI before persisting. */
data class VideoMetadata(
    val title: String,
    val author: String? = null,
    val thumbnailURL: URL? = null,
    val platform: VideoPlatform,
    val sourceURL: URL,
    val formats: List<VideoFormat>,
    val allowsRealDownload: Boolean,
    val usesYTDLP: Boolean = false
) {
    val bestVideoFormat: VideoFormat?
        get() {
            val video = formats.filter { !it.isAudioOnly }
            return video.sortedByDescending { format ->
                val base = (if (format.isHlsStream) 1_000_000 else 2_000_000) + (format.quality ?: 0)
                val penalty = if (format.label.contains("video only", ignoreCase = true)) 500_000 else 0
                base - penalty
            }.firstOrNull()
        }

    val bestAudioFormat: VideoFormat?
        get() = formats
            .filter { it.isAudioOnly }
            .sortedByDescending { it.quality ?: 0 }
            .firstOrNull()
}
