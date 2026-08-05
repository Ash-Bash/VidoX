import Foundation
import AVFoundation

enum HLSDownloadError: LocalizedError, Sendable {
    case exportFailed
    case unsupported
    case cancelled

    var errorDescription: String? {
        switch self {
        case .exportFailed:
            "Couldn’t export the video stream."
        case .unsupported:
            "This stream format can’t be saved on this device."
        case .cancelled:
            "Download cancelled."
        }
    }
}

/// Downloads an HLS (`.m3u8`) stream and exports a local MP4 via AVFoundation.
enum HLSVideoDownloader {
    static func download(from hlsURL: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: hlsURL)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        guard isPlayable else { throw HLSDownloadError.unsupported }

        let outputURL = destination.deletingPathExtension().appendingPathExtension("mp4")
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw HLSDownloadError.unsupported
        }

        do {
            try await exportSession.export(to: outputURL, as: .mp4)
        } catch is CancellationError {
            throw HLSDownloadError.cancelled
        } catch {
            throw error
        }
    }
}
