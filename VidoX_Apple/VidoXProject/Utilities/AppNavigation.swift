import SwiftUI

/// Top-level destinations shared by TabView (Pins is its own tab).
enum AppDestination: String, CaseIterable, Identifiable, Hashable {
    case recent
    case library
    case pins
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .library: "Library"
        case .pins: "Pins"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock.fill"
        case .library: "film.stack.fill"
        case .pins: "pin.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// Sidebar selection for split view: browse destinations or a specific pinned video.
enum SplitSidebarSelection: Hashable {
    case destination(AppDestination)
    case pinnedVideo(UUID)
}

/// Shared presentation state for the download sheet and selected destination.
@Observable
final class AppNavigationState {
    var selectedDestination: AppDestination = .recent
    /// Optional so `List(selection:)` works on iOS (requires `Binding<Selection?>`).
    var splitSelection: SplitSidebarSelection? = .destination(.recent)
    var isDownloaderPresented = false
    /// Selected library item for navigation within Library / Pins stacks.
    var selectedVideoID: UUID?
}
