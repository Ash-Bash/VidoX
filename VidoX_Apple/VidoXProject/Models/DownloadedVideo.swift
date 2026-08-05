import Foundation
import SwiftData

/// Persistent record of a video stored in the local library (app sandbox).
@Model
final class DownloadedVideo {
    var id: UUID
    var title: String
    var author: String?
    /// Original page or media URL the user pasted.
    var sourceURL: String
    /// `VideoPlatform.rawValue`
    var platformRaw: String
    var thumbnailPath: String?
    /// Relative filename under Application Support/Videos (legacy rows may still store an absolute path).
    var localFilePath: String
    var fileExtension: String
    var downloadedAt: Date
    var fileSize: Int64
    /// When `true`, the video appears in the Pins tab / sidebar section.
    var isPinned: Bool = false
    /// Used to order pinned items (most recently pinned first).
    var pinnedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        sourceURL: String,
        platform: VideoPlatform,
        thumbnailPath: String? = nil,
        localFilePath: String,
        fileExtension: String,
        downloadedAt: Date = .now,
        fileSize: Int64 = 0,
        isPinned: Bool = false,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceURL = sourceURL
        self.platformRaw = platform.rawValue
        self.thumbnailPath = thumbnailPath
        self.localFilePath = localFilePath
        self.fileExtension = fileExtension
        self.downloadedAt = downloadedAt
        self.fileSize = fileSize
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
    }

    var platform: VideoPlatform {
        VideoPlatform(rawValue: platformRaw) ?? .unknown
    }

    /// Resolved sandbox URL — safe across container UUID changes after rebuilds.
    var fileURL: URL {
        FileStorage.resolvedURL(forStoredPath: localFilePath)
    }

    var isFileAvailable: Bool {
        FileStorage.fileExists(atStoredPath: localFilePath)
    }

    var formattedFileSize: String {
        let bytes = isFileAvailable ? FileStorage.fileSize(atStoredPath: localFilePath) : fileSize
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func togglePinned() {
        if isPinned {
            isPinned = false
            pinnedAt = nil
        } else {
            isPinned = true
            pinnedAt = .now
        }
    }

    /// Rewrites absolute legacy paths to relative filenames and refreshes `fileSize` from disk.
    @discardableResult
    func repairStorageMetadata() -> Bool {
        let normalized = FileStorage.normalizedStoredPath(forStoredPath: localFilePath)
        var changed = false
        if normalized != localFilePath {
            localFilePath = normalized
            changed = true
        }
        if FileStorage.fileExists(atStoredPath: localFilePath) {
            let size = FileStorage.fileSize(atStoredPath: localFilePath)
            if size > 0, size != fileSize {
                fileSize = size
                changed = true
            }
        }
        return changed
    }
}
