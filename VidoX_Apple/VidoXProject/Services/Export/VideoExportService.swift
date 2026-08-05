import Foundation
import Photos

#if canImport(AppKit)
import AppKit
#endif

/// Saves library videos to Photos or a user-chosen Files / Finder location.
struct VideoExportService: VideoExporting {
    func saveToPhotos(fileURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ExportError.fileMissing
        }
        try await addToPhotoLibrary(fileURL: fileURL)
    }

    func exportToUserChosenLocation(fileURL: URL, suggestedName: String) async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ExportError.fileMissing
        }

        #if os(macOS)
        try await exportWithSavePanel(fileURL: fileURL, suggestedName: suggestedName)
        #else
        // On iOS / iPadOS / visionOS, ShareLink is preferred; Documents is a fallback.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destination = docs.appendingPathComponent(suggestedName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: fileURL, to: destination)
        } catch {
            throw ExportError.copyFailed(error.localizedDescription)
        }
        #endif
    }

    private func addToPhotoLibrary(fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photosDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
        } catch {
            throw ExportError.photosFailed(error.localizedDescription)
        }
    }

    #if os(macOS)
    @MainActor
    private func exportWithSavePanel(fileURL: URL, suggestedName: String) async throws {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.title = "Save Video"
        let response = panel.runModal()
        guard response == .OK, let destination = panel.url else {
            throw ExportError.saveCancelled
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: fileURL, to: destination)
        } catch {
            throw ExportError.copyFailed(error.localizedDescription)
        }
    }
    #endif
}
