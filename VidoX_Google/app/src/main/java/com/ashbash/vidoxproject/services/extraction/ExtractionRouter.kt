package com.ashbash.vidoxproject.services.extraction

import android.content.Context
import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.models.VideoPlatform
import com.ashbash.vidoxproject.util.FeatureFlags
import java.net.URL

/** Chooses direct-file, page-engine, or preview stub extraction. */
class ExtractionRouter(
    appContext: Context,
    private val pagePreviewExtractor: VideoExtracting = StubSocialExtractor(),
    private val pageDownloadExtractor: VideoExtracting = ExperimentalSocialExtractor(appContext),
    private val directExtractor: VideoExtracting = DirectMediaExtractor()
) : VideoExtracting {

    override suspend fun extract(from: URL): VideoMetadata {
        if (DirectMediaExtractor.looksLikeDirectMediaURL(from)) {
            return directExtractor.extract(from)
        }

        val platform = VideoPlatform.detect(from.toString())

        if (FeatureFlags.experimentalSocialDownloads) {
            return pageDownloadExtractor.extract(from)
        }

        if (platform != VideoPlatform.UNKNOWN) {
            return pagePreviewExtractor.extract(from)
        }

        return directExtractor.extract(from)
    }
}
