import Foundation

/// Chooses direct-file, page-engine, or preview stub extraction.
nonisolated struct ExtractionRouter: VideoExtracting {
    private let pagePreviewExtractor: any VideoExtracting
    private let pageDownloadExtractor: any VideoExtracting
    private let directExtractor: any VideoExtracting

    init(
        pagePreviewExtractor: any VideoExtracting = StubSocialExtractor(),
        pageDownloadExtractor: any VideoExtracting = ExperimentalSocialExtractor(),
        directExtractor: any VideoExtracting = DirectMediaExtractor()
    ) {
        self.pagePreviewExtractor = pagePreviewExtractor
        self.pageDownloadExtractor = pageDownloadExtractor
        self.directExtractor = directExtractor
    }

    nonisolated func extract(from url: URL) async throws -> VideoMetadata {
        // 1) Raw media files always use URLSession (.mp4, .mov, …).
        if DirectMediaExtractor.looksLikeDirectMediaURL(url) {
            return try await directExtractor.extract(from: url)
        }

        let platform = VideoPlatform.detect(from: url.absoluteString)

        // 2) Standalone mode: any standard video page via the built-in engine
        //    (YouTube, Vimeo, Reddit, Twitch, Streamable, Dailymotion, and more).
        if FeatureFlags.experimentalSocialDownloads {
            return try await pageDownloadExtractor.extract(from: url)
        }

        // 3) App Store–ready: known page hosts get a preview; otherwise try direct.
        if platform != .unknown {
            return try await pagePreviewExtractor.extract(from: url)
        }

        return try await directExtractor.extract(from: url)
    }
}
