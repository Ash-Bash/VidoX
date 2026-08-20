import Foundation
import AVFoundation

enum HLSDownloadError: LocalizedError, Sendable {
    case exportFailed
    case unsupported
    case cancelled

    var errorDescription: String? {
        switch self {
        case .exportFailed:
            "Couldn’t save this stream. The site may have blocked it (this is often a 403). Try again, or pick another quality."
        case .unsupported:
            "This stream format can’t be saved on this device."
        case .cancelled:
            "Download cancelled."
        }
    }
}

/// Downloads an HLS (`.m3u8`) stream and exports a local MP4 via AVFoundation.
enum HLSVideoDownloader {
    private static let youtubeIOSUserAgent =
        "com.google.ios.youtube/20.50.3 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)"

    static func download(from hlsURL: URL, to destination: URL) async throws {
        let host = hlsURL.host?.lowercased() ?? ""
        let asset: AVURLAsset
        if host.contains("googlevideo.com") || host.contains("youtube.com") {
            asset = AVURLAsset(
                url: hlsURL,
                options: [
                    "AVURLAssetHTTPHeaderFieldsKey": [
                        "User-Agent": youtubeIOSUserAgent,
                        "Referer": "https://www.youtube.com/"
                    ]
                ]
            )
        } else {
            asset = AVURLAsset(url: hlsURL)
        }
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
            if let code = TransferErrorHelp.httpStatus(in: error.localizedDescription) {
                throw DownloadError.httpStatus(code)
            }
            throw HLSDownloadError.exportFailed
        }
    }
}
