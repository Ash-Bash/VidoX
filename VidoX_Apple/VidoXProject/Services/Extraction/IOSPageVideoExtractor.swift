import Foundation

enum PageExtractionError: LocalizedError, Sendable {
    case unsupported
    case noMediaFound
    case network(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "This link isn’t supported for download on iPhone / iPad yet."
        case .noMediaFound:
            "Couldn’t find a downloadable video on that page. Try another link or a direct .mp4 URL."
        case .network(let message):
            message
        case .invalidResponse:
            "The site returned data VidoX couldn’t read."
        }
    }
}

/// iOS / visionOS page extractor — resolves real media URLs without a macOS yt-dlp binary.
/// `nonisolated` so lookups never block the main-thread UI (“Preparing downloader…”).
nonisolated struct IOSPageVideoExtractor: VideoExtracting {
    /// Short-lived session so YouTube lookups fail fast instead of waiting on shared/system defaults.
    private static let fastSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    nonisolated func extract(from url: URL) async throws -> VideoMetadata {
        let detected = VideoPlatform.detect(from: url.absoluteString)
        let platform: VideoPlatform = detected == .unknown ? .web : detected

        if platform == .youtube, let videoID = Self.youtubeVideoID(from: url) {
            return try await extractYouTube(videoID: videoID, sourceURL: url)
        }

        if platform == .instagram {
            return try await extractInstagram(from: url)
        }

        if platform == .facebook {
            return try await extractFacebook(from: url)
        }

        if platform == .tiktok {
            return try await extractTikTok(from: url)
        }

        if let metadata = try await extractKnownPlatform(from: url, platform: platform) {
            return metadata
        }

        if let metadata = try await extractFromHTMLPage(url: url, platform: platform) {
            return metadata
        }

        throw PageExtractionError.noMediaFound
    }

    // MARK: - Facebook

    private func extractFacebook(from sourceURL: URL) async throws -> VideoMetadata {
        let resolvedURL = await resolveFacebookURL(sourceURL)

        // Race the strategies that still work for public videos (Facebook itself is usually login-walled).
        if let metadata = await raceFacebookExtractors(pageURL: resolvedURL, sourceURL: sourceURL) {
            return metadata
        }

        throw PageExtractionError.network(
            "Couldn’t resolve this Facebook video. Public watch/reel links work best — private, friends-only, or expired share links can’t be opened. Try again, or download it on Mac."
        )
    }

    private func raceFacebookExtractors(pageURL: URL, sourceURL: URL) async -> VideoMetadata? {
        await withTaskGroup(of: VideoMetadata?.self) { group in
            group.addTask {
                await self.extractFacebookViaGetMyFB(pageURL: pageURL, sourceURL: sourceURL)
            }
            group.addTask {
                await self.extractFacebookViaSnapSave(pageURL: pageURL, sourceURL: sourceURL)
            }
            group.addTask {
                try? await self.extractFacebookFromWebpage(pageURL: pageURL, sourceURL: sourceURL)
            }

            // Also try the numeric watch URL when we already know the id.
            if let videoID = URLNormalizer.facebookVideoID(from: pageURL)
                ?? URLNormalizer.facebookVideoID(from: sourceURL),
               let watchURL = URL(string: "https://www.facebook.com/watch/?v=\(videoID)"),
               watchURL.absoluteString != pageURL.absoluteString {
                group.addTask {
                    await self.extractFacebookViaGetMyFB(pageURL: watchURL, sourceURL: sourceURL)
                }
                group.addTask {
                    try? await self.extractFacebookFromWebpage(pageURL: watchURL, sourceURL: sourceURL)
                }
            }

            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private func resolveFacebookURL(_ url: URL) async -> URL {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let needsResolve = host.contains("fb.watch")
            || host == "fb.me"
            || path.contains("/share/")
            || path.contains("/flx/warn")

        guard needsResolve else { return url }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let finalURL = response.url ?? url
            if let videoID = URLNormalizer.facebookVideoID(from: finalURL),
               let watchURL = URL(string: "https://www.facebook.com/watch/?v=\(videoID)") {
                return watchURL
            }
            return finalURL
        } catch {
            return url
        }
    }

    private func extractFacebookViaGetMyFB(pageURL: URL, sourceURL: URL) async -> VideoMetadata? {
        guard let endpoint = URL(string: "https://getmyfb.com/process") else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 22
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://getmyfb.com", forHTTPHeaderField: "Origin")
        request.setValue("https://getmyfb.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "id", value: pageURL.absoluteString),
            URLQueryItem(name: "locale", value: "en_US")
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            return metadataFromGetMyFBHTML(html, sourceURL: sourceURL)
        } catch {
            return nil
        }
    }

    private func metadataFromGetMyFBHTML(_ html: String, sourceURL: URL) -> VideoMetadata? {
        var formats: [VideoFormat] = []
        var seen = Set<String>()

        // Prefer labeled rows: "720p(HD)" / "360p(SD)" with proxy download hrefs.
        let labeled = #"(\d{3,4}p\s*\((?:HD|SD)\)|\d{3,4}p|HD|SD)\s*<a[^>]+href=["'](https://ssscdn\.io/getmyfb/[^"']+)["']"#
        if let regex = try? NSRegularExpression(
            pattern: labeled,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let range = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 2,
                      let labelRange = Range(match.range(at: 1), in: html),
                      let urlRange = Range(match.range(at: 2), in: html),
                      let mediaURL = URL(string: String(html[urlRange])),
                      seen.insert(mediaURL.absoluteString).inserted else { return }
                let label = String(html[labelRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let quality = Self.qualityHint(from: label)
                formats.append(
                    VideoFormat(
                        id: "fb-getmyfb-\(formats.count)",
                        label: label.contains("p") || label.uppercased().contains("HD") || label.uppercased().contains("SD")
                            ? label
                            : (quality.map { "\($0)p" } ?? "Download"),
                        url: mediaURL,
                        fileExtension: "mp4",
                        quality: quality,
                        isAudioOnly: false
                    )
                )
            }
        }

        if formats.isEmpty {
            let loose = #"href=["'](https://ssscdn\.io/getmyfb/[^"']+)["']"#
            if let regex = try? NSRegularExpression(pattern: loose, options: [.caseInsensitive]) {
                let range = NSRange(html.startIndex..., in: html)
                regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                    guard let match, match.numberOfRanges > 1,
                          let urlRange = Range(match.range(at: 1), in: html),
                          let mediaURL = URL(string: String(html[urlRange])),
                          seen.insert(mediaURL.absoluteString).inserted else { return }
                    formats.append(
                        VideoFormat(
                            id: "fb-getmyfb-\(formats.count)",
                            label: formats.isEmpty ? "Best available" : "Option \(formats.count + 1)",
                            url: mediaURL,
                            fileExtension: "mp4",
                            quality: formats.isEmpty ? 720 : 360,
                            isAudioOnly: false
                        )
                    )
                }
            }
        }

        guard !formats.isEmpty else { return nil }

        formats.sort { ($0.quality ?? 0) > ($1.quality ?? 0) }

        let title = Self.firstMatch(html, pattern: #"class="results-item-text">\s*([^<]+)"#)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).htmlDecoded }
        let thumbnail = Self.firstMatch(html, pattern: #"class="results-item-image"[^>]*src="([^"]+)""#)
            .flatMap(URL.init(string:))

        return VideoMetadata(
            title: (title?.isEmpty == false ? title! : "Facebook video"),
            author: "Facebook",
            thumbnailURL: thumbnail,
            platform: .facebook,
            sourceURL: sourceURL,
            formats: Array(formats.prefix(4)),
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    private func extractFacebookViaSnapSave(pageURL: URL, sourceURL: URL) async -> VideoMetadata? {
        guard let endpoint = URL(string: "https://snapsave.app/action.php") else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 22
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://snapsave.app", forHTTPHeaderField: "Origin")
        request.setValue("https://snapsave.app/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        var body = URLComponents()
        body.queryItems = [URLQueryItem(name: "url", value: pageURL.absoluteString)]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let script = String(data: data, encoding: .utf8),
                  let decoded = Self.decodeSnapSavePayload(script) else {
                return nil
            }
            return metadataFromSnapSaveHTML(decoded, sourceURL: sourceURL)
        } catch {
            return nil
        }
    }

    private func metadataFromSnapSaveHTML(_ html: String, sourceURL: URL) -> VideoMetadata? {
        var formats: [VideoFormat] = []
        var seen = Set<String>()

        let patterns = [
            #"<td[^>]*class="[^"]*video-quality[^"]*"[^>]*>\s*([^<]+?)\s*</td>\s*<td[^>]*>.*?<a[^>]+href=["'](https://[^"']+)["']"#,
            #"href=["'](https://d\.rapidcdn\.app/[^"']+)["']"#
        ]

        if let regex = try? NSRegularExpression(
            pattern: patterns[0],
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let range = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 2,
                      let labelRange = Range(match.range(at: 1), in: html),
                      let urlRange = Range(match.range(at: 2), in: html) else { return }
                let label = String(html[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let raw = String(html[urlRange]).htmlDecoded
                guard let mediaURL = URL(string: raw),
                      seen.insert(mediaURL.absoluteString).inserted else { return }
                let lower = label.lowercased()
                guard !lower.contains("audio") else { return }
                formats.append(
                    VideoFormat(
                        id: "fb-snapsave-\(formats.count)",
                        label: label.isEmpty ? "Download" : label,
                        url: mediaURL,
                        fileExtension: "mp4",
                        quality: Self.qualityHint(from: label),
                        isAudioOnly: false
                    )
                )
            }
        }

        if formats.isEmpty, let regex = try? NSRegularExpression(pattern: patterns[1], options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let urlRange = Range(match.range(at: 1), in: html),
                      let mediaURL = URL(string: String(html[urlRange])),
                      seen.insert(mediaURL.absoluteString).inserted else { return }
                // Skip pure thumbnail endpoints.
                if mediaURL.path.contains("/thumb") { return }
                formats.append(
                    VideoFormat(
                        id: "fb-snapsave-\(formats.count)",
                        label: formats.isEmpty ? "Best available" : "Option \(formats.count + 1)",
                        url: mediaURL,
                        fileExtension: "mp4",
                        quality: formats.isEmpty ? 720 : nil,
                        isAudioOnly: false
                    )
                )
            }
        }

        guard !formats.isEmpty else { return nil }

        let title = Self.firstMatch(html, pattern: #"alt=["']([^"']+)["']"#)
            ?? Self.metaContent(html, property: "og:title")
            ?? "Facebook video"
        let thumbnail = Self.firstMatch(html, pattern: #"src=["'](https://d\.rapidcdn\.app/thumb[^"']+)["']"#)
            .flatMap(URL.init(string:))
            ?? Self.metaContent(html, property: "og:image").flatMap(URL.init(string:))

        return VideoMetadata(
            title: title.htmlDecoded,
            author: "Facebook",
            thumbnailURL: thumbnail,
            platform: .facebook,
            sourceURL: sourceURL,
            formats: Array(formats.prefix(4)),
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    /// Decode snapsave’s packed `eval(function(h,u,n,t,e,r){...})` response into HTML.
    private static func decodeSnapSavePayload(_ script: String) -> String? {
        guard let match = script.range(
            of: #"\}\("([^"]+)",(\d+),"([^"]+)",(\d+),(\d+),(\d+)\)\)"#,
            options: .regularExpression
        ) else { return nil }

        let snippet = String(script[match])
        guard let inner = snippet.range(of: #"\("([^"]+)",(\d+),"([^"]+)",(\d+),(\d+),(\d+)\)"#, options: .regularExpression) else {
            return nil
        }
        let args = String(snippet[inner])
        // Capture packed-script arguments without splitting on commas inside the payload.
        let capture = #"\("([^"]+)",(\d+),"([^"]+)",(\d+),(\d+),(\d+)\)"#
        guard let regex = try? NSRegularExpression(pattern: capture),
              let m = regex.firstMatch(in: args, range: NSRange(args.startIndex..., in: args)),
              m.numberOfRanges == 7,
              let hRange = Range(m.range(at: 1), in: args),
              let nRange = Range(m.range(at: 3), in: args),
              let tRange = Range(m.range(at: 4), in: args),
              let eRange = Range(m.range(at: 5), in: args),
              let t = Int(args[tRange]),
              let e = Int(args[eRange]) else {
            return nil
        }

        let h = String(args[hRange])
        let n = String(args[nRange])
        guard e >= 0, e < n.count else { return nil }

        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/")
        func intPower(_ base: Int, _ exp: Int) -> Int {
            var result = 1
            var count = 0
            while count < exp {
                result *= base
                count += 1
            }
            return result
        }
        func decodeToken(_ d: String, _ fromBase: Int, _ toBase: Int) -> String {
            let source = Array(alphabet.prefix(fromBase))
            let dest = Array(alphabet.prefix(toBase))
            var value = 0
            for (index, char) in d.reversed().enumerated() {
                if let digit = source.firstIndex(of: char) {
                    value += digit * intPower(fromBase, index)
                }
            }
            if value == 0 { return "0" }
            var out = ""
            var remaining = value
            while remaining > 0 {
                out = String(dest[remaining % toBase]) + out
                remaining /= toBase
            }
            return out
        }

        let delimiter = n[n.index(n.startIndex, offsetBy: e)]
        var output = ""
        var index = h.startIndex
        while index < h.endIndex {
            var token = ""
            while index < h.endIndex, h[index] != delimiter {
                token.append(h[index])
                index = h.index(after: index)
            }
            if index < h.endIndex {
                index = h.index(after: index)
            }
            for (position, character) in n.enumerated() {
                token = token.replacingOccurrences(of: String(character), with: String(position))
            }
            guard let code = Int(decodeToken(token, e, 10)) else { continue }
            let scalar = code - t
            guard scalar >= 0, let unicode = UnicodeScalar(scalar) else { continue }
            output.append(Character(unicode))
        }

        // snapsave builds percent-encoded UTF-8 then escapes it.
        if let decoded = output.removingPercentEncoding {
            return decoded
        }
        return output
    }

    private func extractFacebookFromWebpage(pageURL: URL, sourceURL: URL) async throws -> VideoMetadata? {
        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("locale=en_US", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        let media = Self.facebookMediaURLs(fromHTML: html)
        guard !media.isEmpty else { return nil }

        let title = Self.metaContent(html, property: "og:title")
            ?? Self.tagContent(html, tag: "title")
            ?? "Facebook video"
        let author = Self.metaContent(html, property: "og:site_name") ?? "Facebook"
        let thumbnail = Self.metaContent(html, property: "og:image").flatMap(URL.init(string:))

        let formats: [VideoFormat] = media.prefix(4).enumerated().map { index, entry in
            VideoFormat(
                id: "fb-page-\(index)",
                label: entry.label,
                url: entry.url,
                fileExtension: "mp4",
                quality: entry.quality,
                isAudioOnly: false,
                isHLSStream: entry.url.absoluteString.lowercased().contains("m3u8")
            )
        }

        return VideoMetadata(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).htmlDecoded,
            author: author,
            thumbnailURL: thumbnail,
            platform: .facebook,
            sourceURL: sourceURL,
            formats: Array(formats),
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    private static func facebookMediaURLs(fromHTML html: String) -> [(url: URL, label: String, quality: Int?)] {
        let keys: [(pattern: String, label: String, quality: Int)] = [
            (#"playable_url_quality_hd"\s*:\s*"([^"]+)""#, "HD", 720),
            (#"browser_native_hd_url"\s*:\s*"([^"]+)""#, "HD", 720),
            (#"hd_src_no_ratelimit"\s*:\s*"([^"]+)""#, "HD", 720),
            (#"hd_src"\s*:\s*"([^"]+)""#, "HD", 720),
            (#"playable_url"\s*:\s*"([^"]+)""#, "SD", 360),
            (#"browser_native_sd_url"\s*:\s*"([^"]+)""#, "SD", 360),
            (#"sd_src_no_ratelimit"\s*:\s*"([^"]+)""#, "SD", 360),
            (#"sd_src"\s*:\s*"([^"]+)""#, "SD", 360),
            (#"progressive_url"\s*:\s*"([^"]+)""#, "Progressive", 480)
        ]

        var results: [(url: URL, label: String, quality: Int?)] = []
        var seen = Set<String>()

        for entry in keys {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, options: [], range: range) { match, _, stop in
                guard let match, match.numberOfRanges > 1,
                      let urlRange = Range(match.range(at: 1), in: html) else { return }
                let cleaned = decodeFacebookURL(String(html[urlRange]))
                guard let mediaURL = URL(string: cleaned),
                      seen.insert(cleaned).inserted else { return }
                let lower = cleaned.lowercased()
                guard lower.contains(".mp4")
                        || lower.contains("m3u8")
                        || lower.contains("fbcdn")
                        || lower.contains("video") else { return }
                results.append((mediaURL, entry.label, entry.quality))
                stop.pointee = true
            }
        }

        return results
    }

    private static func decodeFacebookURL(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0025", with: "%")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u003D", with: "=")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
            .htmlDecoded
    }

    private static func qualityHint(from label: String) -> Int? {
        if let match = label.range(of: #"(\d{3,4})"#, options: .regularExpression) {
            return Int(label[match])
        }
        let upper = label.uppercased()
        if upper.contains("HD") { return 720 }
        if upper.contains("SD") { return 360 }
        return nil
    }

    private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    // MARK: - TikTok

    private func extractTikTok(from sourceURL: URL) async throws -> VideoMetadata {
        let resolvedURL = await resolveTikTokURL(sourceURL)

        // 1) tikwm — returns direct CDN links that usually download without login.
        if let metadata = await extractTikTokViaTikwm(pageURL: resolvedURL, sourceURL: sourceURL) {
            return metadata
        }

        // 2) Parse TikTok’s embedded player JSON when the page isn’t bot-gated.
        if let metadata = try? await extractTikTokFromWebpage(pageURL: resolvedURL, sourceURL: sourceURL) {
            return metadata
        }

        // 3) Community fallback API.
        if let metadata = await extractTikTokViaCommunityAPI(pageURL: resolvedURL, sourceURL: sourceURL) {
            return metadata
        }

        throw PageExtractionError.network(
            "Couldn’t resolve this TikTok video. It may be private, region-locked, or deleted. Try again, or download it on Mac."
        )
    }

    private func resolveTikTokURL(_ url: URL) async -> URL {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("vm.tiktok.com") || host.contains("vt.tiktok.com") else {
            return url
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.7 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response.url ?? url
        } catch {
            return url
        }
    }

    private func extractTikTokViaTikwm(pageURL: URL, sourceURL: URL) async -> VideoMetadata? {
        let bases = ["https://www.tikwm.com/api/", "https://tikwm.com/api/"]

        for base in bases {
            var components = URLComponents(string: base)
            components?.queryItems = [
                URLQueryItem(name: "hd", value: "1"),
                URLQueryItem(name: "url", value: pageURL.absoluteString)
            ]
            guard let apiURL = components?.url else { continue }
            var request = URLRequest(url: apiURL)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("https://www.tikwm.com/", forHTTPHeaderField: "Referer")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (json["code"] as? Int) == 0,
                      let payload = json["data"] as? [String: Any] else {
                    continue
                }
                if let metadata = metadataFromTikwm(payload, sourceURL: sourceURL) {
                    return metadata
                }
            } catch {
                continue
            }
        }

        // POST form as a second chance (some regions prefer it).
        guard let postURL = URL(string: "https://www.tikwm.com/api/") else { return nil }
        var post = URLRequest(url: postURL)
        post.httpMethod = "POST"
        post.timeoutInterval = 20
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.setValue("application/json", forHTTPHeaderField: "Accept")
        post.setValue("https://www.tikwm.com/", forHTTPHeaderField: "Origin")
        post.setValue("https://www.tikwm.com/", forHTTPHeaderField: "Referer")
        post.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "hd", value: "1"),
            URLQueryItem(name: "url", value: pageURL.absoluteString)
        ]
        post.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: post)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["code"] as? Int) == 0,
                  let payload = json["data"] as? [String: Any] else {
                return nil
            }
            return metadataFromTikwm(payload, sourceURL: sourceURL)
        } catch {
            return nil
        }
    }

    private func metadataFromTikwm(_ data: [String: Any], sourceURL: URL) -> VideoMetadata? {
        let title = (data["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorObj = data["author"] as? [String: Any]
        let author = (authorObj?["unique_id"] as? String)
            ?? (authorObj?["nickname"] as? String)
            ?? (data["author"] as? String)
        let thumbnail = (data["cover"] as? String).flatMap(URL.init(string:))
            ?? (data["origin_cover"] as? String).flatMap(URL.init(string:))

        var formats: [VideoFormat] = []
        // Rank by preference, not file size (HD can be smaller than the default encode).
        let candidates: [(String, String, Int)] = [
            ("hdplay", "HD (no watermark)", 1080),
            ("play", "Best (no watermark)", 720),
            ("wmplay", "With watermark", 480)
        ]
        for (key, label, rank) in candidates {
            guard let urlString = data[key] as? String,
                  let mediaURL = URL(string: urlString),
                  !urlString.isEmpty else { continue }
            formats.append(
                VideoFormat(
                    id: "tikwm-\(key)",
                    label: label,
                    url: mediaURL,
                    fileExtension: "mp4",
                    quality: rank,
                    isAudioOnly: false
                )
            )
        }
        if let music = data["music"] as? String, let musicURL = URL(string: music) {
            formats.append(
                VideoFormat(
                    id: "tikwm-music",
                    label: "Audio only",
                    url: musicURL,
                    fileExtension: "mp3",
                    quality: nil,
                    isAudioOnly: true
                )
            )
        }

        guard formats.contains(where: { !$0.isAudioOnly }) else { return nil }

        return VideoMetadata(
            title: (title?.isEmpty == false ? title! : "TikTok video"),
            author: author,
            thumbnailURL: thumbnail,
            platform: .tiktok,
            sourceURL: sourceURL,
            formats: formats,
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    private func extractTikTokFromWebpage(pageURL: URL, sourceURL: URL) async throws -> VideoMetadata? {
        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 25
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        guard let json = Self.tikTokUniversalData(from: html),
              let detail = (json["__DEFAULT_SCOPE__"] as? [String: Any])?["webapp.video-detail"] as? [String: Any]
                ?? (json["__DEFAULT_SCOPE__"] as? [String: Any])?["webapp.reflow.video.detail"] as? [String: Any],
              let itemInfo = detail["itemInfo"] as? [String: Any],
              let item = itemInfo["itemStruct"] as? [String: Any],
              let video = item["video"] as? [String: Any] else {
            return nil
        }

        let title = (item["desc"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (item["author"] as? [String: Any])?["uniqueId"] as? String
            ?? (item["author"] as? [String: Any])?["nickname"] as? String
        let thumbnail = (video["cover"] as? String).flatMap(URL.init(string:))
            ?? (video["originCover"] as? String).flatMap(URL.init(string:))
        let height = video["height"] as? Int

        var formats: [VideoFormat] = []
        var seen = Set<String>()

        // Prefer bitrate ladder when present.
        if let bitrateInfo = video["bitrateInfo"] as? [[String: Any]] {
            for (index, entry) in bitrateInfo.prefix(5).enumerated() {
                let play = (entry["PlayAddr"] as? [String: Any]) ?? (entry["playAddr"] as? [String: Any])
                let urls = (play?["UrlList"] as? [String]) ?? (play?["url_list"] as? [String]) ?? []
                guard let first = urls.first, let mediaURL = URL(string: first), seen.insert(first).inserted else {
                    continue
                }
                let h = (play?["Height"] as? Int) ?? (play?["height"] as? Int) ?? height
                formats.append(
                    VideoFormat(
                        id: "tt-br-\(index)",
                        label: h.map { "\($0)p" } ?? "Video",
                        url: mediaURL,
                        fileExtension: "mp4",
                        quality: h,
                        isAudioOnly: false
                    )
                )
            }
        }

        for (key, label) in [("downloadAddr", "Download"), ("playAddr", "Play")] {
            if let urlString = video[key] as? String,
               let mediaURL = URL(string: urlString),
               seen.insert(urlString).inserted {
                formats.insert(
                    VideoFormat(
                        id: "tt-\(key)",
                        label: label,
                        url: mediaURL,
                        fileExtension: "mp4",
                        quality: height,
                        isAudioOnly: false
                    ),
                    at: 0
                )
            }
        }

        guard formats.contains(where: { !$0.isAudioOnly }) else { return nil }

        return VideoMetadata(
            title: (title?.isEmpty == false ? title! : "TikTok video"),
            author: author,
            thumbnailURL: thumbnail,
            platform: .tiktok,
            sourceURL: sourceURL,
            formats: formats,
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    private static func tikTokUniversalData(from html: String) -> [String: Any]? {
        guard let range = html.range(of: #"id="__UNIVERSAL_DATA_FOR_REHYDRATION__""#),
              let scriptStart = html[range.lowerBound...].range(of: ">"),
              let scriptEnd = html[scriptStart.upperBound...].range(of: "</script>") else {
            return nil
        }
        let jsonText = String(html[scriptStart.upperBound..<scriptEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func extractTikTokViaCommunityAPI(pageURL: URL, sourceURL: URL) async -> VideoMetadata? {
        var components = URLComponents(string: "https://tiktok-downbloder.vercel.app/")
        components?.queryItems = [URLQueryItem(name: "url", value: pageURL.absoluteString)]
        guard let apiURL = components?.url else {
            return nil
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["success"] as? Bool) == true else {
                return nil
            }

            // Nested shape: result.raw.result.{video,music,desc,author}
            let raw = ((root["result"] as? [String: Any])?["raw"] as? [String: Any])
            let result = (raw?["result"] as? [String: Any])
                ?? (root["result"] as? [String: Any])
                ?? [:]

            let videoURLString = (result["video"] as? String)
                ?? (result["play"] as? String)
                ?? (result["hdplay"] as? String)
            guard let videoURLString, let mediaURL = URL(string: videoURLString) else {
                return nil
            }

            let title = (result["desc"] as? String)
                ?? (result["title"] as? String)
                ?? "TikTok video"
            let authorObj = result["author"] as? [String: Any]
            let author = (authorObj?["nickname"] as? String)
                ?? (authorObj?["unique_id"] as? String)
            let thumbnail = (result["cover"] as? String).flatMap(URL.init(string:))
                ?? (authorObj?["avatar"] as? String).flatMap(URL.init(string:))

            var formats = [
                VideoFormat(
                    id: "tt-community-video",
                    label: "Best available",
                    url: mediaURL,
                    fileExtension: "mp4",
                    quality: nil,
                    isAudioOnly: false
                )
            ]
            if let music = result["music"] as? String, let musicURL = URL(string: music) {
                formats.append(
                    VideoFormat(
                        id: "tt-community-music",
                        label: "Audio only",
                        url: musicURL,
                        fileExtension: "mp3",
                        quality: nil,
                        isAudioOnly: true
                    )
                )
            }

            return VideoMetadata(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                author: author,
                thumbnailURL: thumbnail,
                platform: .tiktok,
                sourceURL: sourceURL,
                formats: formats,
                allowsRealDownload: true,
                usesYTDLP: false
            )
        } catch {
            return nil
        }
    }

    // MARK: - Instagram

    private func extractInstagram(from sourceURL: URL) async throws -> VideoMetadata {
        guard let shortcode = Self.instagramShortcode(from: sourceURL) else {
            throw PageExtractionError.network(
                "Couldn’t read that Instagram link. Use a /reel/ or /p/ URL."
            )
        }

        // Public mirrors first — Instagram’s own APIs usually require login / TLS tricks on iOS.
        for mirror in Self.instagramMirrorURLs(shortcode: shortcode) {
            if let metadata = try? await extractInstagramFromMirror(
                mirrorURL: mirror,
                sourceURL: sourceURL,
                shortcode: shortcode
            ) {
                return metadata
            }
        }

        // Best-effort direct page scrape (often login-walled).
        if let metadata = try? await extractFromHTMLPage(url: sourceURL, platform: .instagram),
           metadata.formats.contains(where: { !$0.isAudioOnly }) {
            return metadata
        }

        throw PageExtractionError.network(
            "Couldn’t resolve this Instagram video. It may be private, expired, or login-gated. Try a public reel/post, or download on Mac."
        )
    }

    private static func instagramShortcode(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let kindIndex = parts.firstIndex(where: { ["p", "tv", "reel", "reels"].contains($0) }),
              kindIndex + 1 < parts.count else {
            return nil
        }
        let code = parts[kindIndex + 1]
            .split(separator: "?").first
            .map(String.init) ?? parts[kindIndex + 1]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !code.isEmpty, code.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return code
    }

    private static func instagramMirrorURLs(shortcode: String) -> [URL] {
        [
            "https://imginn.com/p/\(shortcode)/",
            "https://imginn.com/reel/\(shortcode)/",
            "https://www.instagramez.com/p/\(shortcode)",
            "https://www.instagramez.com/reel/\(shortcode)"
        ].compactMap(URL.init(string:))
    }

    private func extractInstagramFromMirror(
        mirrorURL: URL,
        sourceURL: URL,
        shortcode: String
    ) async throws -> VideoMetadata? {
        var request = URLRequest(url: mirrorURL)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.7 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        let mediaURLs = Self.instagramMediaURLs(fromHTML: html)
        guard !mediaURLs.isEmpty else { return nil }

        let ogTitle = Self.metaContent(html, property: "og:title")
            ?? Self.tagContent(html, tag: "title")
            ?? "Instagram video"
        let author = Self.instagramAuthor(from: ogTitle) ?? "Instagram"
        let title = Self.instagramTitle(from: ogTitle, shortcode: shortcode)
        let thumbnail = Self.metaContent(html, property: "og:image").flatMap(URL.init(string:))

        let formats: [VideoFormat] = mediaURLs.prefix(4).enumerated().map { index, media in
            let lower = media.absoluteString.lowercased()
            let isHLS = lower.contains("m3u8")
            return VideoFormat(
                id: "ig-\(shortcode)-\(index)",
                label: index == 0 ? "Best available" : "Option \(index + 1)",
                url: media,
                fileExtension: "mp4",
                quality: nil,
                isAudioOnly: false,
                isHLSStream: isHLS
            )
        }

        return VideoMetadata(
            title: title,
            author: author,
            thumbnailURL: thumbnail,
            platform: .instagram,
            sourceURL: sourceURL,
            formats: Array(formats),
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    private static func instagramMediaURLs(fromHTML html: String) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()

        let patterns = [
            #"<(?:video|source)[^>]+(?:src|data-src)=["'](https://[^"']+)["']"#,
            #"<a[^>]+download[^>]+href=["'](https://[^"']+)["']"#,
            #"<a[^>]+href=["'](https://[^"']+)["'][^>]+download"#,
            #"(https://scontent[^"'<\s]+\.mp4[^"'<\s]*)"#,
            #"(https://[^"'<\s]*cdninstagram\.com[^"'<\s]*\.mp4[^"'<\s]*)"#,
            #"(https://[^"'<\s]*fbcdn\.net[^"'<\s]*\.mp4[^"'<\s]*)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let urlRange = Range(match.range(at: 1), in: html) else { return }
                let raw = String(html[urlRange])
                    .htmlDecoded
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "\\u0026", with: "&")
                    .replacingOccurrences(of: "\\/", with: "/")
                let cleaned = raw.split(separator: "#").first.map(String.init) ?? raw
                guard cleaned.lowercased().contains(".mp4") || cleaned.lowercased().contains("m3u8"),
                      let url = URL(string: cleaned),
                      seen.insert(cleaned).inserted else { return }
                let host = url.host?.lowercased() ?? ""
                guard host.contains("cdninstagram")
                        || host.contains("fbcdn")
                        || host.contains("scontent") else { return }
                found.append(url)
            }
        }

        return found
    }

    private static func instagramAuthor(from ogTitle: String) -> String? {
        if let at = ogTitle.range(of: #"@([A-Za-z0-9._]+)"#, options: .regularExpression) {
            return String(ogTitle[at].dropFirst())
        }
        if let by = ogTitle.range(
            of: #"Video by\s+([A-Za-z0-9._]+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            return String(ogTitle[by]).split(separator: " ").last.map(String.init)
        }
        return nil
    }

    private static func instagramTitle(from ogTitle: String, shortcode: String) -> String {
        var title = ogTitle
        if let range = title.range(of: #"^[^:]+:\s*"#, options: .regularExpression) {
            title = String(title[range.upperBound...])
        }
        title = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "“”\"'"))
        if title.isEmpty || title.count < 2 {
            return "Instagram \(shortcode)"
        }
        if title.count > 80 {
            return String(title.prefix(77)) + "…"
        }
        return title
    }

    // MARK: - YouTube

    private func extractYouTube(videoID: String, sourceURL: URL) async throws -> VideoMetadata {
        // Race ANDROID + IOS Innertube — take the first usable result (usually < 2s).
        if let metadata = await raceYouTubeInnertube(videoID: videoID, sourceURL: sourceURL) {
            return metadata
        }

        // Single short Piped attempt only.
        if let metadata = await extractYouTubeViaPiped(videoID: videoID, sourceURL: sourceURL) {
            return metadata
        }

        throw PageExtractionError.network(
            "Couldn’t resolve this YouTube video quickly. Try again, or download it on Mac."
        )
    }

    /// Runs ANDROID and IOS player calls in parallel; returns the first metadata that works.
    private func raceYouTubeInnertube(videoID: String, sourceURL: URL) async -> VideoMetadata? {
        await withTaskGroup(of: VideoMetadata?.self) { group in
            for profile in Self.youtubeClientProfiles {
                group.addTask {
                    do {
                        guard let json = try await self.fetchYouTubePlayerJSON(videoID: videoID, profile: profile) else {
                            return nil
                        }
                        return self.metadataFromYouTubePlayerJSON(json, sourceURL: sourceURL)
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    // MARK: Piped

    private static let pipedInstances = [
        "https://api.piped.private.coffee"
    ]

    private func extractYouTubeViaPiped(videoID: String, sourceURL: URL) async -> VideoMetadata? {
        for base in Self.pipedInstances {
            guard let endpoint = URL(string: "\(base)/streams/\(videoID)") else { continue }
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )

            do {
                let (data, response) = try await Self.fastSession.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    continue
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                let title = (json["title"] as? String) ?? "YouTube video"
                let author = json["uploader"] as? String
                let thumbnail = (json["thumbnailUrl"] as? String).flatMap(URL.init(string:))
                let videoStreams = json["videoStreams"] as? [[String: Any]] ?? []
                let audioStreams = json["audioStreams"] as? [[String: Any]] ?? []
                let hls = (json["hls"] as? String).flatMap(URL.init(string:)).flatMap { url in
                    Self.isTrustedYouTubeMediaURL(url) ? url : nil
                }

                var formats: [VideoFormat] = []

                // Prefer muxed progressive streams (videoOnly == false / missing).
                let muxed = videoStreams.filter { stream in
                    let videoOnly = stream["videoOnly"] as? Bool ?? false
                    guard !videoOnly else { return false }
                    guard let urlString = stream["url"] as? String, let mediaURL = URL(string: urlString) else {
                        return false
                    }
                    return Self.isTrustedYouTubeMediaURL(mediaURL)
                }
                let sortedMuxed = muxed.sorted {
                    Self.pipedQuality($0["quality"] as? String) > Self.pipedQuality($1["quality"] as? String)
                }

                for (index, stream) in sortedMuxed.prefix(5).enumerated() {
                    guard let urlString = stream["url"] as? String, let mediaURL = URL(string: urlString) else {
                        continue
                    }
                    let qualityLabel = stream["quality"] as? String ?? "Video"
                    let height = Self.pipedQuality(qualityLabel)
                    guard height > 0 else { continue }
                    let mime = (stream["mimeType"] as? String) ?? "video/mp4"
                    let isHLS = mime.contains("mpegurl") || mediaURL.pathExtension.lowercased() == "m3u8"
                    let ext = mime.contains("webm") ? "webm" : "mp4"
                    formats.append(
                        VideoFormat(
                            id: "piped-\(index)-\(height)",
                            label: qualityLabel,
                            url: mediaURL,
                            fileExtension: ext,
                            quality: height,
                            isAudioOnly: false,
                            isHLSStream: isHLS
                        )
                    )
                }

                if let hls {
                    formats.insert(
                        VideoFormat(
                            id: "piped-hls",
                            label: "Best (stream)",
                            url: hls,
                            fileExtension: "mp4",
                            quality: sortedMuxed.first.flatMap { Self.pipedQuality($0["quality"] as? String) },
                            isAudioOnly: false,
                            isHLSStream: true
                        ),
                        at: 0
                    )
                }

                if let audio = audioStreams.first(where: {
                    guard let urlString = $0["url"] as? String, let mediaURL = URL(string: urlString) else {
                        return false
                    }
                    return Self.isTrustedYouTubeMediaURL(mediaURL)
                }),
                   let urlString = audio["url"] as? String,
                   let mediaURL = URL(string: urlString) {
                    let mime = (audio["mimeType"] as? String) ?? "audio/mp4"
                    formats.append(
                        VideoFormat(
                            id: "piped-audio",
                            label: "Audio only",
                            url: mediaURL,
                            fileExtension: mime.contains("webm") ? "webm" : "m4a",
                            quality: audio["bitrate"] as? Int,
                            isAudioOnly: true
                        )
                    )
                }

                if formats.contains(where: { !$0.isAudioOnly }) {
                    return VideoMetadata(
                        title: title,
                        author: author,
                        thumbnailURL: thumbnail,
                        platform: .youtube,
                        sourceURL: sourceURL,
                        formats: formats,
                        allowsRealDownload: true,
                        usesYTDLP: false
                    )
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func pipedQuality(_ label: String?) -> Int {
        guard let label else { return 0 }
        let digits = label.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    /// Accept YouTube CDN / Piped proxy URLs; reject unrelated mirrors (LBRY, odycdn, …).
    private static func isTrustedYouTubeMediaURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let absolute = url.absoluteString.lowercased()
        if host.contains("googlevideo.com") { return true }
        if host.contains("youtube.com") || host.contains("ytimg.com") { return true }
        if host.contains("piped") && (absolute.contains("videoplayback") || absolute.contains("m3u8")) {
            return true
        }
        if absolute.contains("/videoplayback") { return true }
        if absolute.contains(".m3u8") && host.contains("googlevideo") { return true }
        return false
    }

    // MARK: Innertube

    private struct YouTubeClientProfile {
        let name: String
        let version: String
        let apiKey: String
        let userAgent: String
        /// `X-YouTube-Client-Name` numeric id used by official clients.
        let clientNameHeader: String
        let extraClientFields: [String: Any]
    }

    private static let youtubeClientProfiles: [YouTubeClientProfile] = [
        YouTubeClientProfile(
            name: "ANDROID",
            version: "20.10.38",
            apiKey: "AIzaSyA8eiZmM1FaDVzRv56ghNOtmvq96PukvtE",
            userAgent: "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip",
            clientNameHeader: "3",
            extraClientFields: [
                "androidSdkVersion": 34,
                "osName": "Android",
                "osVersion": "14"
            ]
        ),
        YouTubeClientProfile(
            name: "IOS",
            version: "20.10.4",
            apiKey: "AIzaSyB-63vPrdThhKuerbB2N_a6SpUGSj3JdxE",
            userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 17_7 like Mac OS X;)",
            clientNameHeader: "5",
            extraClientFields: [
                "deviceMake": "Apple",
                "deviceModel": "iPhone16,2",
                "osName": "iPhone",
                "osVersion": "17.7.0.21H16"
            ]
        )
    ]

    private func fetchYouTubePlayerJSON(videoID: String, profile: YouTubeClientProfile) async throws -> [String: Any]? {
        var components = URLComponents(string: "https://www.youtube.com/youtubei/v1/player")!
        components.queryItems = [
            URLQueryItem(name: "key", value: profile.apiKey),
            URLQueryItem(name: "prettyPrint", value: "false")
        ]
        guard let endpoint = components.url else { return nil }

        var client: [String: Any] = [
            "clientName": profile.name,
            "clientVersion": profile.version,
            "hl": "en",
            "gl": "US",
            "userAgent": profile.userAgent
        ]
        for (key, value) in profile.extraClientFields {
            client[key] = value
        }

        let body: [String: Any] = [
            "context": [
                "client": client,
                "thirdParty": ["embedUrl": "https://www.youtube.com/"]
            ],
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(profile.clientNameHeader, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(profile.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("CONSENT=YES+1; SOCS=CAI", forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.fastSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func extractYouTubeFromWatchPage(videoID: String, sourceURL: URL) async throws -> VideoMetadata? {
        // One page only — full HTML scans are expensive and used to freeze the UI.
        guard let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else {
            return nil
        }
        var request = URLRequest(url: watchURL)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.7 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("CONSENT=YES+1; SOCS=CAI", forHTTPHeaderField: "Cookie")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8),
              let json = Self.youtubePlayerJSON(fromWatchHTML: html),
              let metadata = metadataFromYouTubePlayerJSON(json, sourceURL: sourceURL) else {
            return nil
        }
        return metadata
    }

    private static func youtubePlayerJSON(fromWatchHTML html: String) -> [String: Any]? {
        for needle in ["ytInitialPlayerResponse", "var ytInitialPlayerResponse"] {
            guard let needleRange = html.range(of: needle),
                  let braceStart = html[needleRange.upperBound...].firstIndex(of: "{") else {
                continue
            }
            if let json = extractJSONObject(from: html, startingAt: braceStart) {
                return json
            }
        }
        return nil
    }

    private static func extractJSONObject(from html: String, startingAt start: String.Index) -> [String: Any]? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < html.endIndex {
            let ch = html[index]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        let end = html.index(after: index)
                        let slice = String(html[start..<end])
                        if let data = slice.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            return json
                        }
                        return nil
                    }
                default: break
                }
            }
            index = html.index(after: index)
        }
        return nil
    }

    private func metadataFromYouTubePlayerJSON(_ json: [String: Any], sourceURL: URL) -> VideoMetadata? {
        let streaming = json["streamingData"] as? [String: Any] ?? [:]
        let progressive = streaming["formats"] as? [[String: Any]] ?? []
        let adaptive = streaming["adaptiveFormats"] as? [[String: Any]] ?? []
        let hls = (streaming["hlsManifestUrl"] as? String).flatMap(URL.init(string:))
        let hasAnyStream = hls != nil || !progressive.isEmpty || !adaptive.isEmpty

        if let playability = json["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String,
           status != "OK",
           !hasAnyStream {
            return nil
        }

        let details = json["videoDetails"] as? [String: Any]
        let title = (details?["title"] as? String) ?? "YouTube video"
        let author = details?["author"] as? String
        let thumb = ((details?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?
            .last?["url"] as? String
        let thumbnailURL = thumb.flatMap(URL.init(string:))

        var formats: [VideoFormat] = []
        var seenHeights = Set<Int>()

        // Progressive muxed files first (best download experience).
        for entry in progressive.sorted(by: { ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0) }) {
            guard let mediaURL = Self.mediaURL(from: entry) else { continue }
            let height = entry["height"] as? Int
            if let height {
                if seenHeights.contains(height) { continue }
                seenHeights.insert(height)
            }
            let mime = (entry["mimeType"] as? String) ?? ""
            let itag = entry["itag"] as? Int ?? formats.count
            formats.append(
                VideoFormat(
                    id: "yt-\(itag)",
                    label: height.map { "\($0)p" } ?? "Video",
                    url: mediaURL,
                    fileExtension: mime.contains("webm") ? "webm" : "mp4",
                    quality: height,
                    isAudioOnly: false
                )
            )
            if formats.count >= 6 { break }
        }

        if let hls {
            let insertAt = formats.isEmpty ? 0 : 1
            formats.insert(
                VideoFormat(
                    id: "yt-hls",
                    label: "Best (stream)",
                    url: hls,
                    fileExtension: "mp4",
                    quality: seenHeights.max(),
                    isAudioOnly: false,
                    isHLSStream: true
                ),
                at: min(insertAt, formats.count)
            )
        }

        // Only fall back to adaptive video-only when nothing muxed/HLS exists.
        if formats.filter({ !$0.isHLSStream && !$0.isAudioOnly }).isEmpty && hls == nil {
            for entry in adaptive.sorted(by: { ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0) }) {
                let mime = (entry["mimeType"] as? String) ?? ""
                guard mime.contains("video"), let mediaURL = Self.mediaURL(from: entry) else { continue }
                let height = entry["height"] as? Int
                let itag = entry["itag"] as? Int ?? formats.count
                formats.append(
                    VideoFormat(
                        id: "yt-adapt-\(itag)",
                        label: height.map { "\($0)p (video only)" } ?? "Video only",
                        url: mediaURL,
                        fileExtension: mime.contains("webm") ? "webm" : "mp4",
                        quality: height,
                        isAudioOnly: false
                    )
                )
                if formats.count >= 4 { break }
            }
        }

        if let audio = adaptive.first(where: {
            (($0["mimeType"] as? String) ?? "").hasPrefix("audio/") && Self.mediaURL(from: $0) != nil
        }), let mediaURL = Self.mediaURL(from: audio) {
            let mime = (audio["mimeType"] as? String) ?? ""
            formats.append(
                VideoFormat(
                    id: "yt-audio",
                    label: "Audio only",
                    url: mediaURL,
                    fileExtension: mime.contains("mp4") ? "m4a" : "webm",
                    quality: audio["averageBitrate"] as? Int,
                    isAudioOnly: true
                )
            )
        }

        guard formats.contains(where: { !$0.isAudioOnly }) else { return nil }

        return VideoMetadata(
            title: title,
            author: author,
            thumbnailURL: thumbnailURL,
            platform: .youtube,
            sourceURL: sourceURL,
            formats: formats,
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    // MARK: - Generic HTML

    func extractFromHTMLPage(url: URL, platform: VideoPlatform) async throws -> VideoMetadata? {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.7 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("CONSENT=YES+1; SOCS=CAI", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw PageExtractionError.network("Couldn’t load that page.")
        }
        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        let title = Self.metaContent(html, property: "og:title")
            ?? Self.tagContent(html, tag: "title")
            ?? url.host
            ?? "Video"
        let author = Self.metaContent(html, property: "og:site_name") ?? platform.displayName
        let thumbnail = Self.metaContent(html, property: "og:image").flatMap(URL.init(string:))

        var candidates: [URL] = []
        for key in ["og:video:secure_url", "og:video:url", "og:video", "twitter:player:stream"] {
            if let value = Self.metaContent(html, property: key),
               let media = URL(string: value),
               Self.isLikelyMediaURL(media) || value.lowercased().contains("m3u8") {
                candidates.append(media)
            }
        }
        candidates.append(contentsOf: Self.jsonLDVideoURLs(in: html))
        candidates.append(contentsOf: Self.inlineMP4URLs(in: html))

        var seen = Set<URL>()
        let unique = candidates.filter { seen.insert($0).inserted }
        guard let best = unique.first else { return nil }

        let formats: [VideoFormat] = unique.prefix(4).enumerated().map { index, media in
            let lower = media.absoluteString.lowercased()
            let isHLS = lower.contains("m3u8")
            let ext = isHLS ? "mp4" : (media.pathExtension.isEmpty ? "mp4" : media.pathExtension.lowercased())
            return VideoFormat(
                id: "page-\(index)",
                label: index == 0 ? "Best available" : "Option \(index + 1)",
                url: media,
                fileExtension: ext,
                quality: nil,
                isAudioOnly: ["m4a", "mp3", "aac"].contains(ext),
                isHLSStream: isHLS
            )
        }

        return VideoMetadata(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: author,
            thumbnailURL: thumbnail,
            platform: platform,
            sourceURL: url,
            formats: Array(formats),
            allowsRealDownload: true,
            usesYTDLP: false
        )
    }

    // MARK: - Helpers

    static func youtubeVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("youtu.be") {
            let id = url.path.split(separator: "/").first.map(String.init) ?? ""
            let cleaned = id.split(separator: "?").first.map(String.init) ?? id
            return cleaned.count >= 11 ? String(cleaned.prefix(11)) : nil
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, v.count >= 11 {
            return String(v.prefix(11))
        }
        let parts = url.path.split(separator: "/").map(String.init)
        if let embedIndex = parts.firstIndex(where: { ["embed", "shorts", "live", "v"].contains($0) }),
           embedIndex + 1 < parts.count {
            return String(parts[embedIndex + 1].prefix(11))
        }
        return nil
    }

    private static func mediaURL(from entry: [String: Any]) -> URL? {
        if let urlString = entry["url"] as? String, let url = URL(string: urlString) {
            return url
        }
        return nil
    }

    private static func isLikelyMediaURL(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        if lower.contains(".m3u8") { return false }
        if DirectMediaExtractor.looksLikeDirectMediaURL(url) { return true }
        return lower.contains(".mp4")
            || lower.contains(".mov")
            || lower.contains("mime=video")
            || lower.contains("googlevideo.com")
    }

    static func metaContent(_ html: String, property: String) -> String? {
        let patterns = [
            "property=\"\(property)\"[^>]*content=\"([^\"]+)\"",
            "content=\"([^\"]+)\"[^>]*property=\"\(property)\"",
            "name=\"\(property)\"[^>]*content=\"([^\"]+)\"",
            "content=\"([^\"]+)\"[^>]*name=\"\(property)\""
        ]
        for pattern in patterns {
            if let match = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let snippet = String(html[match])
                if let contentRange = snippet.range(of: "content=\"([^\"]+)\"", options: .regularExpression) {
                    let piece = String(snippet[contentRange])
                    let value = piece
                        .replacingOccurrences(of: "content=\"", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                    if !value.isEmpty { return value.htmlDecoded }
                }
            }
        }
        return nil
    }

    static func tagContent(_ html: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let match = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let snippet = String(html[match])
        return snippet
            .replacingOccurrences(of: "<\(tag)[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</\(tag)>", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .htmlDecoded
    }

    private static func jsonLDVideoURLs(in html: String) -> [URL] {
        var results: [URL] = []
        let pattern = #"\"contentUrl\"\s*:\s*\"(https?[^\"]+)\""#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(html.startIndex..., in: html)
        regex?.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let urlRange = Range(match.range(at: 1), in: html) else { return }
            let raw = String(html[urlRange]).replacingOccurrences(of: "\\/", with: "/")
            if let url = URL(string: raw), isLikelyMediaURL(url) || raw.lowercased().contains("m3u8") {
                results.append(url)
            }
        }
        return results
    }

    static func inlineMP4URLs(in html: String) -> [URL] {
        var results: [URL] = []
        let pattern = #"https?://[^\s\"'<>]+\.mp4[^\s\"'<>]*"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(html.startIndex..., in: html)
        regex?.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
            guard let match, let urlRange = Range(match.range, in: html) else { return }
            if let url = URL(string: String(html[urlRange])) {
                results.append(url)
            }
        }
        return results
    }
}

extension String {
    nonisolated var htmlDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
