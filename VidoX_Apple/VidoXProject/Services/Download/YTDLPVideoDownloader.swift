import Foundation

#if os(macOS)
/// Downloads via local `yt-dlp` when experimental social downloads are enabled.
struct YTDLPVideoDownloader: VideoDownloading {
    func download(
        from remoteURL: URL,
        to destination: URL
    ) -> AsyncThrowingStream<DownloadProgress, Error> {
        download(pageURL: remoteURL, formatSelector: ExperimentalSocialExtractor.youtubeFormatSelector, to: destination)
    }

    func download(
        pageURL: URL,
        formatSelector: String,
        to destination: URL
    ) -> AsyncThrowingStream<DownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let directory = destination.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                    let workID = UUID().uuidString
                    let template = directory
                        .appendingPathComponent("\(workID).%(ext)s")
                        .path

                    continuation.yield(DownloadProgress(bytesReceived: 0, totalBytes: nil))

                    var arguments = [
                        "-f", formatSelector,
                        "--no-playlist",
                        "--no-warnings",
                        "--merge-output-format", "mp4",
                        "-o", template
                    ]
                    let host = pageURL.host?.lowercased() ?? ""
                    if host.contains("youtube.com") || host.contains("youtu.be") {
                        arguments += [
                            "--extractor-args", ExperimentalSocialExtractor.youtubeExtractorArgs,
                            "--check-formats",
                            "--remote-components", "ejs:github"
                        ]
                    }
                    arguments.append(pageURL.absoluteString)

                    _ = try await YTDLPTool.run(arguments: arguments, forDownload: true)

                    let produced = try FileManager.default.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ).first { $0.lastPathComponent.hasPrefix(workID) }

                    guard let produced else {
                        throw DownloadError.writeFailed("Download finished but the output file was not found.")
                    }

                    let finalURL = destination
                        .deletingPathExtension()
                        .appendingPathExtension(produced.pathExtension.isEmpty ? "mp4" : produced.pathExtension)

                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: produced, to: finalURL)

                    // If the caller expected a different extension path, mirror when needed.
                    if finalURL.path != destination.path,
                       destination.pathExtension == finalURL.pathExtension {
                        // already aligned via pathExtension swap above
                    }

                    let size = FileStorage.fileSize(at: finalURL)
                    continuation.yield(DownloadProgress(bytesReceived: size, totalBytes: size))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
#endif
