import Foundation

/// Resolves video-page metadata for experimental / standalone downloads.
/// macOS uses the managed yt-dlp binary; iOS / visionOS resolve media URLs natively.
nonisolated struct ExperimentalSocialExtractor: VideoExtracting {
    #if os(macOS)
    /// android_vr / tv still return playable metadata; web clients often error with “page needs to be reloaded”.
    static let youtubeExtractorArgs =
        "youtube:player_client=android_vr,tv,-web,-mweb,-ios,-android,-android_sdkless"
    /// Same working clients for Fetch Info — do not skip the webpage/JS or YouTube returns UNPLAYABLE.
    static let youtubeExtractArgs =
        "youtube:player_client=android_vr,tv"
    /// Merge video+audio first. `/b*` is last so Fetch Info / download never die with
    /// “Requested format is not available” when DASH mp4+m4a isn’t in the list.
    static func youtubeSelector(maxHeight: Int? = nil) -> String {
        let height = maxHeight.map { "[height<=\($0)]" } ?? ""
        return "bv*\(height)[ext=mp4]+ba[ext=m4a]/bv*\(height)+ba/b*\(height)"
    }

    static var youtubeFormatSelector: String { youtubeSelector() }
    #endif

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

        // Instagram’s official extractor is login/audience-gated; resolve natively (mirrors + SnapSave).
        if platform == .instagram {
            return try await IOSPageVideoExtractor().extract(from: url)
        }

        if platform == .youtube {
            return try await extractYouTube(url: url)
        }

        if platform == .facebook {
            do {
                return try await extractFacebookWithYTDLP(url: url)
            } catch {
                if let metadata = try? await IOSPageVideoExtractor().extract(from: url) {
                    return metadata
                }
                throw error
            }
        }

        do {
            return try await extractGenericWithYTDLP(url: url, platform: platform)
        } catch {
            if let metadata = try? await IOSPageVideoExtractor().extract(from: url) {
                return metadata
            }
            throw error
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

    /// Native Innertube is usually seconds; yt-dlp can hang. First success wins, the other is cancelled.
    private func extractYouTube(url: URL) async throws -> VideoMetadata {
        try await withThrowingTaskGroup(of: VideoMetadata.self) { group in
            group.addTask {
                let native = try await IOSPageVideoExtractor().extract(from: url)
                return Self.taggedForYTDLP(native)
            }
            group.addTask {
                try await self.extractGenericWithYTDLP(url: url, platform: .youtube)
            }

            var lastError: Error = YTDLPError.invalidMetadata
            while let result = await group.nextResult() {
                switch result {
                case .success(let metadata):
                    group.cancelAll()
                    return metadata
                case .failure(let error):
                    lastError = error
                }
            }
            throw lastError
        }
    }

    /// Keep Mac downloads on yt-dlp even when metadata came from Innertube.
    private static func taggedForYTDLP(_ metadata: VideoMetadata) -> VideoMetadata {
        var formats = metadata.formats.map { format -> VideoFormat in
            guard !format.isAudioOnly else { return format }
            return VideoFormat(
                id: format.id,
                label: format.qualityTitle,
                url: format.url,
                fileExtension: "mp4",
                quality: format.quality,
                isAudioOnly: false,
                ytdlpFormatSelector: youtubeSelector(maxHeight: format.quality),
                isHLSStream: false
            )
        }
        if formats.filter({ !$0.isAudioOnly }).isEmpty {
            formats.insert(
                VideoFormat(
                    id: "best-mp4",
                    label: "Best quality",
                    url: metadata.sourceURL,
                    fileExtension: "mp4",
                    quality: nil,
                    isAudioOnly: false,
                    ytdlpFormatSelector: youtubeFormatSelector
                ),
                at: 0
            )
        }
        return VideoMetadata(
            title: metadata.title,
            author: metadata.author,
            thumbnailURL: metadata.thumbnailURL,
            platform: .youtube,
            sourceURL: metadata.sourceURL,
            formats: formats,
            allowsRealDownload: true,
            usesYTDLP: true
        )
    }

    private func extractGenericWithYTDLP(url: URL, platform: VideoPlatform) async throws -> VideoMetadata {
        var arguments = [
            "-J",
            "--no-playlist",
            "--no-warnings",
            "--socket-timeout", "8",
            "--retries", "1",
            // Default yt-dlp `-f` fails YouTube lookups when DASH isn’t listed yet.
            "-f", "all",
            "--ignore-no-formats-error"
        ]
        if platform == .youtube {
            arguments += ["--extractor-args", Self.youtubeExtractArgs]
        }
        arguments.append(url.absoluteString)

        let data = try await YTDLPTool.run(arguments: arguments, forDownload: false)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTDLPError.invalidMetadata
        }

        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (json["uploader"] as? String) ?? (json["channel"] as? String)
        let thumbnail = (json["thumbnail"] as? String).flatMap(URL.init(string:))
        let rawFormats = json["formats"] as? [[String: Any]] ?? []
        let defaultExt = (json["ext"] as? String) ?? "mp4"

        var formats: [VideoFormat] = curatedFormats(from: rawFormats, pageURL: url, platform: platform)
        if formats.isEmpty {
            formats = [
                VideoFormat(
                    id: "best",
                    label: "Best available",
                    url: url,
                    fileExtension: defaultExt,
                    quality: nil,
                    isAudioOnly: false,
                    ytdlpFormatSelector: Self.youtubeFormatSelector
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

    /// YouTube: never download a muxed itag directly (18/22 403). Offer merge/HLS selectors.
    /// Other sites: progressive files are fine and avoid needing ffmpeg.
    private func curatedFormats(from raw: [[String: Any]], pageURL: URL, platform: VideoPlatform) -> [VideoFormat] {
        if platform == .youtube {
            return youtubeDownloadFormats(from: raw, pageURL: pageURL)
        }

        var result: [VideoFormat] = []
        var seenHeights = Set<Int>()

        let progressive = raw.compactMap { entry -> (height: Int, id: String, ext: String)? in
            guard let id = Self.formatID(from: entry) else { return nil }
            let height = Self.intValue(entry["height"])
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
                ytdlpFormatSelector: "bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b"
            ),
            at: 0
        )

        appendAudioFormat(from: raw, pageURL: pageURL, into: &result)
        return result
    }

    private func youtubeDownloadFormats(from raw: [[String: Any]], pageURL: URL) -> [VideoFormat] {
        var heights = Set<Int>()
        for entry in raw {
            let id = Self.formatID(from: entry) ?? ""
            if id == "18" || id.hasPrefix("18-") || id == "22" || id.hasPrefix("22-") { continue }
            let vcodec = entry["vcodec"] as? String ?? "none"
            let height = Self.intValue(entry["height"])
            guard vcodec != "none", let height, height >= 360 else { continue }
            heights.insert(height)
        }
        let sortedHeights = heights.sorted(by: >)
        var result: [VideoFormat] = []
        if let bestHeight = sortedHeights.first {
            result.append(
                VideoFormat(
                    id: "yt-\(bestHeight)",
                    label: "\(bestHeight)p",
                    url: pageURL,
                    fileExtension: "mp4",
                    quality: bestHeight,
                    isAudioOnly: false,
                    ytdlpFormatSelector: Self.youtubeSelector()
                )
            )
            for height in sortedHeights.dropFirst().prefix(3) {
                result.append(
                    VideoFormat(
                        id: "yt-\(height)",
                        label: "\(height)p",
                        url: pageURL,
                        fileExtension: "mp4",
                        quality: height,
                        isAudioOnly: false,
                        ytdlpFormatSelector: Self.youtubeSelector(maxHeight: height)
                    )
                )
            }
        } else {
            result.append(
                VideoFormat(
                    id: "best-mp4",
                    label: "Best quality",
                    url: pageURL,
                    fileExtension: "mp4",
                    quality: nil,
                    isAudioOnly: false,
                    ytdlpFormatSelector: Self.youtubeSelector()
                )
            )
        }
        appendAudioFormat(from: raw, pageURL: pageURL, into: &result)
        return result
    }

    private func appendAudioFormat(from raw: [[String: Any]], pageURL: URL, into result: inout [VideoFormat]) {
        if let audio = raw.first(where: {
            ($0["vcodec"] as? String ?? "none") == "none"
                && ($0["acodec"] as? String ?? "none") != "none"
                && Self.formatID(from: $0) != nil
        }), let id = Self.formatID(from: audio) {
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
    }

    private static func formatID(from entry: [String: Any]) -> String? {
        if let string = entry["format_id"] as? String, !string.isEmpty { return string }
        if let number = entry["format_id"] as? Int { return String(number) }
        if let number = entry["format_id"] as? NSNumber { return number.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
    #endif
}
