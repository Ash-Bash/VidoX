import Foundation

/// Errors raised while resolving a URL into downloadable metadata.
enum ExtractionError: LocalizedError, Sendable {
    case invalidURL
    case unsupportedPlatform(VideoPlatform)
    case notDirectMedia
    case network(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "That doesn’t look like a valid link. Try pasting a full https:// URL."
        case .unsupportedPlatform(let platform):
            "Downloading from \(platform.displayName) isn’t available yet."
        case .notDirectMedia:
            "This isn’t a direct media file. Paste a file link (.mp4, .mov, …) or a supported video page (YouTube, Vimeo, and similar) when standalone downloads are enabled."
        case .network(let message):
            message
        case .emptyResponse:
            "The server returned an empty response."
        }
    }
}

/// Turns a pasted URL into `VideoMetadata` with one or more formats.
protocol VideoExtracting: Sendable {
    func extract(from url: URL) async throws -> VideoMetadata
}
