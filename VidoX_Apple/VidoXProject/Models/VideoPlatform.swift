import SwiftUI

/// Video hosts VidoX can recognize from a pasted URL (pages or direct files).
enum VideoPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case youtube
    case twitter
    case instagram
    case facebook
    case tiktok
    case vimeo
    case dailymotion
    case reddit
    case twitch
    case streamable
    case rumble
    case web
    case unknown

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .twitter: "X"
        case .instagram: "Instagram"
        case .facebook: "Facebook"
        case .tiktok: "TikTok"
        case .vimeo: "Vimeo"
        case .dailymotion: "Dailymotion"
        case .reddit: "Reddit"
        case .twitch: "Twitch"
        case .streamable: "Streamable"
        case .rumble: "Rumble"
        case .web: "Web"
        case .unknown: "Direct"
        }
    }

    nonisolated var iconName: String {
        switch self {
        case .youtube: "play.rectangle.fill"
        case .twitter: "bubble.left.fill"
        case .instagram: "camera.fill"
        case .facebook: "person.2.fill"
        case .tiktok: "music.note"
        case .vimeo: "v.circle.fill"
        case .dailymotion: "play.circle.fill"
        case .reddit: "bubble.left.and.bubble.right.fill"
        case .twitch: "gamecontroller.fill"
        case .streamable: "rectangle.stack.fill.badge.play"
        case .rumble: "speaker.wave.2.fill"
        case .web: "globe"
        case .unknown: "link"
        }
    }

    var accentColor: Color {
        switch self {
        case .youtube: Color(red: 1.0, green: 0.0, blue: 0.0)
        case .twitter: Color.primary
        case .instagram: Color(red: 0.88, green: 0.19, blue: 0.42)
        case .facebook: Color(red: 0.09, green: 0.47, blue: 0.95)
        case .tiktok: Color(red: 0.0, green: 0.96, blue: 0.88)
        case .vimeo: Color(red: 0.13, green: 0.71, blue: 0.98)
        case .dailymotion: Color(red: 0.0, green: 0.4, blue: 0.85)
        case .reddit: Color(red: 1.0, green: 0.27, blue: 0.0)
        case .twitch: Color(red: 0.57, green: 0.27, blue: 1.0)
        case .streamable: Color(red: 0.05, green: 0.65, blue: 0.91)
        case .rumble: Color(red: 0.42, green: 0.75, blue: 0.12)
        case .web: Color.accentColor
        case .unknown: Color.secondary
        }
    }

    /// Page-based hosts (not a raw media file). Used for preview / engine routing.
    nonisolated var isPageHost: Bool {
        switch self {
        case .unknown: false
        case .web: true
        default: true
        }
    }

    nonisolated static func detect(from urlString: String) -> VideoPlatform {
        let lower = urlString.lowercased()
        let hosts: [(VideoPlatform, [String])] = [
            (.youtube, ["youtube.com", "youtu.be", "youtube-nocookie.com", "m.youtube.com", "music.youtube.com"]),
            (.twitter, ["twitter.com", "x.com", "t.co", "mobile.twitter.com"]),
            (.instagram, ["instagram.com", "instagr.am", "kkinstagram.com"]),
            (.facebook, [
                "facebook.com", "fb.watch", "fb.com", "fb.me",
                "m.facebook.com", "web.facebook.com", "mbasic.facebook.com"
            ]),
            (.tiktok, ["tiktok.com", "vm.tiktok.com", "vt.tiktok.com"]),
            (.vimeo, ["vimeo.com", "player.vimeo.com"]),
            (.dailymotion, ["dailymotion.com", "dai.ly"]),
            (.reddit, ["reddit.com", "redd.it", "v.redd.it", "old.reddit.com"]),
            (.twitch, ["twitch.tv", "clips.twitch.tv", "m.twitch.tv"]),
            (.streamable, ["streamable.com"]),
            (.rumble, ["rumble.com", "rumble.cloud"])
        ]
        for (platform, patterns) in hosts {
            if patterns.contains(where: { lower.contains($0) }) {
                return platform
            }
        }
        return .unknown
    }
}
