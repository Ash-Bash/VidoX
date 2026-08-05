import Foundation

enum DownloadError: LocalizedError, Sendable {
    case cancelled
    case invalidResponse
    case httpStatus(Int)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Download cancelled."
        case .invalidResponse:
            "Invalid download response."
        case .httpStatus(let code):
            "Download failed with status \(code)."
        case .writeFailed(let message):
            "Could not save the file: \(message)"
        }
    }
}

/// Progress updates emitted while a file is transferring.
struct DownloadProgress: Sendable {
    let bytesReceived: Int64
    let totalBytes: Int64?

    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return Double(bytesReceived) / Double(totalBytes)
    }
}

protocol VideoDownloading: Sendable {
    /// Downloads `remoteURL` to `destination`, yielding progress updates.
    func download(
        from remoteURL: URL,
        to destination: URL
    ) -> AsyncThrowingStream<DownloadProgress, Error>
}
