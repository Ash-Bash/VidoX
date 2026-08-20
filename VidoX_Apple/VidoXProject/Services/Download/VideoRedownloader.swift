import Foundation
import SwiftData

/// Replaces the on-disk file for an existing library entry without creating a duplicate record.
enum VideoRedownloader {
    enum RedownloadError: LocalizedError {
        case invalidSourceURL
        case downloadNotAvailable
        case noFormat

        var errorDescription: String? {
            switch self {
            case .invalidSourceURL:
                return "This library item doesn’t have a valid source URL."
            case .downloadNotAvailable:
                return "This source can’t be downloaded automatically right now."
            case .noFormat:
                return "No downloadable format was found for this video."
            }
        }
    }

    /// Downloads the best available format for `video.sourceURL` and updates the same SwiftData row.
    @MainActor
    static func redownload(
        video: DownloadedVideo,
        modelContext: ModelContext,
        onProgress: @escaping (String, Double?) -> Void
    ) async throws {
        guard let sourceURL = URLNormalizer.url(from: video.sourceURL) else {
            throw RedownloadError.invalidSourceURL
        }

        onProgress("Looking up…", nil)
        let metadata = try await ExtractionRouter().extract(from: sourceURL)
        guard metadata.allowsRealDownload else {
            throw RedownloadError.downloadNotAvailable
        }
        guard let format = metadata.bestVideoFormat ?? metadata.formats.first(where: { !$0.isAudioOnly }) else {
            throw RedownloadError.noFormat
        }

        onProgress(metadata.usesYTDLP ? "Preparing…" : "Starting…", nil)

        var destination = FileStorage.makeVideoFileURL(
            preferredName: metadata.title.isEmpty ? video.title : metadata.title,
            fileExtension: format.fileExtension
        )

        let urlDownloader = URLSessionVideoDownloader()

        do {
            #if os(macOS)
            if metadata.platform == .youtube || (metadata.usesYTDLP && format.ytdlpFormatSelector != nil) {
                let ytdlpDownloader = YTDLPVideoDownloader()
                let selector = format.ytdlpFormatSelector
                    ?? ExperimentalSocialExtractor.youtubeFormatSelector
                for try await progress in ytdlpDownloader.download(
                    pageURL: metadata.sourceURL,
                    formatSelector: selector,
                    to: destination
                ) {
                    onProgress(
                        progress.totalBytes == nil ? "Downloading…" : "Finished",
                        progress.fraction
                    )
                }
                let directory = destination.deletingLastPathComponent()
                let stem = destination.deletingPathExtension().lastPathComponent
                if let match = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )
                    .filter({ $0.lastPathComponent.hasPrefix(stem) })
                    .sorted(by: { $0.lastPathComponent.count < $1.lastPathComponent.count })
                    .first {
                    destination = match
                }
            } else if format.isHLSStream {
                onProgress("Exporting stream…", nil)
                let exportDestination = destination.deletingPathExtension().appendingPathExtension("mp4")
                try await HLSVideoDownloader.download(from: format.url, to: exportDestination)
                destination = exportDestination
                onProgress("Finished", 1)
            } else {
                try await downloadURLSession(
                    urlDownloader: urlDownloader,
                    from: format.url,
                    to: destination,
                    onProgress: onProgress
                )
            }
            #else
            if format.isHLSStream {
                onProgress("Exporting stream…", nil)
                let exportDestination = destination.deletingPathExtension().appendingPathExtension("mp4")
                try await HLSVideoDownloader.download(from: format.url, to: exportDestination)
                destination = exportDestination
                onProgress("Finished", 1)
            } else {
                try await downloadURLSession(
                    urlDownloader: urlDownloader,
                    from: format.url,
                    to: destination,
                    onProgress: onProgress
                )
            }
            #endif

            let previousPath = video.localFilePath
            let size = FileStorage.fileSize(at: destination)
            let storedPath = FileStorage.storedPath(for: destination)

            if !metadata.title.isEmpty {
                video.title = metadata.title
            }
            if let author = metadata.author {
                video.author = author
            }
            video.platformRaw = metadata.platform.rawValue
            video.localFilePath = storedPath
            video.fileExtension = destination.pathExtension.isEmpty
                ? format.fileExtension
                : destination.pathExtension
            video.fileSize = size
            video.downloadedAt = .now

            try modelContext.save()
            LocalSyncService.shared.noteUpserted(videoID: video.id)

            if previousPath != storedPath {
                FileStorage.removeFile(at: previousPath)
            }
        } catch {
            FileStorage.removeFile(at: destination.path)
            throw error
        }
    }

    private static func downloadURLSession(
        urlDownloader: URLSessionVideoDownloader,
        from remoteURL: URL,
        to destination: URL,
        onProgress: @escaping (String, Double?) -> Void
    ) async throws {
        for try await progress in urlDownloader.download(from: remoteURL, to: destination) {
            if let total = progress.totalBytes {
                let received = ByteCountFormatter.string(fromByteCount: progress.bytesReceived, countStyle: .file)
                let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                onProgress("\(received) of \(totalText)", progress.fraction)
            } else {
                let received = ByteCountFormatter.string(fromByteCount: progress.bytesReceived, countStyle: .file)
                onProgress("\(received) downloaded", progress.fraction)
            }
        }
    }
}
