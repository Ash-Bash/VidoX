import Foundation

/// Streams a remote file to disk with byte-level progress via URLSession.
/// Uses `nonisolated(unsafe)` storage so URLSession callbacks can run off the MainActor
/// (project default actor isolation is MainActor).
final class URLSessionVideoDownloader: NSObject, VideoDownloading, URLSessionDownloadDelegate, @unchecked Sendable {
    /// Must match the ANDROID_VR Innertube client used for progressive YouTube URLs.
    private static let youtubeVRUserAgent =
        "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
    private static let youtubeIOSUserAgent =
        "com.google.ios.youtube/20.50.3 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)"

    nonisolated(unsafe) private var session: URLSession!
    nonisolated(unsafe) private var continuations: [Int: AsyncThrowingStream<DownloadProgress, Error>.Continuation] = [:]
    nonisolated(unsafe) private var destinations: [Int: URL] = [:]
    nonisolated(unsafe) private let lock = NSLock()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    nonisolated func download(
        from remoteURL: URL,
        to destination: URL
    ) -> AsyncThrowingStream<DownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            var request = URLRequest(url: remoteURL)
            let host = remoteURL.host?.lowercased() ?? ""
            if host.contains("googlevideo.com") || host.contains("youtube.com") {
                // Match Innertube client identity. Safari UA + Origin is a common 403.
                let isHLS = remoteURL.path.lowercased().contains(".m3u8")
                    || remoteURL.absoluteString.lowercased().contains("manifest/hls")
                request.setValue(
                    isHLS ? Self.youtubeIOSUserAgent : Self.youtubeVRUserAgent,
                    forHTTPHeaderField: "User-Agent"
                )
                request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
            } else {
                request.setValue(
                    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                    forHTTPHeaderField: "User-Agent"
                )
            }
            if host.contains("cdninstagram.com")
                        || host.contains("fbcdn.net")
                        || host.contains("scontent") {
                // Meta CDNs serve both Instagram and Facebook progressive files.
                request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")
                request.setValue("https://www.instagram.com", forHTTPHeaderField: "Origin")
            } else if host.contains("ssscdn.io")
                        || host.contains("rapidcdn.app")
                        || host.contains("getmyfb")
                        || host.contains("facebook.com") {
                request.setValue("https://www.facebook.com/", forHTTPHeaderField: "Referer")
                request.setValue("https://www.facebook.com", forHTTPHeaderField: "Origin")
            } else if host.contains("tiktokcdn")
                        || host.contains("tiktok.com")
                        || host.contains("byteoversea")
                        || host.contains("musical.ly")
                        || host.contains("tokcdn") {
                request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
                request.setValue("https://www.tiktok.com", forHTTPHeaderField: "Origin")
            } else if host.contains("twimg.com") || host.contains("video.twimg.com") || host.contains("x.com") {
                request.setValue("https://x.com/", forHTTPHeaderField: "Referer")
                request.setValue("https://x.com", forHTTPHeaderField: "Origin")
            } else if host.contains("vimeocdn.com") || host.contains("vimeo.com") {
                request.setValue("https://vimeo.com/", forHTTPHeaderField: "Referer")
                request.setValue("https://vimeo.com", forHTTPHeaderField: "Origin")
            } else if host.contains("dailymotion.com") || host.contains("dmcdn.net") || host.contains("dmxleo") {
                request.setValue("https://www.dailymotion.com/", forHTTPHeaderField: "Referer")
            } else if host.contains("redd.it") || host.contains("reddit.com") || host.contains("redditmedia") {
                request.setValue("https://www.reddit.com/", forHTTPHeaderField: "Referer")
            } else if host.contains("ttvnw.net") || host.contains("twitchcdn") || host.contains("twitch.tv") {
                request.setValue("https://www.twitch.tv/", forHTTPHeaderField: "Referer")
            } else if host.contains("streamable.com") {
                request.setValue("https://streamable.com/", forHTTPHeaderField: "Referer")
            } else if host.contains("rumble.com") || host.contains("rmbl.ws") {
                request.setValue("https://rumble.com/", forHTTPHeaderField: "Referer")
            }

            let task = self.session.downloadTask(with: request)
            self.lock.lock()
            self.continuations[task.taskIdentifier] = continuation
            self.destinations[task.taskIdentifier] = destination
            self.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.remove(taskID: task.taskIdentifier)
            }

            task.resume()
        }
    }

    private nonisolated func remove(taskID: Int) {
        lock.lock()
        continuations.removeValue(forKey: taskID)
        destinations.removeValue(forKey: taskID)
        lock.unlock()
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let continuation = continuations[downloadTask.taskIdentifier]
        lock.unlock()
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        continuation?.yield(DownloadProgress(bytesReceived: totalBytesWritten, totalBytes: total))
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        let continuation = continuations[downloadTask.taskIdentifier]
        let destination = destinations[downloadTask.taskIdentifier]
        lock.unlock()

        guard let continuation, let destination else { return }

        do {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                continuation.finish(throwing: DownloadError.httpStatus(http.statusCode))
                remove(taskID: downloadTask.taskIdentifier)
                return
            }

            let directory = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            // URLSession may delete the temp file after this callback returns; copy immediately.
            try FileManager.default.copyItem(at: location, to: destination)
            continuation.finish()
        } catch {
            continuation.finish(throwing: DownloadError.writeFailed(error.localizedDescription))
        }
        remove(taskID: downloadTask.taskIdentifier)
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        lock.lock()
        let continuation = continuations[task.taskIdentifier]
        lock.unlock()
        if (error as NSError).code == NSURLErrorCancelled {
            continuation?.finish(throwing: DownloadError.cancelled)
        } else {
            continuation?.finish(throwing: error)
        }
        remove(taskID: task.taskIdentifier)
    }
}
