import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#endif

/// Shared export / delete actions. Videos always live in app sandbox until the user
/// explicitly chooses Photos, Files, Share, or a Mac save location.
struct VideoLibraryItemActions: ViewModifier {
    @Environment(\.modelContext) private var modelContext

    let video: DownloadedVideo
    var onOpen: (() -> Void)?
    var onDeleted: (() -> Void)?

    @State private var exportService = VideoExportService()
    @State private var alertMessage: String?
    @State private var showDeleteConfirm = false
    @State private var isBusy = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let onOpen {
                    Button(action: onOpen) {
                        Label("Open", systemImage: "play.rectangle")
                    }
                    Divider()
                }

                Button {
                    video.togglePinned()
                    try? modelContext.save()
                } label: {
                    Label(
                        video.isPinned ? "Unpin" : "Pin",
                        systemImage: video.isPinned ? "pin.slash" : "pin"
                    )
                }

                Divider()

                Button {
                    Task { await saveToPhotos() }
                } label: {
                    Label("Save to Photos", systemImage: "photo.on.rectangle")
                }
                .disabled(isBusy)

                #if os(iOS) || os(visionOS)
                ShareLink(item: video.fileURL) {
                    Label("Share / Save to Files…", systemImage: "square.and.arrow.up")
                }
                #elseif os(macOS)
                Button {
                    Task { await saveToFilesystem() }
                } label: {
                    Label("Save to Disk…", systemImage: "folder")
                }
                .disabled(isBusy)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([video.fileURL])
                } label: {
                    Label("Show in Finder", systemImage: "finder")
                }
                #endif

                Divider()

                Button("Delete from Library", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
            .confirmationDialog(
                "Delete this video?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteVideo)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the file from VidoX storage only. Items you already saved to Photos or Files are not deleted.")
            }
            .alert("Notice", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .overlay {
                if isBusy {
                    ProgressView()
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                }
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
            alertMessage = "Saved a copy. The original stays in VidoX."
        } catch let error as ExportError where error == .saveCancelled {
            // Ignore cancel.
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deleteVideo() {
        let videoID = video.id
        LocalSyncService.shared.noteDeleted(videoID: videoID)
        FileStorage.removeFile(at: video.localFilePath)
        if let thumb = video.thumbnailPath {
            FileStorage.removeFile(at: thumb)
        }
        modelContext.delete(video)
        try? modelContext.save()
        onDeleted?()
    }
}

extension View {
    /// Long-press / right-click actions to copy a sandbox video out to Photos / Files / Disk.
    func videoLibraryItemActions(
        for video: DownloadedVideo,
        onOpen: (() -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) -> some View {
        modifier(VideoLibraryItemActions(video: video, onOpen: onOpen, onDeleted: onDeleted))
    }
}
