import SwiftUI

private struct VidoxNavigationKey: FocusedValueKey {
    typealias Value = AppNavigationState
}

extension FocusedValues {
    var vidoxNavigation: AppNavigationState? {
        get { self[VidoxNavigationKey.self] }
        set { self[VidoxNavigationKey.self] = newValue }
    }
}

/// Menu bar commands for Mac and iPad (keyboard / Stage Manager menu bar).
struct VidoxCommands: Commands {
    @FocusedValue(\.vidoxNavigation) private var navigation
    @AppStorage("library.layoutMode") private var layoutModeRaw = LibraryLayoutMode.grid.rawValue
    @AppStorage("library.sortMode") private var sortModeRaw = LibrarySortMode.newest.rawValue

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Download Video…") {
                navigation?.openDownloader()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Picker("Layout", selection: $layoutModeRaw) {
                ForEach(LibraryLayoutMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            Picker("Sort", selection: $sortModeRaw) {
                ForEach(LibrarySortMode.allCases) { mode in
                    Text(mode.menuTitle).tag(mode.rawValue)
                }
            }
        }

        CommandMenu("Go") {
            Button("Library") {
                navigation?.go(to: .library)
            }
            .keyboardShortcut("1", modifiers: .command)
            Button("Pins") {
                navigation?.go(to: .pins)
            }
            .keyboardShortcut("2", modifiers: .command)
            Button("Settings") {
                navigation?.go(to: .settings)
            }
            .keyboardShortcut("3", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("VidoX Welcome Guide") {
                navigation?.showOnboarding()
            }
            Button("What’s New in VidoX") {
                navigation?.showWhatsNew()
            }
        }

        CommandMenu("Sync") {
            Toggle("Sync with Nearby Apple Devices", isOn: nearbySyncBinding)
        }

        #if os(macOS)
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                navigation?.go(to: .settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        #endif
    }

    private var nearbySyncBinding: Binding<Bool> {
        Binding(
            get: { LocalSyncService.shared.isEnabled },
            set: { LocalSyncService.shared.isEnabled = $0 }
        )
    }
}
