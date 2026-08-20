import Foundation

/// A selectable media stream or file offered by an extractor.
struct VideoFormat: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let url: URL
    let fileExtension: String
    let quality: Int?
    let isAudioOnly: Bool
    /// When set, download with `yt-dlp -f` instead of fetching `url` directly.
    let ytdlpFormatSelector: String?
    /// When `true`, download via AVFoundation HLS export instead of raw URLSession bytes.
    let isHLSStream: Bool

    init(
        id: String,
        label: String,
        url: URL,
        fileExtension: String,
        quality: Int?,
        isAudioOnly: Bool,
        ytdlpFormatSelector: String? = nil,
        isHLSStream: Bool = false
    ) {
        self.id = id
        self.label = label
        self.url = url
        self.fileExtension = fileExtension
        self.quality = quality
        self.isAudioOnly = isAudioOnly
        self.ytdlpFormatSelector = ytdlpFormatSelector
        self.isHLSStream = isHLSStream
    }

    var qualityTitle: String {
        if isAudioOnly { return "Audio only" }
        if let quality { return "\(quality)p" }
        return label
    }

    var formatDetail: String {
        let kind = isAudioOnly ? "Audio" : (isHLSStream ? "Stream" : "Video")
        return "\(kind) · \(fileExtension.uppercased())"
    }
}

/// Result of URL extraction — used by the downloader UI before persisting to SwiftData.
struct VideoMetadata: Sendable {
    let title: String
    let author: String?
    let thumbnailURL: URL?
    let platform: VideoPlatform
    let sourceURL: URL
    let formats: [VideoFormat]
    /// `false` for stub social extractions until a rights-safe engine exists.
    let allowsRealDownload: Bool
    /// Personal / debug path that shells out to `yt-dlp`.
    let usesYTDLP: Bool

    init(
        title: String,
        author: String? = nil,
        thumbnailURL: URL? = nil,
        platform: VideoPlatform,
        sourceURL: URL,
        formats: [VideoFormat],
        allowsRealDownload: Bool,
        usesYTDLP: Bool = false
    ) {
        self.title = title
        self.author = author
        self.thumbnailURL = thumbnailURL
        self.platform = platform
        self.sourceURL = sourceURL
        self.formats = formats
        self.allowsRealDownload = allowsRealDownload
        self.usesYTDLP = usesYTDLP
    }

    var bestVideoFormat: VideoFormat? {
        let video = formats.filter { !$0.isAudioOnly }
        // Prefer progressive/muxed files, then HLS export, then adaptive video-only.
        let ranked = video.sorted { lhs, rhs in
            // Progressive/merged files first; YouTube HLS currently 403s without a PO token.
            let leftScore = (lhs.isHLSStream ? 1_000_000 : 2_000_000) + (lhs.quality ?? 0)
            let rightScore = (rhs.isHLSStream ? 1_000_000 : 2_000_000) + (rhs.quality ?? 0)
            // Labels that mention video-only rank last.
            let leftPenalty = lhs.label.localizedCaseInsensitiveContains("video only") ? 500_000 : 0
            let rightPenalty = rhs.label.localizedCaseInsensitiveContains("video only") ? 500_000 : 0
            return (leftScore - leftPenalty) > (rightScore - rightPenalty)
        }
        return ranked.first
    }

    var bestAudioFormat: VideoFormat? {
        formats
            .filter(\.isAudioOnly)
            .sorted { ($0.quality ?? 0) > ($1.quality ?? 0) }
            .first
    }
}
