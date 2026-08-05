import Foundation

/// Preview-only metadata for known video page hosts (App Store–ready path).
nonisolated struct StubSocialExtractor: VideoExtracting {
    nonisolated func extract(from url: URL) async throws -> VideoMetadata {
        var platform = VideoPlatform.detect(from: url.absoluteString)
        if platform == .unknown {
            platform = .web
        }

        let oembed = await fetchOEmbed(for: url, platform: platform)

        return VideoMetadata(
            title: oembed?.title ?? "\(platform.displayName) video",
            author: oembed?.authorName ?? platform.displayName,
            thumbnailURL: oembed?.thumbnailURL,
            platform: platform,
            sourceURL: url,
            formats: [],
            allowsRealDownload: false
        )
    }

    private struct OEmbedInfo {
        var title: String?
        var authorName: String?
        var thumbnailURL: URL?
    }

    private func fetchOEmbed(for url: URL, platform: VideoPlatform) async -> OEmbedInfo? {
        guard let endpoint = oEmbedEndpoint(for: url, platform: platform) else {
            try? await Task.sleep(for: .milliseconds(250))
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let title = json["title"] as? String
            let author = json["author_name"] as? String
            let thumb = (json["thumbnail_url"] as? String).flatMap(URL.init(string:))
            return OEmbedInfo(title: title, authorName: author, thumbnailURL: thumb)
        } catch {
            return nil
        }
    }

    private func oEmbedEndpoint(for url: URL, platform: VideoPlatform) -> URL? {
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString
        switch platform {
        case .youtube:
            return URL(string: "https://www.youtube.com/oembed?url=\(encoded)&format=json")
        case .twitter:
            return URL(string: "https://publish.twitter.com/oembed?url=\(encoded)")
        case .tiktok:
            return URL(string: "https://www.tiktok.com/oembed?url=\(encoded)")
        case .vimeo:
            return URL(string: "https://vimeo.com/api/oembed.json?url=\(encoded)")
        case .dailymotion:
            return URL(string: "https://www.dailymotion.com/services/oembed?url=\(encoded)")
        case .reddit:
            return URL(string: "https://www.reddit.com/oembed?url=\(encoded)")
        case .streamable:
            // No public oEmbed; preview title falls back to platform name.
            return nil
        case .rumble:
            return nil
        case .twitch:
            return nil
        case .instagram, .facebook, .web, .unknown:
            return nil
        }
    }
}
