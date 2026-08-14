import SwiftUI
import SwiftData

/// Polished settings screen — storage rules, pins, platforms, and about.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigation
    @Environment(LocalSyncService.self) private var localSync
    @Query private var allVideos: [DownloadedVideo]
    @Query(filter: #Predicate<DownloadedVideo> { $0.isPinned })
    private var pinnedVideos: [DownloadedVideo]

    @State private var libraryConfirm: LibraryCleanupConfirm?
    @State private var storageEpoch = 0

    /// Actual bytes in the Videos folder (not stale SwiftData size metadata).
    private var totalBytesOnDisk: Int64 {
        _ = storageEpoch
        return FileStorage.videosDirectoryByteCount()
    }

    private var missingFileCount: Int {
        _ = storageEpoch
        return allVideos.filter { !$0.isFileAvailable }.count
    }

    private var filesOnDiskCount: Int {
        _ = storageEpoch
        return allVideos.filter(\.isFileAvailable).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                libraryCard
                nearbySyncCard
                storageCard
                downloadsCard
                platformsCard
                aboutCard
            }
            .padding(20)
        }
        .background(Color.primary.opacity(0.03))
        .navigationTitle("Settings")
        .toolbar { DetailDownloadToolbarItem() }
        .confirmationDialog(
            "Remove video files?",
            isPresented: Binding(
                get: { libraryConfirm == .removeFiles },
                set: { if !$0 { libraryConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Files", role: .destructive) { removeVideoFilesKeepingItems() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(LibraryCleanupConfirm.removeFiles.message)
        }
        .confirmationDialog(
            "Delete entire library?",
            isPresented: Binding(
                get: { libraryConfirm == .deleteLibrary },
                set: { if !$0 { libraryConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Library", role: .destructive) { deleteEntireLibrary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(LibraryCleanupConfirm.deleteLibrary.message)
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image("AppIconDisplay")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("VidoX")
                    .font(.title2.weight(.bold))
                Text("Your videos, in one place")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var libraryCard: some View {
        settingsCard(title: "Library", systemImage: "film.stack.fill") {
            HStack(spacing: 12) {
                metricTile(value: "\(allVideos.count)", label: "Videos", color: .accentColor)
                metricTile(value: "\(pinnedVideos.count)", label: "Pinned", color: .orange)
                metricTile(
                    value: ByteCountFormatter.string(fromByteCount: totalBytesOnDisk, countStyle: .file),
                    label: "On disk",
                    color: .secondary
                )
            }

            if missingFileCount > 0 {
                Text(
                    missingFileCount == 1
                        ? "1 library item has no file on disk. Open it and tap Redownload, or delete it."
                        : "\(missingFileCount) library items have no file on disk. Open each and tap Redownload, or delete them."
                )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    libraryConfirm = .removeFiles
                } label: {
                    Label("Remove video files", systemImage: "internaldrive")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(filesOnDiskCount == 0)

                Text("Frees space on this device. Titles stay in the library so you can redownload them later.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    libraryConfirm = .deleteLibrary
                } label: {
                    Label("Delete entire library", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(allVideos.isEmpty)

                Text("Removes every item and its video file from VidoX. Copies already in Photos or Files are kept.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var nearbySyncCard: some View {
        settingsCard(title: "Nearby Sync", systemImage: "antenna.radiowaves.left.and.right") {
            HStack(alignment: .center, spacing: 12) {
                Text("Sync with nearby Apple devices")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle(
                    "Sync with nearby Apple devices",
                    isOn: Binding(
                        get: { localSync.isEnabled },
                        set: { localSync.isEnabled = $0 }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .accessibilityElement(children: .combine)

            Text("No iCloud. When this iPhone and your Mac (or another device) are nearby with VidoX open, libraries catch up — including downloads made while you were apart.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label(localSync.statusText, systemImage: localSync.connectedPeerName == nil ? "wifi" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(localSync.connectedPeerName == nil ? Color.secondary : Color.green)

                if localSync.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }

                if let error = localSync.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var storageCard: some View {
        settingsCard(title: "Storage", systemImage: "internaldrive.fill") {
            Text("Downloads stay inside VidoX. Copies go to Photos or Files only when you choose Save / Share from a video or its context menu.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label("App library", systemImage: "folder.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(FileStorage.videosDirectory.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Text(
                    "Using \(ByteCountFormatter.string(fromByteCount: totalBytesOnDisk, countStyle: .file)) on disk"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var downloadsCard: some View {
        settingsCard(title: "Downloads", systemImage: "arrow.down.circle.fill") {
            if FeatureFlags.experimentalSocialDownloads {
                HStack {
                    Label("Standalone social", systemImage: "hammer.fill")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("On")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Text("Personal / sideload mode. iPhone resolves page media in-app; Mac fetches a download engine on first use. Set FeatureFlags.experimentalSocialDownloads to false before App Store builds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Direct media file links (for example .mp4) download into the app. Social pages are preview-only in this build.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Pin favourites from Library — they appear in the Pins tab on iPhone, and under Pinned in the sidebar on iPad, Mac, and visionOS.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var platformsCard: some View {
        settingsCard(title: "Platforms", systemImage: "globe") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(VideoPlatform.allCases.filter { $0 != .unknown && $0 != .web }) { platform in
                    HStack(spacing: 8) {
                        Image(systemName: platform.iconName)
                            .foregroundStyle(platform.accentColor)
                            .frame(width: 20)
                        Text(platform.displayName)
                            .font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            Text("Standalone mode resolves these hosts natively on iPhone/iPad and via the built-in engine on Mac. Direct file links (.mp4, .mov, …) always work.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var aboutCard: some View {
        settingsCard(title: "About", systemImage: "info.circle.fill") {
            LabeledContent("Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            LabeledContent("Build") {
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metricTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func removeVideoFilesKeepingItems() {
        for video in allVideos where video.isFileAvailable {
            FileStorage.removeFile(at: video.localFilePath)
        }
        storageEpoch += 1
    }

    private func deleteEntireLibrary() {
        navigation.selectedVideoID = nil
        for video in allVideos {
            LocalSyncService.shared.noteDeleted(videoID: video.id)
            FileStorage.removeFile(at: video.localFilePath)
            if let thumb = video.thumbnailPath {
                FileStorage.removeFile(at: thumb)
            }
            modelContext.delete(video)
        }
        try? modelContext.save()
        FileStorage.removeAllMediaFiles()
        storageEpoch += 1
    }
}

private enum LibraryCleanupConfirm {
    case removeFiles
    case deleteLibrary

    var message: String {
        switch self {
        case .removeFiles:
            "Deletes downloaded video files to free space. Library items stay so you can redownload them later. Copies already in Photos or Files are kept."
        case .deleteLibrary:
            "Removes every library item and its video file from VidoX. Copies already in Photos or Files are kept."
        }
    }
}
