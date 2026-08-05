package com.ashbash.vidoxproject.services.extraction

import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.models.VideoPlatform
import java.net.URL

sealed class ExtractionError(message: String) : Exception(message) {
    data object InvalidURL : ExtractionError(
        "That doesn’t look like a valid link. Try pasting a full https:// URL."
    )
    data class UnsupportedPlatform(val platform: VideoPlatform) : ExtractionError(
        "Downloading from ${platform.displayName} isn’t available yet."
    )
    data object NotDirectMedia : ExtractionError(
        "This isn’t a direct media file. Paste a file link (.mp4, .mov, …) or a supported video page when standalone downloads are enabled."
    )
    data class Network(val detail: String) : ExtractionError(detail)
    data object EmptyResponse : ExtractionError("The server returned an empty response.")
}

sealed class PageExtractionError(message: String) : Exception(message) {
    data object Unsupported : PageExtractionError(
        "This link isn’t supported for download yet."
    )
    data object NoMediaFound : PageExtractionError(
        "Couldn’t find a downloadable video on that page. Try another link or a direct .mp4 URL."
    )
    data class Network(val detail: String) : PageExtractionError(detail)
    data object InvalidResponse : PageExtractionError(
        "The site returned data VidoX couldn’t read."
    )
}

fun interface VideoExtracting {
    suspend fun extract(from: URL): VideoMetadata
}
