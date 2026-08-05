import Foundation

/// Wire protocol for nearby VidoX library sync (no iCloud).
enum SyncWireMessage: Codable, Sendable {
    case hello(SyncHello)
    case offer(SyncVideoManifest)
    case delete(UUID)

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private enum MessageType: String, Codable {
        case hello, offer, delete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .hello:
            self = .hello(try container.decode(SyncHello.self, forKey: .payload))
        case .offer:
            self = .offer(try container.decode(SyncVideoManifest.self, forKey: .payload))
        case .delete:
            self = .delete(try container.decode(UUID.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let value):
            try container.encode(MessageType.hello, forKey: .type)
            try container.encode(value, forKey: .payload)
        case .offer(let value):
            try container.encode(MessageType.offer, forKey: .type)
            try container.encode(value, forKey: .payload)
        case .delete(let value):
            try container.encode(MessageType.delete, forKey: .type)
            try container.encode(value, forKey: .payload)
        }
    }
}

struct SyncHello: Codable, Sendable {
    var deviceName: String
    var videoIDs: [UUID]
    var deletedIDs: [UUID]
}

struct SyncVideoManifest: Codable, Sendable, Hashable {
    var id: UUID
    var title: String
    var author: String?
    var sourceURL: String
    var platformRaw: String
    var fileExtension: String
    var fileSize: Int64
    var downloadedAt: Date
    var isPinned: Bool
    var pinnedAt: Date?
    /// Resource name used with `MCSession.sendResource`.
    var resourceName: String
}

enum LocalSyncKeys {
    static let enabled = "vidox.localSync.enabled"
    static let deletedIDs = "vidox.localSync.deletedIDs"
    static let serviceType = "vidox-sync"
}
