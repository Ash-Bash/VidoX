import SwiftUI

struct WhatsNewItem: Identifiable, Hashable {
    var id: String { title }
    let systemImage: String
    let accent: Color
    let title: String
    let message: String
}

enum WhatsNewNotes {
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static func items(after lastSeenVersion: String) -> [WhatsNewItem] {
        releases
            .filter { version($0.version, isNewerThan: lastSeenVersion) }
            .filter { !version($0.version, isNewerThan: currentVersion) }
            .flatMap(\.items)
    }

    /// Upgrade notes when lastSeen is older; current-release notes for Settings replay.
    static func displayItems(lastSeenVersion: String) -> [WhatsNewItem] {
        let newer = items(after: lastSeenVersion)
        return newer.isEmpty ? currentReleaseItems : newer
    }

    static var currentReleaseItems: [WhatsNewItem] {
        releases.last { !version($0.version, isNewerThan: currentVersion) }?.items ?? []
    }

    static func shouldPresent(lastSeenVersion: String) -> Bool {
        lastSeenVersion != currentVersion && !items(after: lastSeenVersion).isEmpty
    }

    private static let releases: [(version: String, items: [WhatsNewItem])] = [
        (
            "1.1.0",
            [
                WhatsNewItem(
                    systemImage: "arrow.up.arrow.down",
                    accent: Color(red: 0.0, green: 0.48, blue: 1.0),
                    title: "Library sorting",
                    message: "Sort by newest, title, video size, or social site."
                ),
                WhatsNewItem(
                    systemImage: "menubar.rectangle",
                    accent: Color(red: 0.35, green: 0.34, blue: 0.84),
                    title: "Desktop menus",
                    message: "Download, browse, and sort from the menu bar on Mac and iPad."
                ),
                WhatsNewItem(
                    systemImage: "camera.fill",
                    accent: Color(red: 0.88, green: 0.19, blue: 0.42),
                    title: "Faster Instagram",
                    message: "Instagram and kkinstagram links resolve in parallel, so they load sooner."
                ),
                WhatsNewItem(
                    systemImage: "square.grid.2x2.fill",
                    accent: Color.orange,
                    title: "Sidebar action cards",
                    message: "Library and Settings sit in Reminders-style cards on iPad and Mac."
                ),
                WhatsNewItem(
                    systemImage: "gearshape.fill",
                    accent: Color(red: 0.56, green: 0.56, blue: 0.58),
                    title: "Library cleanup",
                    message: "Remove video files or wipe the library from Settings, without touching Photos copies."
                ),
                WhatsNewItem(
                    systemImage: "antenna.radiowaves.left.and.right",
                    accent: Color(red: 0.10, green: 0.68, blue: 0.98),
                    title: "Nearby Sync switch",
                    message: "Turn Nearby Sync on or off from Settings, or the Sync menu on Mac."
                )
            ]
        )
    ]

    private static func version(_ lhs: String, isNewerThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

/// Shown after an update when the user has already completed first-run onboarding.
struct WhatsNewView: View {
    var items: [WhatsNewItem] = WhatsNewNotes.displayItems(lastSeenVersion: "")
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("What’s New")
                .font(.title.bold())
                .padding(.top, 28)
            Text("Version \(WhatsNewNotes.currentVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(item.accent, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.message)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            Button(action: onFinished) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .interactiveDismissDisabled()
    }
}

#Preview("What's New") {
    WhatsNewView(onFinished: {})
}
