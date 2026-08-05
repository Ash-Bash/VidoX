import Foundation

/// Persists delete tombstones so a video removed on one device is not pulled back later.
enum LocalSyncStore {
    private static let maxTombstones = 500

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: LocalSyncKeys.enabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: LocalSyncKeys.enabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: LocalSyncKeys.enabled)
        }
    }

    static var deletedIDs: [UUID] {
        guard let raw = UserDefaults.standard.array(forKey: LocalSyncKeys.deletedIDs) as? [String] else {
            return []
        }
        return raw.compactMap(UUID.init(uuidString:))
    }

    static func noteDeleted(id: UUID) {
        var ids = deletedIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        if ids.count > maxTombstones {
            ids = Array(ids.prefix(maxTombstones))
        }
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: LocalSyncKeys.deletedIDs)
    }

    static func clearDeleted(id: UUID) {
        let ids = deletedIDs.filter { $0 != id }
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: LocalSyncKeys.deletedIDs)
    }
}
