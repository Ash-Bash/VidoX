import Foundation

/// Resolves video-page metadata for experimental / standalone downloads.
/// macOS uses the managed yt-dlp binary; iOS / visionOS resolve media URLs natively.
nonisolated struct ExperimentalSocialExtractor: VideoExtracting {
    nonisolated func extract(from url: URL) async throws -> VideoMetadata {
        #if os(macOS)
        try await extractWithYTDLP(url: url)
        #else
        try await IOSPageVideoExtractor().extract(from: url)
        #endif
    }

    #if os(macOS)
    private func extractWithYTDLP(url: URL) async throws -> VideoMetadata {
        let detected = VideoPlatform.detect(from: url.absoluteString)
        let platform: VideoPlatform = detected == .unknown ? .web : detected

        // Prefer native resolvers for sites yt-dlp often fails on (login walls / challenges),
        // then fall back to yt-dlp. On success this also keeps iOS/macOS behaviour aligned.
        if Self.prefersNativeExtractor(platform),
           let metadata = try? await IOSPageVideoExtractor().extract(from: url) {
            return metadata
        }

        if platform == .facebook {
            return try await extractFacebookWithYTDLP(url: url)
        }

        do {
            return try await extractGenericWithYTDLP(url: url, platform: platform)
        } catch {
            // Last chance: native page resolvers (X, Reddit, Vimeo, …) when yt-dlp fails.
            if let metadata = try? await IOSPageVideoExtractor().extract(from: url) {
                return metadata
            }
            throw error
        }
    }

    private static func prefersNativeExtractor(_ platform: VideoPlatform) -> Bool {
        switch platform {
        case .facebook, .instagram, .twitter, .tiktok, .reddit, .streamable:
            true
        default:
            false
        }
    }

    private func extractFacebookWithYTDLP(url: URL) async throws -> VideoMetadata {
        var candidates = [url]
        if let videoID = URLNormalizer.facebookVideoID(from: url),
           let watchURL = URL(string: "https://www.facebook.com/watch/?v=\(videoID)"),
           watchURL.absoluteString != url.absoluteString {
            candidates.append(watchURL)
        }
        if let videoID = URLNormalizer.facebookVideoID(from: url),
           let mobileWatch = URL(string: "https://m.facebook.com/watch/?v=\(videoID)&_rdr") {
            candidates.append(mobileWatch)
        }

        var lastError: Error = YTDLPError.invalidMetadata
        for candidate in candidates {
            do {
                return try await extractGenericWithYTDLP(url: candidate, platform: .facebook)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func extractGenericWithYTDLP(url: URL, platform: VideoPlatform) async throws -> VideoMetadata {
        var arguments = [
            "-J",
            "--no-playlist",
            "--no-warnings",
            "--socket-timeout", "10"
        ]
        // Android client is usually the fastest YouTube path.
        if platform == .youtube {
            arguments += ["--extractor-args", "youtube:player_client=android"]
        }
        arguments.append(url.absoluteString)

        let data = try await YTDLPTool.run(arguments: arguments)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTDLPError.invalidMetadata
        }

        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (json["uploader"] as? String) ?? (json["channel"] as? String)
        let thumbnail = (json["thumbnail"] as? String).flatMap(URL.init(string:))
        let rawFormats = json["formats"] as? [[String: Any]] ?? []
        let defaultExt = (json["ext"] as? String) ?? "mp4"

        var formats: [VideoFormat] = curatedFormats(from: rawFormats, pageURL: url)
        if formats.isEmpty {
            formats = [
                VideoFormat(
                    id: "best",
                    label: "Best available",
                    url: url,
                    fileExtension: defaultExt,
                    quality: nil,
                    isAudioOnly: false,
                    ytdlpFormatSelector: "best[ext=mp4]/best"
                )
            ]
        }

        return VideoMetadata(
            title: (title?.isEmpty == false ? title! : "\(platform.displayName) video"),
            author: author,
            thumbnailURL: thumbnail,
            platform: platform,
            sourceURL: url,
            formats: formats,
            allowsRealDownload: true,
            usesYTDLP: true
        )
    }

    /// Prefer progressive (video+audio) formats so downloads work without bundling ffmpeg.
    private func curatedFormats(from raw: [[String: Any]], pageURL: URL) -> [VideoFormat] {
        var result: [VideoFormat] = []
        var seenHeights = Set<Int>()

        let progressive = raw.compactMap { entry -> (height: Int, id: String, ext: String)? in
            guard let id = entry["format_id"] as? String else { return nil }
            let height = entry["height"] as? Int
            let vcodec = entry["vcodec"] as? String ?? "none"
            let acodec = entry["acodec"] as? String ?? "none"
            guard let height, vcodec != "none", acodec != "none" else { return nil }
            guard height >= 360 else { return nil }
            let ext = (entry["ext"] as? String) ?? "mp4"
            return (height, id, ext)
        }
        .sorted { $0.height > $1.height }

        for candidate in progressive {
            if seenHeights.contains(candidate.height) { continue }
            seenHeights.insert(candidate.height)
            result.append(
                VideoFormat(
                    id: candidate.id,
                    label: "\(candidate.height)p",
                    url: pageURL,
                    fileExtension: candidate.ext,
                    quality: candidate.height,
                    isAudioOnly: false,
                    ytdlpFormatSelector: candidate.id
                )
            )
            if result.count >= 4 { break }
        }

        result.insert(
            VideoFormat(
                id: "best-mp4",
                label: "Best (single file)",
                url: pageURL,
                fileExtension: "mp4",
                quality: progressive.first?.height,
                isAudioOnly: false,
                ytdlpFormatSelector: "best[ext=mp4]/best"
            ),
            at: 0
        )

        if let audio = raw.first(where: {
            ($0["vcodec"] as? String ?? "none") == "none"
                && ($0["acodec"] as? String ?? "none") != "none"
                && ($0["format_id"] as? String) != nil
        }), let id = audio["format_id"] as? String {
            let ext = (audio["ext"] as? String) ?? "m4a"
            result.append(
                VideoFormat(
                    id: "audio-\(id)",
                    label: "Audio only",
                    url: pageURL,
                    fileExtension: ext,
                    quality: audio["abr"] as? Int,
                    isAudioOnly: true,
                    ytdlpFormatSelector: id
                )
            )
        }

        return result
    }
    #endif
}
