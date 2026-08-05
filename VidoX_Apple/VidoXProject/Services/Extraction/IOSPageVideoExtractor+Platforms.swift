import Foundation

/// Dedicated native resolvers for platforms that usually fail generic HTML scraping.
extension IOSPageVideoExtractor {

    // MARK: - Routing helpers

    /// Returns metadata for platforms with dedicated resolvers, or `nil` to continue.
    func extractKnownPlatform(from url: URL, platform: VideoPlatform) async throws -> VideoMetadata? {
        switch platform {
        case .twitter:
            return try await extractTwitter(from: url)
        case .vimeo:
            return try await extractVimeo(from: url)
        case .dailymotion:
            return try await extractDailymotion(from: url)
        case .reddit:
            return try await extractReddit(from: url)
        case .twitch:
            return try await extractTwitch(from: url)
        case .streamable:
            return try await extractStreamable(from: url)
        case .rumble:
            return try await extractRumble(from: url)
        default:
            return nil
        }
    }

    // MARK: - X / Twitter

    private func extractTwitter(from sourceURL: URL) async throws -> VideoMetadata {
        guard let statusID = Self.twitterStatusID(from: sourceURL) else {
            throw PageExtractionError.network(
                "Couldn’t read that X link. Use a post URL like x.com/user/status/…"
            )
        }

        let endpoints = [
            "https://api.fxtwitter.com/status/\(statusID)",
            "https://api.vxtwitter.com/Twitter/status/\(statusID)"
        ].compactMap(URL.init(string:))

        for endpoint in endpoints {
            if let metadata = await fetchTwitterAPI(endpoint: endpoint, sourceURL: sourceURL) {
                return metadata
            }
        }

        if let metadata = try? await extractFromHTMLPage(url: sourceURL, platform: .twitter),
           metadata.formats.contains(where: { !$0.isAudioOnly }) {
            return metadata
        }

        throw PageExtractionError.network(
            "Couldn’t resolve this X video. It may be private, deleted, or have no video attached."
        )
    }

