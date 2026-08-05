import SwiftUI
import SwiftData

@main
struct VidoXApp: App {
    /// Shared navigation for tabs / split view and the download sheet.
    @State private var navigation = AppNavigationState()
    @State private var localSync = LocalSyncService.shared

    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: DownloadedVideo.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(navigation)
                .environment(localSync)
                .sheet(isPresented: Bindable(navigation).isDownloaderPresented) {
                    DownloaderSheet()
                }
                .task {
                    LibraryStorageMigrator.repairAll(in: modelContainer.mainContext)
                    localSync.configure(container: modelContainer)
                    localSync.startIfEnabled()
                }
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif
    }
}

/// Routes between compact TabView and regular NavigationSplitView shells.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        adaptiveRootShell(
            sizeClass: sizeClass,
            compact: { CompactTabShell() },
            regular: { RegularSplitShell() }
        )
    }
}

#Preview("Root") {
    RootView()
        .environment(AppNavigationState())
        .environment(LocalSyncService.shared)
        .modelContainer(for: DownloadedVideo.self, inMemory: true)
}
