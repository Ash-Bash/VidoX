import Foundation

/// Compile-time switches for personal / sideload behaviour.
///
/// **App Store:** set `experimentalSocialDownloads` to `false` before shipping.
/// When enabled, macOS uses a managed yt-dlp binary; iOS / iPadOS / visionOS resolve
/// page links natively (YouTube player API + Open Graph / media URL discovery).
/// That path is not App Store–safe.
enum FeatureFlags {
    /// When `true`, social / video page URLs can be downloaded in standalone mode.
    /// When `false`, page URLs are preview-only (App Store–ready path).
    nonisolated static let experimentalSocialDownloads = true
}
