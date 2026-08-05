import Foundation
import SwiftData

/// One-shot repair for library rows that stored absolute sandbox paths.
/// iOS can change the container UUID across reinstalls/rebuilds; relative paths stay valid.
enum LibraryStorageMigrator {
    static func repairAll(in context: ModelContext) {
        let descriptor = FetchDescriptor<DownloadedVideo>()
        guard let videos = try? context.fetch(descriptor) else { return }

        var changed = false
        for video in videos {
            if video.repairStorageMetadata() {
                changed = true
            }
        }

        if changed {
            try? context.save()
        }
    }
}
