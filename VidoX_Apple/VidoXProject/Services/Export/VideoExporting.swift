import Foundation

enum ExportError: LocalizedError, Sendable, Equatable {
    case fileMissing
    case photosDenied
    case photosFailed(String)
    case saveCancelled
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            "The video file is missing from disk."
        case .photosDenied:
            "Photos access was denied. Enable it in Settings to save videos."
        case .photosFailed(let message):
            message
        case .saveCancelled:
            "Save cancelled."
        case .copyFailed(let message):
            "Could not export the file: \(message)"
        }
    }
}

protocol VideoExporting: Sendable {
    func saveToPhotos(fileURL: URL) async throws
    func exportToUserChosenLocation(fileURL: URL, suggestedName: String) async throws
}
