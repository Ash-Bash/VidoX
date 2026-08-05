import SwiftUI

private struct ShowsDetailDownloadButtonKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// When `false` (split-view detail), the Download control lives only in the sidebar.
    var showsDetailDownloadButton: Bool {
        get { self[ShowsDetailDownloadButtonKey.self] }
        set { self[ShowsDetailDownloadButtonKey.self] = newValue }
    }
}

/// Shared toolbar control that presents the downloader sheet.
struct DownloadToolbarButton: View {
    @Environment(AppNavigationState.self) private var navigation

    var body: some View {
        Button {
            navigation.isDownloaderPresented = true
        } label: {
            Label("Download", systemImage: "arrow.down.circle.fill")
        }
        .help("Download a video")
    }
}

/// Adds the Download toolbar item only when detail-level download buttons are enabled.
struct DetailDownloadToolbarItem: ToolbarContent {
    @Environment(\.showsDetailDownloadButton) private var showsDetailDownloadButton

    var body: some ToolbarContent {
        if showsDetailDownloadButton {
            ToolbarItem(placement: .primaryAction) {
                DownloadToolbarButton()
            }
        }
    }
}
