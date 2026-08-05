import SwiftUI
import SwiftData
import AVKit

#if os(macOS)
import AppKit
#endif

/// Detail, playback, and export actions for a single library entry.
struct VideoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigation

    let video: DownloadedVideo

    @State private var exportService = VideoExportService()
    @State private var isBusy = false
    @State private var isRedownloading = false
    @State private var busyLabel = "Looking up…"
    @State private var alertMessage: String?
    @State private var showDeleteConfirm = false
    @State private var showFullScreenPlayer = false
    @State private var player: AVPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                playerSection
                infoSection
                actionsSection
            }
            .padding(20)
        }
        .background(Color.primary.opacity(0.03))
        .navigationTitle(video.title)
        .modifier(InlineNavigationTitleModifier())
        .busyProgressCover(isPresented: $isRedownloading, label: busyLabel)
        .alert("Notice", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog("Delete this video?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteVideo() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file will be removed from VidoX storage. Copies already in Photos or Files are kept.")
        }
        .sheet(isPresented: $showFullScreenPlayer) {
            NavigationStack {
                LibraryVideoPlayerView(url: video.fileURL)
                    .navigationTitle(video.title)
                    .modifier(InlineNavigationTitleModifier())
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showFullScreenPlayer = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 480)
            #endif
        }
        .onDisappear {
            player?.pause()
        }
    }

    private var playerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                if video.isFileAvailable {
                    if let player {
                        VideoPlayer(player: player)
                    } else {
                        VideoThumbnailView(url: video.fileURL, cornerRadius: 14)
                            .overlay {
                                Button {
                                    prepareAndPlay()
                                } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 56))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                            }
                    }
                } else {
                    ContentUnavailableView(
                        "File Missing",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This video file is no longer on disk. Redownload to restore it without creating a duplicate.")
                    )
                }
            }
            .frame(minHeight: 260)
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                if video.isFileAvailable {
                    Button {
                        prepareAndPlay()
                    } label: {
                        Label(player == nil ? "Play" : "Replay", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showFullScreenPlayer = true
                    } label: {
                        Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await redownload() }
                    } label: {
                        Label("Redownload", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRedownloading)
                }

                Button {
                    video.togglePinned()
                    try? modelContext.save()
                } label: {
                    Label(video.isPinned ? "Unpin" : "Pin", systemImage: video.isPinned ? "pin.slash.fill" : "pin.fill")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(video.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)

            HStack(spacing: 10) {
                PlatformBadge(platform: video.platform)
                if video.isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(.orange)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                if let author = video.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Downloaded").foregroundStyle(.secondary)
                    Text(video.downloadedAt.formatted(date: .abbreviated, time: .shortened))
                }
                GridRow {
                    Text("Size").foregroundStyle(.secondary)
                    Text(video.formattedFileSize)
                }
                GridRow {
                    Text("Format").foregroundStyle(.secondary)
                    Text(video.fileExtension.uppercased())
                }
            }
            .font(.subheadline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(video.sourceURL)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export a copy")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            Text("The original stays in VidoX until you delete it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            #if os(iOS) || os(visionOS)
            actionButton("Save to Photos", systemImage: "photo.on.rectangle") {
                Task { await saveToPhotos() }
            }
            .disabled(!video.isFileAvailable)
            Divider().padding(.leading, 48)
            if video.isFileAvailable {
                ShareLink(item: video.fileURL) {
                    actionLabel("Share / Save to Files…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
            #elseif os(macOS)
            actionButton("Save to Photos", systemImage: "photo.on.rectangle") {
                Task { await saveToPhotos() }
            }
            .disabled(!video.isFileAvailable)
            Divider().padding(.leading, 48)
            actionButton("Save to Disk…", systemImage: "folder") {
                Task { await saveToFilesystem() }
            }
            .disabled(!video.isFileAvailable)
            Divider().padding(.leading, 48)
            actionButton("Show in Finder", systemImage: "finder") {
                NSWorkspace.shared.activateFileViewerSelecting([video.fileURL])
            }
            .disabled(!video.isFileAvailable)
            #endif
            if !video.isFileAvailable {
                Divider().padding(.leading, 48)
                actionButton("Redownload", systemImage: "arrow.clockwise.circle") {
                    Task { await redownload() }
                }
            }
            Divider().padding(.leading, 48)
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                actionLabel("Delete from Library", systemImage: "trash", destructive: true)
            }
            .buttonStyle(.plain)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(isBusy || isRedownloading)
    }

    private func actionLabel(_ title: String, systemImage: String, destructive: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 28)
                .foregroundStyle(destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
            Text(title)
                .foregroundStyle(destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func prepareAndPlay() {
        guard video.isFileAvailable else {
            alertMessage = "This video file is missing from disk."
            return
        }
        PlaybackAudioSession.activateForPlayback()
        let newPlayer = AVPlayer(url: video.fileURL)
        newPlayer.isMuted = false
        newPlayer.volume = 1
        player = newPlayer
        newPlayer.seek(to: .zero)
        newPlayer.play()
    }

    private func redownload() async {
        isRedownloading = true
        busyLabel = "Looking up…"
        defer { isRedownloading = false }
        do {
            try await VideoRedownloader.redownload(video: video, modelContext: modelContext) { label, _ in
                busyLabel = label
            }
            alertMessage = "Redownloaded successfully."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func saveToPhotos() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await exportService.saveToPhotos(fileURL: video.fileURL)
            alertMessage = "Saved a copy to Photos. The original stays in VidoX."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func saveToFilesystem() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let name = "\(video.title).\(video.fileExtension)"
            try await exportService.exportToUserChosenLocation(fileURL: video.fileURL, suggestedName: name)
        } catch let error as ExportError where error == .saveCancelled {
            // User dismissed the panel — ignore.
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deleteVideo() {
        player?.pause()
        player = nil
        let videoID = video.id
        // Tombstone + notify peers before removing locally so reconnect sync cannot resurrect it.
        LocalSyncService.shared.noteDeleted(videoID: videoID)
        FileStorage.removeFile(at: video.localFilePath)
        if let thumb = video.thumbnailPath {
            FileStorage.removeFile(at: thumb)
        }
        if navigation.selectedVideoID == video.id {
            navigation.selectedVideoID = nil
        }
        modelContext.delete(video)
        try? modelContext.save()
    }
}

private struct InlineNavigationTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS) || os(visionOS)
        content.navigationBarTitleDisplayMode(.inline)
        #else
        content
        #endif
    }
}
