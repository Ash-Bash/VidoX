import Foundation

/// Resolves direct media URLs (mp4, mov, m4v, webm, etc.) into downloadable metadata.
nonisolated struct DirectMediaExtractor: VideoExtracting {
    private static let mediaExtensions: Set<String> = [
        "mp4", "mov", "m4v", "webm", "mkv", "avi", "m4a", "mp3", "aac"
    ]

    private static let mediaContentTypes: Set<String> = [
        "video/mp4", "video/quicktime", "video/webm", "video/x-m4v",
        "video/x-matroska", "audio/mp4", "audio/mpeg", "audio/aac", "application/octet-stream"
    ]

    /// Fast path check used by `ExtractionRouter` before probing the network.
    nonisolated static func looksLikeDirectMediaURL(_ url: URL) -> Bool {
        let pathExt = url.pathExtension.lowercased()
        if mediaExtensions.contains(pathExt) { return true }
        let last = url.lastPathComponent.lowercased()
        return mediaExtensions.contains { last.contains(".\($0)") }
    }

    nonisolated func extract(from url: URL) async throws -> VideoMetadata {
        let ext = mediaExtension(from: url)
        if let ext, Self.mediaExtensions.contains(ext) {
            return makeMetadata(for: url, fileExtension: ext)
        }

        // Prefer HEAD; fall back to a ranged GET when servers reject HEAD.
        if let probed = try await probeContentType(url: url) {
            let resolvedExt = Self.extension(forContentType: probed, fallback: ext ?? "mp4")
            if Self.mediaContentTypes.contains(probed) || Self.mediaExtensions.contains(resolvedExt) {
                return makeMetadata(for: url, fileExtension: resolvedExt)
            }
        }

        throw ExtractionError.notDirectMedia
    }

    private func mediaExtension(from url: URL) -> String? {
        let pathExt = url.pathExtension.lowercased()
        if Self.mediaExtensions.contains(pathExt) { return pathExt }

        // Some CDNs put the extension before query-like path segments.
        let last = url.lastPathComponent.lowercased()
        for candidate in Self.mediaExtensions {
            if last.contains(".\(candidate)") { return candidate }
        }
        return pathExt.isEmpty ? nil : pathExt
    }

    private func probeContentType(url: URL) async throws -> String? {
        if let type = try await contentType(from: url, method: "HEAD") {
            return type
        }
        // Minimal ranged GET — enough to read Content-Type without downloading the file.
        return try await contentType(from: url, method: "GET", extraHeaders: ["Range": "bytes=0-0"])
    }

    private func contentType(
        from url: URL,
        method: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ExtractionError.network("Unexpected response from server.")
            }
            // 206 is success for ranged GET; some servers answer HEAD with 405.
            guard (200..<400).contains(http.statusCode) else {
                if http.statusCode == 405 || http.statusCode == 501 { return nil }
                throw ExtractionError.network("Server returned status \(http.statusCode).")
            }
            return http.value(forHTTPHeaderField: "Content-Type")?
                .split(separator: ";")
                .first
                .map(String.init)?
                .lowercased()
        } catch let error as ExtractionError {
            throw error
        } catch {
            return nil
        }
    }

    private func makeMetadata(for url: URL, fileExtension: String) -> VideoMetadata {
        let name = url.deletingPathExtension().lastPathComponent
        let title = name.isEmpty ? "Direct video" : name.removingPercentEncoding ?? name
        let isAudio = ["m4a", "mp3", "aac"].contains(fileExtension)
        let label = isAudio ? "Audio · \(fileExtension.uppercased())" : "Video · \(fileExtension.uppercased())"

        let format = VideoFormat(
            id: "direct-\(fileExtension)",
            label: label,
            url: url,
            fileExtension: fileExtension,
            quality: nil,
            isAudioOnly: isAudio
        )

        return VideoMetadata(
            title: title,
            author: url.host,
            thumbnailURL: nil,
            platform: .unknown,
            sourceURL: url,
            formats: [format],
            allowsRealDownload: true
        )
    }

    private static func `extension`(forContentType contentType: String, fallback: String) -> String {
        switch contentType {
        case "video/mp4": "mp4"
        case "video/quicktime": "mov"
        case "video/webm": "webm"
        case "video/x-m4v": "m4v"
        case "video/x-matroska": "mkv"
        case "audio/mp4": "m4a"
        case "audio/mpeg": "mp3"
        case "audio/aac": "aac"
        default: fallback.isEmpty ? "mp4" : fallback
        }
    }
}
