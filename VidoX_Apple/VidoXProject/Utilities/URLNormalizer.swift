import Foundation

/// Cleans pasted URLs so extraction is more reliable across platforms.
enum URLNormalizer {
    /// Tracking / share noise that breaks some extractors when left on the URL.
    private static let stripQueryKeys: Set<String> = [
        "fbclid", "fb_action_ids", "fb_action_types", "fb_source",
        "mibextid", "rdid", "share_url", "ref", "refsrc", "_rdr",
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "si", "feature", "pp", "s", "refid", "__tn__", "sfnsn"
    ]

    /// Trims whitespace/quotes, adds `https://` when missing, and rejects non-http(s) schemes.
    static func url(from raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Strip wrapping quotes copied from browsers or chat apps.
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'"))
            || (trimmed.hasPrefix("<") && trimmed.hasSuffix(">")) {
            trimmed = String(trimmed.dropFirst().dropLast())
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: trimmed) else { return nil }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        components.scheme = scheme

        if let host = components.host?.lowercased() {
            components.host = canonicalizeHost(host)
        }

        if VideoPlatform.detect(from: components.url?.absoluteString ?? trimmed) == .facebook {
            components = normalizeFacebookComponents(components)
        } else if VideoPlatform.detect(from: components.url?.absoluteString ?? trimmed) == .youtube {
            components = normalizeYouTubeComponents(components)
        } else if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.filter { item in
                !stripQueryKeys.contains(item.name.lowercased())
            }
            if components.queryItems?.isEmpty == true {
                components.queryItems = nil
            }
        }

        return components.url
    }

    /// Rewrites kkinstagram (and similar) hosts to instagram.com for extractors that
    /// only understand official Instagram URLs (yt-dlp).
    static func instagramCanonicalURL(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              host == "kkinstagram.com" || host.hasSuffix(".kkinstagram.com") else {
            return url
        }
        components.host = "www.instagram.com"
        return components.url ?? url
    }

    // MARK: - Host / Facebook helpers

    private static func canonicalizeHost(_ host: String) -> String {
        switch host {
        case "m.facebook.com", "mbasic.facebook.com", "web.facebook.com", "mobile.facebook.com":
            "www.facebook.com"
        case "fb.com", "www.fb.com":
            "www.facebook.com"
        case "www.fb.watch":
            "fb.watch"
        case "m.youtube.com", "music.youtube.com", "www.music.youtube.com",
             "youtube-nocookie.com", "www.youtube-nocookie.com":
            "www.youtube.com"
        default:
            host
        }
    }

    private static func normalizeFacebookComponents(_ components: URLComponents) -> URLComponents {
        var components = components
        let path = components.path

        // /reel/<id> and /videos/<id> are stable; drop tracking query noise.
        if let items = components.queryItems, !items.isEmpty {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                if name == "v" || name == "story_fbid" || name == "id" || name == "video_id" {
                    return true
                }
                return !stripQueryKeys.contains(name)
            }
            components.queryItems = kept.isEmpty ? nil : kept
        }

        // Collapse accidental trailing slash variants on share links.
        if path.hasPrefix("/share/"), path.count > 1, path.hasSuffix("/") {
            components.path = String(path.dropLast())
        }

        return components
    }

    private static func normalizeYouTubeComponents(_ components: URLComponents) -> URLComponents {
        var components = components
        if let items = components.queryItems, !items.isEmpty {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                if name == "v" || name == "vi" || name == "t" || name == "list" {
                    return true
                }
                return !stripQueryKeys.contains(name)
            }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        return components
    }

    /// Best-effort numeric Facebook video id from common URL shapes.
    static func facebookVideoID(from url: URL) -> String? {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for key in ["v", "video_id", "story_fbid"] {
                if let value = items.first(where: { $0.name == key })?.value,
                   isDigits(value),
                   value.count >= 5 {
                    return value
                }
            }
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return nil }

        if let reelIndex = parts.firstIndex(where: { $0 == "reel" || $0 == "videos" || $0 == "watch" }),
           reelIndex + 1 < parts.count {
            let candidate = parts[reelIndex + 1]
                .split(separator: "?").first
                .map(String.init) ?? parts[reelIndex + 1]
            if isDigits(candidate), candidate.count >= 5 {
                return candidate
            }
        }

        // /username/videos/<id>
        if parts.count >= 3, parts[1] == "videos",
           isDigits(parts[2]),
           parts[2].count >= 5 {
            return parts[2]
        }

        return nil
    }

    private static func isDigits(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }
}
