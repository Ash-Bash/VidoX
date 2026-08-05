import Foundation

/// Manages on-disk locations for downloaded videos and optional thumbnails.
/// All downloads stay inside the app sandbox (Application Support) until the user
/// explicitly exports a copy to Photos, Files, or another location.
///
/// Library records store **relative** filenames (or legacy absolute paths). Always
/// resolve through `resolvedURL(forStoredPath:)` so rebuilds that change the
/// container UUID do not orphan files that are still in the Videos folder.
enum FileStorage {
    private static let videosFolderName = "Videos"
    private static let thumbnailsFolderName = "Thumbnails"

    /// Application Support / Videos — primary store for downloaded media.
    static var videosDirectory: URL {
        let base = applicationSupportDirectory
        let url = base.appendingPathComponent(videosFolderName, isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }

    static var thumbnailsDirectory: URL {
        let base = applicationSupportDirectory
        let url = base.appendingPathComponent(thumbnailsFolderName, isDirectory: true)
        ensureDirectoryExists(at: url)
        return url
    }

    private static var applicationSupportDirectory: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = urls[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "VidoX"
        let appFolder = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        ensureDirectoryExists(at: appFolder)
        return appFolder
    }

    /// Creates a unique destination path for a new download.
    static func makeVideoFileURL(preferredName: String, fileExtension: String) -> URL {
        let safeBase = preferredName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safeBase.isEmpty ? UUID().uuidString : String(safeBase.prefix(80))
        let ext = fileExtension.hasPrefix(".") ? String(fileExtension.dropFirst()) : fileExtension
        let filename = "\(base)-\(UUID().uuidString.prefix(8)).\(ext)"
        return videosDirectory.appendingPathComponent(filename)
    }

    /// Value to persist on `DownloadedVideo.localFilePath` (filename relative to Videos).
    static func storedPath(for fileURL: URL) -> String {
        let videosPath = videosDirectory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(videosPath + "/") {
            return String(filePath.dropFirst(videosPath.count + 1))
        }
        return fileURL.lastPathComponent
    }

    /// Resolves a stored relative or legacy absolute path to a usable file URL.
    /// Heals stale absolute paths after the app container UUID changes.
    static func resolvedURL(forStoredPath storedPath: String) -> URL {
        // Preferred: relative filename / relative path under Videos.
        if !storedPath.hasPrefix("/") {
            return videosDirectory.appendingPathComponent(storedPath)
        }

        let absolute = URL(fileURLWithPath: storedPath)
        if FileManager.default.fileExists(atPath: absolute.path) {
            return absolute
        }

        // Legacy absolute path from an old container — recover by filename.
        let candidate = videosDirectory.appendingPathComponent(absolute.lastPathComponent)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        // Last resort: scan Videos for a unique suffix match (handles renamed containers
        // where only the UUID segment of the absolute path changed).
        if let match = findVideoMatchingLegacyPath(storedPath) {
            return match
        }

        return absolute
    }

    /// Relative path to persist after healing, when possible.
    static func normalizedStoredPath(forStoredPath path: String) -> String {
        let resolved = resolvedURL(forStoredPath: path)
        if FileManager.default.fileExists(atPath: resolved.path) {
            return storedPath(for: resolved)
        }
        if !path.hasPrefix("/") {
            return path
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    static func fileExists(atStoredPath storedPath: String) -> Bool {
        FileManager.default.fileExists(atPath: resolvedURL(forStoredPath: storedPath).path)
    }

    static func removeFile(atStoredPath storedPath: String) {
        let url = resolvedURL(forStoredPath: storedPath)
        try? FileManager.default.removeItem(at: url)
    }

    /// Backward-compatible absolute-path delete.
    static func removeFile(at path: String) {
        removeFile(atStoredPath: path)
    }

    static func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    static func fileSize(atStoredPath storedPath: String) -> Int64 {
        fileSize(at: resolvedURL(forStoredPath: storedPath))
    }

    /// Bytes actually present in the Videos directory (not SwiftData metadata).
    static func videosDirectoryByteCount() -> Int64 {
        let directory = videosDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    private static func findVideoMatchingLegacyPath(_ storedPath: String) -> URL? {
        let filename = URL(fileURLWithPath: storedPath).lastPathComponent
        guard !filename.isEmpty else { return nil }

        // Match exact filename first.
        let exact = videosDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: exact.path) {
            return exact
        }

        // Filename format is `{title}-{8-char-uuid}.{ext}` — match the UUID stem when possible.
        let stem = (filename as NSString).deletingPathExtension
        let suffix = stem.split(separator: "-").last.map(String.init) ?? ""
        guard suffix.count == 8 else { return nil }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: videosDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        let matches = contents.filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            return name.hasSuffix("-\(suffix)") || name.hasSuffix(suffix)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func ensureDirectoryExists(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
