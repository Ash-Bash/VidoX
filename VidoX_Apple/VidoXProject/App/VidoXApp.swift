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
                .focusedSceneValue(\.vidoxNavigation, navigation)
                .sheet(isPresented: Bindable(navigation).isDownloaderPresented) {
                    DownloaderSheet()
                }
                .task {
                    LibraryStorageMigrator.repairAll(in: modelContainer.mainContext)
                    localSync.configure(container: modelContainer)
                    localSync.startIfEnabled()
                    #if os(macOS)
                    YTDLPTool.prepareInBackground()
                    #endif
                }
        }
        .modelContainer(modelContainer)
        .commands {
            VidoxCommands()
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif
    }
}

/// Routes between compact TabView and regular NavigationSplitView shells.
struct RootView: View {
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @AppStorage("whatsNew.lastSeenVersion") private var lastSeenVersion = ""

    var body: some View {
        adaptiveRootShell(
            sizeClass: sizeClass,
            compact: { CompactTabShell() },
            regular: { RegularSplitShell() }
        )
        .onAppear {
            if !onboardingCompleted {
                navigation.isOnboardingPresented = true
            } else if WhatsNewNotes.shouldPresent(lastSeenVersion: lastSeenVersion) {
                navigation.isWhatsNewPresented = true
            }
        }
        .modifier(
            OnboardingPresentationModifier(
                isPresented: Bindable(navigation).isOnboardingPresented,
                onFinished: {
                    onboardingCompleted = true
                    lastSeenVersion = WhatsNewNotes.currentVersion
                    navigation.isOnboardingPresented = false
                }
            )
        )
        .modifier(
            WhatsNewPresentationModifier(
                isPresented: Bindable(navigation).isWhatsNewPresented,
                items: WhatsNewNotes.displayItems(lastSeenVersion: lastSeenVersion),
                onFinished: {
                    lastSeenVersion = WhatsNewNotes.currentVersion
                    navigation.isWhatsNewPresented = false
                }
            )
        )
    }
}

private struct OnboardingPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onFinished: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .sheet(isPresented: $isPresented) {
                OnboardingView(onFinished: onFinished)
                    .frame(width: 420, height: 480)
            }
        #else
        content
            .fullScreenCover(isPresented: $isPresented) {
                OnboardingView(onFinished: onFinished)
            }
        #endif
    }
}

private struct WhatsNewPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    var items: [WhatsNewItem]
    let onFinished: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .sheet(isPresented: $isPresented) {
                WhatsNewView(items: items, onFinished: onFinished)
                    .frame(width: 420, height: 520)
            }
        #else
        content
            .sheet(isPresented: $isPresented) {
                WhatsNewView(items: items, onFinished: onFinished)
                    .presentationDetents([.medium, .large])
            }
        #endif
    }
}

#Preview("Root") {
    RootView()
        .environment(AppNavigationState())
        .environment(LocalSyncService.shared)
        .modelContainer(for: DownloadedVideo.self, inMemory: true)
}