    private func fetchTwitterAPI(endpoint: URL, sourceURL: URL) async -> VideoMetadata? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return metadataFromTwitterJSON(json, sourceURL: sourceURL)
        } catch {
            return nil
        }
    }

    private func metadataFromTwitterJSON(_ json: [String: Any], sourceURL: URL) -> VideoMetadata? {
        let tweet = (json["tweet"] as? [String: Any]) ?? json
        let media = tweet["media"] as? [String: Any]
        let videos = (media?["videos"] as? [[String: Any]])
            ?? (media?["all"] as? [[String: Any]])
            ?? []

        var formats: [VideoFormat] = []
        var seen = Set<String>()
        var thumbnail: URL?

        for (index, video) in videos.enumerated() {
            let type = (video["type"] as? String)?.lowercased() ?? "video"
            if type.contains("photo") || type.contains("image") { continue }

            if thumbnail == nil {
                thumbnail = (video["thumbnail_url"] as? String).flatMap(URL.init(string:))
                    ?? (video["thumbnail"] as? String).flatMap(URL.init(string:))
            }

            let variants = (video["variants"] as? [[String: Any]]) ?? []
            if !variants.isEmpty {
                let mp4s = variants.compactMap { variant -> (Int, URL)? in
                    let contentType = (variant["content_type"] as? String)?.lowercased() ?? ""
                    guard contentType.contains("mp4") || (variant["url"] as? String)?.contains(".mp4") == true,
                          let urlString = variant["url"] as? String,
                          let url = URL(string: urlString) else { return nil }
                    let bitrate = variant["bitrate"] as? Int ?? 0
                    return (bitrate, url)
                }
                .sorted { $0.0 > $1.0 }

                for (bitrate, url) in mp4s.prefix(4) where seen.insert(url.absoluteString).inserted {
                    let quality: Int? = bitrate > 0 ? min(bitrate / 1000, 2160) : nil
                    formats.append(
                        VideoFormat(
                            id: "x-\(index)-\(formats.count)",
                            label: quality.map { "~\($0) kbps" } ?? (formats.isEmpty ? "Best available" : "Option \(formats.count + 1)"),
                            url: url,
                            fileExtension: "mp4",
                            quality: quality,
                            isAudioOnly: false
                        )
                    )
                }
            } else if let urlString = video["url"] as? String,
                      let url = URL(string: urlString),
                      seen.insert(urlString).inserted {
                let isHLS = urlString.lowercased().contains("m3u8")
                formats.append(
                    VideoFormat(
                        id: "x-\(index)",
                        label: formats.isEmpty ? "Best available" : "Option \(formats.count + 1)",
                        url: url,
                        fileExtension: "mp4",
                        quality: nil,
                        isAudioOnly: false,
                        isHLSStream: isHLS
                    )
                )
            }
        }

        guard !formats.isEmpty else { return nil }

        let authorObj = tweet["author"] as? [String: Any]
        let author = (authorObj?["screen_name"] as? String)
            ?? (authorObj?["name"] as? String)
            ?? "X"
        let title = (tweet["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortTitle: String = {
            guard let title, !title.isEmpty else { return "X video" }
            return title.count > 80 ? String(title.prefix(77)) + "…" : title
        }()

        return VideoMetadata(
            title: shortTitle,
            author: author,
            thumbnailURL: thumbnail,
            platform: .twitter,
            sourceURL: sourceURL,
            formats: formats,
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    private static func twitterStatusID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        if let statusIndex = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }),
           statusIndex + 1 < parts.count {
            let id = parts[statusIndex + 1].split(separator: "?").first.map(String.init) ?? parts[statusIndex + 1]
            if id.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
                return id
            }
        }
        // x.com/i/status/ID
        if parts.count >= 2, parts[0] == "i", parts[1] == "status", parts.count >= 3 {
            let id = parts[2]
            if id.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
                return id
            }
        }
        return nil
    }

    // MARK: - Vimeo

    private func extractVimeo(from sourceURL: URL) async throws -> VideoMetadata {
        guard let videoID = Self.vimeoVideoID(from: sourceURL),
              let configURL = URL(string: "https://player.vimeo.com/video/\(videoID)/config") else {
            throw PageExtractionError.network("Couldn’t read that Vimeo link.")
        }

        var request = URLRequest(url: configURL)
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://vimeo.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let metadata = metadataFromVimeoConfig(json, sourceURL: sourceURL) else {
                throw PageExtractionError.noMediaFound
            }
            return metadata
        } catch let error as PageExtractionError {
            throw error
        } catch {
            if let metadata = try? await extractFromHTMLPage(url: sourceURL, platform: .vimeo),
               metadata.formats.contains(where: { !$0.isAudioOnly }) {
                return metadata
            }
            throw PageExtractionError.network(
                "Couldn’t resolve this Vimeo video. It may be private or password-protected."
            )
        }
    }

    private func metadataFromVimeoConfig(_ json: [String: Any], sourceURL: URL) -> VideoMetadata? {
        let video = json["video"] as? [String: Any]
        let request = json["request"] as? [String: Any]
        let files = request?["files"] as? [String: Any]
        let progressive = files?["progressive"] as? [[String: Any]] ?? []

        var formats: [VideoFormat] = []
        var seen = Set<String>()

        let sorted = progressive.sorted {
            ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0)
        }
        for entry in sorted {
            guard let urlString = entry["url"] as? String,
                  let url = URL(string: urlString),
                  seen.insert(urlString).inserted else { continue }
            let height = entry["height"] as? Int
            formats.append(
                VideoFormat(
                    id: "vimeo-\(height ?? formats.count)",
                    label: height.map { "\($0)p" } ?? "Download",
                    url: url,
                    fileExtension: "mp4",
                    quality: height,
                    isAudioOnly: false
                )
            )
            if formats.count >= 4 { break }
        }

        if formats.isEmpty,
           let hls = files?["hls"] as? [String: Any] {
            let hlsURL = (hls["cdns"] as? [String: Any])
                .flatMap { cdns -> URL? in
                    for value in cdns.values {
                        guard let dict = value as? [String: Any],
                              let urlString = dict["url"] as? String ?? dict["avc_url"] as? String,
                              let url = URL(string: urlString) else { continue }
                        return url
                    }
                    return nil
                }
                ?? (hls["url"] as? String).flatMap(URL.init(string:))
            if let hlsURL {
                formats.append(
                    VideoFormat(
                        id: "vimeo-hls",
                        label: "Stream (HLS)",
                        url: hlsURL,
                        fileExtension: "mp4",
                        quality: video?["height"] as? Int,
                        isAudioOnly: false,
                        isHLSStream: true
                    )
                )
            }
        }

        guard !formats.isEmpty else { return nil }

        let title = (video?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = video?["owner"] as? [String: Any]
        let author = owner?["name"] as? String ?? "Vimeo"
        let thumbnail = (video?["thumbs"] as? [String: Any])
            .flatMap { thumbs -> URL? in
                for key in ["1280", "960", "640", "base"] {
                    if let s = thumbs[key] as? String, let u = URL(string: s) { return u }
                }
                return (thumbs.values.first as? String).flatMap(URL.init(string:))
            }

        return VideoMetadata(
            title: (title?.isEmpty == false ? title! : "Vimeo video"),
            author: author,
            thumbnailURL: thumbnail,
            platform: .vimeo,
            sourceURL: sourceURL,
            formats: formats,
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    private static func vimeoVideoID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        // player.vimeo.com/video/ID
        if let videoIndex = parts.firstIndex(of: "video"), videoIndex + 1 < parts.count {
            let id = parts[videoIndex + 1]
            if id.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
                return id
            }
        }
        // vimeo.com/ID
        if let first = parts.first,
           first.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
           first.count >= 5 {
            return first
        }
        // vimeo.com/channels/x/ID or manage/videos/ID
        if let last = parts.last,
           last.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
           last.count >= 5 {
            return last
        }
        return nil
    }

    // MARK: - Dailymotion

    private func extractDailymotion(from sourceURL: URL) async throws -> VideoMetadata {
        guard let videoID = Self.dailymotionVideoID(from: sourceURL),
              let metaURL = URL(string: "https://www.dailymotion.com/player/metadata/video/\(videoID)") else {
            throw PageExtractionError.network("Couldn’t read that Dailymotion link.")
        }

        var request = URLRequest(url: metaURL)
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let metadata = metadataFromDailymotion(json, sourceURL: sourceURL) else {
                throw PageExtractionError.noMediaFound
            }
            return metadata
        } catch let error as PageExtractionError {
            throw error
        } catch {
            throw PageExtractionError.network(
                "Couldn’t resolve this Dailymotion video. It may be private or geo-blocked."
            )
        }
    }

    private func metadataFromDailymotion(_ json: [String: Any], sourceURL: URL) -> VideoMetadata? {
        let qualities = json["qualities"] as? [String: Any] ?? [:]
        var formats: [VideoFormat] = []
        var seen = Set<String>()

        let rankedKeys = qualities.keys.sorted { lhs, rhs in
            (Int(lhs) ?? (lhs == "auto" ? 0 : 1)) > (Int(rhs) ?? (rhs == "auto" ? 0 : 1))
        }

        for key in rankedKeys {
            guard let entries = qualities[key] as? [[String: Any]] else { continue }
            for entry in entries {
                guard let urlString = entry["url"] as? String,
                      let url = URL(string: urlString),
                      seen.insert(urlString).inserted else { continue }
                let type = (entry["type"] as? String)?.lowercased() ?? ""
                let isHLS = type.contains("mpegurl") || urlString.lowercased().contains("m3u8")
                let height = Int(key)
                formats.append(
                    VideoFormat(
                        id: "dm-\(key)-\(formats.count)",
                        label: height.map { "\($0)p" } ?? (key == "auto" ? "Auto" : key),
                        url: url,
                        fileExtension: "mp4",
                        quality: height,
                        isAudioOnly: false,
                        isHLSStream: isHLS
                    )
                )
            }
            if formats.count >= 4 { break }
        }

        guard !formats.isEmpty else { return nil }

        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (json["owner"] as? [String: Any])?["screenname"] as? String
            ?? (json["owner"] as? [String: Any])?["username"] as? String
            ?? "Dailymotion"
        let thumbnail = (json["thumbnails"] as? [String: Any])
            .flatMap { thumbs -> URL? in
                for key in ["1080", "720", "480", "360"] {
                    if let s = thumbs[key] as? String, let u = URL(string: s) { return u }
                }
                return (thumbs.values.first as? String).flatMap(URL.init(string:))
            }
            ?? (json["poster_url"] as? String).flatMap(URL.init(string:))

        // Prefer progressive mp4 over HLS when both exist.
        formats.sort {
            let left = ($0.isHLSStream ? 0 : 1_000_000) + ($0.quality ?? 0)
            let right = ($1.isHLSStream ? 0 : 1_000_000) + ($1.quality ?? 0)
            return left > right
        }

        return VideoMetadata(
            title: (title?.isEmpty == false ? title! : "Dailymotion video"),
            author: author,
            thumbnailURL: thumbnail,
            platform: .dailymotion,
            sourceURL: sourceURL,
            formats: Array(formats.prefix(4)),
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    private static func dailymotionVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let parts = url.path.split(separator: "/").map(String.init)

        if host.contains("dai.ly"), let first = parts.first, !first.isEmpty {
            return first
        }
        if let videoIndex = parts.firstIndex(where: { $0 == "video" || $0 == "embed" }),
           videoIndex + 1 < parts.count {
            return parts[videoIndex + 1].split(separator: "?").first.map(String.init)
        }
        return nil
    }

    // MARK: - Reddit

    private func extractReddit(from sourceURL: URL) async throws -> VideoMetadata {
        let jsonURL = Self.redditJSONURL(from: sourceURL)

        var request = URLRequest(url: jsonURL)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("VidoX/1.0 (video library; +https://vidox.app)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw PageExtractionError.noMediaFound
            }
            let json = try JSONSerialization.jsonObject(with: data)
            guard let metadata = metadataFromRedditJSON(json, sourceURL: sourceURL) else {
                throw PageExtractionError.noMediaFound
            }
            return metadata
        } catch let error as PageExtractionError {
            throw error
        } catch {
            // v.redd.it direct links sometimes still expose mp4 via HTML / dash.
            if let metadata = try? await extractFromHTMLPage(url: sourceURL, platform: .reddit),
               metadata.formats.contains(where: { !$0.isAudioOnly }) {
                return metadata
            }
            throw PageExtractionError.network(
                "Couldn’t resolve this Reddit video. Try the full post URL (reddit.com/r/…/comments/…)."
            )
        }
    }

    private static func redditJSONURL(from url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        let host = (components.host ?? "www.reddit.com").replacingOccurrences(of: "old.", with: "")
        if host.contains("redd.it") && !host.contains("reddit.com") {
            // Short links: keep as-is and append .json after redirect target isn't known —
            // use www.reddit.com path if we only have an id-like path.
            if let id = url.path.split(separator: "/").first {
                return URL(string: "https://www.reddit.com/comments/\(id).json")!
            }
        }

        components.host = host.contains("reddit.com") ? "www.reddit.com" : host
        components.scheme = "https"
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix(".json") {
            path += ".json"
        }
        components.path = path
        components.queryItems = [URLQueryItem(name: "raw_json", value: "1")]
        return components.url ?? url
    }

    private func metadataFromRedditJSON(_ json: Any, sourceURL: URL) -> VideoMetadata? {
        // Comment pages return [postListing, commentsListing]; single listings return one object.
        let listings: [[String: Any]]
        if let array = json as? [[String: Any]] {
            listings = array
        } else if let object = json as? [String: Any] {
            listings = [object]
        } else {
            return nil
        }

        for listing in listings {
            guard let children = (listing["data"] as? [String: Any])?["children"] as? [[String: Any]] else {
                continue
            }
            for child in children {
                guard let post = child["data"] as? [String: Any],
                      let metadata = metadataFromRedditPost(post, sourceURL: sourceURL) else {
                    continue
                }
                return metadata
            }
        }
        return nil
    }

    private func metadataFromRedditPost(_ post: [String: Any], sourceURL: URL) -> VideoMetadata? {
        let media = (post["secure_media"] as? [String: Any])
            ?? (post["media"] as? [String: Any])
            ?? [:]
        let redditVideo = media["reddit_video"] as? [String: Any]
        let cross = post["crosspost_parent_list"] as? [[String: Any]]
        let crossVideo = (cross?.first?["secure_media"] as? [String: Any])?["reddit_video"] as? [String: Any]
            ?? (cross?.first?["media"] as? [String: Any])?["reddit_video"] as? [String: Any]

        let video = redditVideo ?? crossVideo
        var formats: [VideoFormat] = []

        if let fallback = video?["fallback_url"] as? String, let url = URL(string: fallback) {
            formats.append(
                VideoFormat(
                    id: "reddit-progressive",
                    label: "Best available",
                    url: url,
                    fileExtension: "mp4",
                    quality: video?["height"] as? Int,
                    isAudioOnly: false
                )
            )
        }
        if let hls = video?["hls_url"] as? String, let url = URL(string: hls) {
            formats.append(
                VideoFormat(
                    id: "reddit-hls",
                    label: "Stream (HLS)",
                    url: url,
                    fileExtension: "mp4",
                    quality: video?["height"] as? Int,
                    isAudioOnly: false,
                    isHLSStream: true
                )
            )
        }
        if let dash = video?["dash_url"] as? String, let url = URL(string: dash), formats.isEmpty {
            formats.append(
                VideoFormat(
                    id: "reddit-dash",
                    label: "Stream (DASH)",
                    url: url,
                    fileExtension: "mp4",
                    quality: video?["height"] as? Int,
                    isAudioOnly: false,
                    isHLSStream: true
                )
            )
        }

        // Direct gifv / external mp4 hosted by Reddit or imgur-style.
        if formats.isEmpty, let urlString = post["url_overridden_by_dest"] as? String ?? post["url"] as? String,
           let url = URL(string: urlString),
           DirectMediaExtractor.looksLikeDirectMediaURL(url) || urlString.lowercased().contains(".gifv") {
            var mediaURL = url
            if url.pathExtension.lowercased() == "gifv" {
                mediaURL = url.deletingPathExtension().appendingPathExtension("mp4")
            }
            formats.append(
                VideoFormat(
                    id: "reddit-direct",
                    label: "Best available",
                    url: mediaURL,
                    fileExtension: "mp4",
                    quality: nil,
                    isAudioOnly: false
                )
            )
        }

        guard !formats.isEmpty else { return nil }

        let title = (post["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = post["author"] as? String ?? "Reddit"
        let thumbnail: URL? = {
            let images = (post["preview"] as? [String: Any])?["images"] as? [[String: Any]]
            let source = images?.first?["source"] as? [String: Any]
            guard let raw = source?["url"] as? String else { return nil }
            return URL(string: raw.replacingOccurrences(of: "&amp;", with: "&"))
        }()

        return VideoMetadata(
            title: (title?.isEmpty == false ? title! : "Reddit video"),
            author: author.hasPrefix("u/") ? author : "u/\(author)",
            thumbnailURL: thumbnail,
            platform: .reddit,
            sourceURL: sourceURL,
            formats: formats,
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    // MARK: - Twitch (clips + VODs best-effort)

    private func extractTwitch(from sourceURL: URL) async throws -> VideoMetadata {
        if let slug = Self.twitchClipSlug(from: sourceURL) {
            if let metadata = await extractTwitchClip(slug: slug, sourceURL: sourceURL) {
                return metadata
            }
        }

        if let metadata = try? await extractFromHTMLPage(url: sourceURL, platform: .twitch),
           metadata.formats.contains(where: { !$0.isAudioOnly }) {
            return metadata
        }

        throw PageExtractionError.network(
            "Couldn’t resolve this Twitch media. Clips work best — VODs may need Mac (yt-dlp)."
        )
    }

    private func extractTwitchClip(slug: String, sourceURL: URL) async -> VideoMetadata? {
        // Official-ish clip status endpoint.
        if let statusURL = URL(string: "https://clips.twitch.tv/api/v2/clips/\(slug)/status") {
            var request = URLRequest(url: statusURL)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let options = json["quality_options"] as? [[String: Any]] {
                var formats: [VideoFormat] = []
                var seen = Set<String>()
                let sorted = options.sorted {
                    (Int($0["quality"] as? String ?? "") ?? 0) > (Int($1["quality"] as? String ?? "") ?? 0)
                }
                for entry in sorted {
                    guard let urlString = entry["source"] as? String,
                          let url = URL(string: urlString),
                          seen.insert(urlString).inserted else { continue }
                    let quality = Int(entry["quality"] as? String ?? "")
                    formats.append(
                        VideoFormat(
                            id: "twitch-\(quality ?? formats.count)",
                            label: quality.map { "\($0)p" } ?? "Download",
                            url: url,
                            fileExtension: "mp4",
                            quality: quality,
                            isAudioOnly: false
                        )
                    )
                    if formats.count >= 4 { break }
                }
                if !formats.isEmpty {
                    return VideoMetadata(
                        title: "Twitch clip",
                        author: "Twitch",
                        thumbnailURL: nil,
                        platform: .twitch,
                        sourceURL: sourceURL,
                        formats: formats,
                        allowsRealDownload: true,
                        usesYTDLP: false
                    )
                }
            }
        }

        // GQL fallback for clip access token + URL.
        return await extractTwitchClipViaGQL(slug: slug, sourceURL: sourceURL)
    }

    private func extractTwitchClipViaGQL(slug: String, sourceURL: URL) async -> VideoMetadata? {
        guard let endpoint = URL(string: "https://gql.twitch.tv/gql") else { return nil }
        let body: [[String: Any]] = [[
            "operationName": "VideoAccessToken_Clip",
            "variables": ["slug": slug],
            "extensions": [
                "persistedQuery": [
                    "version": 1,
                    "sha256Hash": "36b89d2507fce29e5ca84ee7110745d554561589c371bf684938d7a2c6a648c7"
                ]
            ]
        ]]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.httpBody = httpBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("kimne78kx3ncx6brgo4mv6wki5h1ko", forHTTPHeaderField: "Client-ID")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let clip = ((array.first?["data"] as? [String: Any])?["clip"] as? [String: Any]) else {
                return nil
            }

            let title = (clip["title"] as? String) ?? "Twitch clip"
            let broadcaster = (clip["broadcaster"] as? [String: Any])?["displayName"] as? String
                ?? (clip["broadcaster"] as? [String: Any])?["login"] as? String
            let thumbnail = (clip["thumbnailURL"] as? String).flatMap(URL.init(string:))
                ?? (clip["posterURL"] as? String).flatMap(URL.init(string:))

            var formats: [VideoFormat] = []
            let qualities = clip["videoQualities"] as? [[String: Any]] ?? []
            let token = (clip["playbackAccessToken"] as? [String: Any])?["value"] as? String
            let sig = (clip["playbackAccessToken"] as? [String: Any])?["signature"] as? String

            for (index, quality) in qualities.enumerated() {
                guard var urlString = quality["sourceURL"] as? String else { continue }
                if let token, let sig {
                    let sep = urlString.contains("?") ? "&" : "?"
                    urlString += "\(sep)sig=\(sig)&token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)"
                }
                guard let url = URL(string: urlString) else { continue }
                let height = Int(quality["quality"] as? String ?? "")
                formats.append(
                    VideoFormat(
                        id: "twitch-gql-\(index)",
                        label: height.map { "\($0)p" } ?? "Download",
                        url: url,
                        fileExtension: "mp4",
                        quality: height,
                        isAudioOnly: false
                    )
                )
            }

            guard !formats.isEmpty else { return nil }
            formats.sort { ($0.quality ?? 0) > ($1.quality ?? 0) }

            return VideoMetadata(
                title: title,
                author: broadcaster ?? "Twitch",
                thumbnailURL: thumbnail,
                platform: .twitch,
                sourceURL: sourceURL,
                formats: Array(formats.prefix(4)),
                allowsRealDownload: true,
                usesYTDLP: false
            )
        } catch {
            return nil
        }
    }

    private static func twitchClipSlug(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let parts = url.path.split(separator: "/").map(String.init)
        if host.contains("clips.twitch.tv"), let first = parts.first, !first.isEmpty, first != "embed" {
            return first.split(separator: "?").first.map(String.init)
        }
        if let clipIndex = parts.firstIndex(of: "clip"), clipIndex + 1 < parts.count {
            return parts[clipIndex + 1].split(separator: "?").first.map(String.init)
        }
        return nil
    }

    // MARK: - Streamable

    private func extractStreamable(from sourceURL: URL) async throws -> VideoMetadata {
        guard let shortcode = Self.streamableShortcode(from: sourceURL),
              let apiURL = URL(string: "https://api.streamable.com/videos/\(shortcode)") else {
            throw PageExtractionError.network("Couldn’t read that Streamable link.")
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let metadata = metadataFromStreamable(json, sourceURL: sourceURL) else {
                throw PageExtractionError.noMediaFound
            }
            return metadata
        } catch let error as PageExtractionError {
            throw error
        } catch {
            if let metadata = try? await extractFromHTMLPage(url: sourceURL, platform: .streamable),
               metadata.formats.contains(where: { !$0.isAudioOnly }) {
                return metadata
            }
            throw PageExtractionError.network("Couldn’t resolve this Streamable video.")
        }
    }

    private func metadataFromStreamable(_ json: [String: Any], sourceURL: URL) -> VideoMetadata? {
        let files = json["files"] as? [String: Any] ?? [:]
        var formats: [VideoFormat] = []

        let preferred = ["mp4", "mp4-mobile", "original"]
        var seen = Set<String>()
        for key in preferred + files.keys.filter({ !preferred.contains($0) }) {
            guard let entry = files[key] as? [String: Any],
                  let urlString = entry["url"] as? String else { continue }
            let absolute: String
            if urlString.hasPrefix("//") {
                absolute = "https:\(urlString)"
            } else {
                absolute = urlString
            }
            guard let url = URL(string: absolute), seen.insert(absolute).inserted else { continue }
            let height = entry["height"] as? Int
            formats.append(
                VideoFormat(
                    id: "streamable-\(key)",
                    label: height.map { "\($0)p" } ?? (key == "mp4" ? "Best available" : key),
                    url: url,
                    fileExtension: "mp4",
                    quality: height,
                    isAudioOnly: false
                )
            )
        }

        guard !formats.isEmpty else { return nil }

        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let thumbnail = (json["thumbnail_url"] as? String).flatMap { raw -> URL? in
            let absolute = raw.hasPrefix("//") ? "https:\(raw)" : raw
            return URL(string: absolute)
        }

        return VideoMetadata(
            title: (title?.isEmpty == false ? title! : "Streamable video"),
            author: "Streamable",
            thumbnailURL: thumbnail,
            platform: .streamable,
            sourceURL: sourceURL,
            formats: formats,
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    private static func streamableShortcode(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        // streamable.com/abc12 or /e/abc12
        if let eIndex = parts.firstIndex(of: "e"), eIndex + 1 < parts.count {
            return parts[eIndex + 1]
        }
        guard let first = parts.first, !first.isEmpty,
              first != "o", first != "s" else {
            return parts.dropFirst().first
        }
        let allowed = CharacterSet.alphanumerics
        guard first.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return first
    }

    // MARK: - Rumble

    private func extractRumble(from sourceURL: URL) async throws -> VideoMetadata {
        if let metadata = await extractRumbleFromPage(sourceURL: sourceURL) {
            return metadata
        }
        if let embedID = Self.rumbleEmbedID(from: sourceURL),
           let metadata = await extractRumbleEmbedJS(embedID: embedID, sourceURL: sourceURL) {
            return metadata
        }
        throw PageExtractionError.network(
            "Couldn’t resolve this Rumble video. It may be live-only or unavailable in your region."
        )
    }

    private func extractRumbleFromPage(sourceURL: URL) async -> VideoMetadata? {
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Prefer embed id → embedJS for clean mp4 map.
            if let embedID = Self.firstMatch(html, pattern: #"rumble\.com/embed/([A-Za-z0-9_-]+)"#)
                ?? Self.firstMatch(html, pattern: #""video"\s*:\s*"(v[A-Za-z0-9]+)""#)
                ?? Self.rumbleEmbedID(from: sourceURL),
               let metadata = await extractRumbleEmbedJS(embedID: embedID, sourceURL: sourceURL) {
                return metadata
            }

            // Fallback: scrape mp4 urls from page JSON blobs.
            let media = Self.inlineMP4URLs(in: html).filter {
                let host = $0.host?.lowercased() ?? ""
                return host.contains("rumble") || host.contains("rmbl.ws") || host.contains("cdn")
            }
            guard !media.isEmpty else { return nil }

            let title = Self.metaContent(html, property: "og:title")
                ?? Self.tagContent(html, tag: "title")
                ?? "Rumble video"
            let thumbnail = Self.metaContent(html, property: "og:image").flatMap(URL.init(string:))
            let formats = media.prefix(4).enumerated().map { index, url in
                VideoFormat(
                    id: "rumble-page-\(index)",
                    label: index == 0 ? "Best available" : "Option \(index + 1)",
                    url: url,
                    fileExtension: "mp4",
                    quality: nil,
                    isAudioOnly: false
                )
            }
            return VideoMetadata(
                title: title.htmlDecoded,
                author: "Rumble",
                thumbnailURL: thumbnail,
                platform: .rumble,
                sourceURL: sourceURL,
                formats: Array(formats),
                allowsRealDownload: true,
                usesYTDLP: false
            )
        } catch {
            return nil
        }
    }

    private func extractRumbleEmbedJS(embedID: String, sourceURL: URL) async -> VideoMetadata? {
        let cleaned = embedID.replacingOccurrences(of: "/", with: "")
        guard let apiURL = URL(string: "https://rumble.com/embedJS/u3/?request=video&ver=2&v=\(cleaned)") else {
            return nil
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://rumble.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return metadataFromRumbleEmbed(json, sourceURL: sourceURL)
        } catch {
            return nil
        }
    }

    private func metadataFromRumbleEmbed(_ json: [String: Any], sourceURL: URL) -> VideoMetadata? {
        // ua.mp4.{height: url} or u.mp4 / ua.webm
        let ua = json["ua"] as? [String: Any]
        let mp4Map = (ua?["mp4"] as? [String: Any]) ?? (json["u"] as? [String: Any])?["mp4"] as? [String: Any]
        var formats: [VideoFormat] = []

        if let mp4Map {
            let ranked = mp4Map.keys.compactMap { key -> (Int, String, String)? in
                guard let value = mp4Map[key] else { return nil }
                let urlString: String?
                if let s = value as? String {
                    urlString = s
                } else if let dict = value as? [String: Any] {
                    urlString = dict["url"] as? String
                } else {
                    urlString = nil
                }
                guard let urlString else { return nil }
                return (Int(key) ?? 0, key, urlString)
            }
            .sorted { $0.0 > $1.0 }

            for (height, key, urlString) in ranked {
                guard let url = URL(string: urlString) else { continue }
                formats.append(
                    VideoFormat(
                        id: "rumble-\(key)",
                        label: height > 0 ? "\(height)p" : key,
                        url: url,
                        fileExtension: "mp4",
                        quality: height > 0 ? height : nil,
                        isAudioOnly: false
                    )
                )
                if formats.count >= 4 { break }
            }
        }

        if formats.isEmpty,
           let hls = (ua?["hls"] as? [String: Any])?["auto"] as? [String: Any]
                ?? ua?["hls"] as? [String: Any],
           let urlString = hls["url"] as? String ?? (hls.values.first as? [String: Any])?["url"] as? String,
           let url = URL(string: urlString) {
            formats.append(
                VideoFormat(
                    id: "rumble-hls",
                    label: "Stream (HLS)",
                    url: url,
                    fileExtension: "mp4",
                    quality: nil,
                    isAudioOnly: false,
                    isHLSStream: true
                )
            )
        }

        guard !formats.isEmpty else { return nil }

        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (json["author"] as? [String: Any])?["name"] as? String
            ?? (json["channel"] as? [String: Any])?["name"] as? String
            ?? "Rumble"
        let thumbnail = (json["i"] as? String).flatMap(URL.init(string:))
            ?? (json["thumbnail"] as? String).flatMap(URL.init(string:))

        return VideoMetadata(
            title: (title?.isEmpty == false ? title! : "Rumble video"),
            author: author,
            thumbnailURL: thumbnail,
            platform: .rumble,
            sourceURL: sourceURL,
            formats: formats,
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    private static func rumbleEmbedID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        if let embedIndex = parts.firstIndex(of: "embed"), embedIndex + 1 < parts.count {
            return parts[embedIndex + 1]
        }
        // Paths like /vXXXXX-title.html sometimes expose v-id in query `v`
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        return nil
    }

    // MARK: - Shared private helpers used by this extension

    fileprivate static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
