import Foundation
import MultipeerConnectivity
import SwiftData
import Observation

#if canImport(UIKit)
import UIKit
#endif

/// Nearby library sync over Multipeer Connectivity (Wi‑Fi / peer-to-peer).
/// Downloads queue implicitly via inventory exchange; deletes use local tombstones.
/// Sync runs when another VidoX device is nearby — no iCloud.
@Observable
@MainActor
final class LocalSyncService: NSObject {
    static let shared = LocalSyncService()

    var isEnabled: Bool = LocalSyncStore.isEnabled {
        didSet {
            LocalSyncStore.isEnabled = isEnabled
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    var statusText: String = "Off"
    var connectedPeerName: String?
    var lastError: String?
    var isSyncing: Bool = false
    var discoveredPeerCount: Int = 0

    /// 0...1 aggregate transfer progress while files move; `nil` when idle.
    var transferFraction: Double?
    /// Short label for the active transfer (e.g. “Sending Title…”).
    var transferDetail: String = ""
    /// Number of file transfers currently in flight (send + receive).
    var activeTransferCount: Int = 0

    /// True only while bytes are moving or a sync wave is actively transferring.
    var hasTransferActivity: Bool {
        isEnabled && (activeTransferCount > 0 || transferFraction != nil)
    }

    private var modelContainer: ModelContainer?
    private var peerID: MCPeerID!
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// Manifests waiting for an incoming resource file.
    private var pendingIncoming: [String: SyncVideoManifest] = [:]
    /// Peers we have already greeted in this connection.
    private var greetedPeers: Set<MCPeerID> = []
    private var isStarted = false

    private var trackedProgresses: [ObjectIdentifier: Progress] = [:]
    private var progressObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var progressLabels: [ObjectIdentifier: String] = [:]

    private override init() {
        super.init()
        peerID = MCPeerID(displayName: Self.makeDisplayName())
    }

    func configure(container: ModelContainer) {
        modelContainer = container
    }

    func startIfEnabled() {
        guard isEnabled else {
            statusText = "Off"
            return
        }
        start()
    }

    func start() {
        guard modelContainer != nil else {
            statusText = "Waiting for library…"
            return
        }
        guard !isStarted else { return }
        isStarted = true
        lastError = nil

        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["app": "VidoX"],
            serviceType: LocalSyncKeys.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: LocalSyncKeys.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        statusText = "Looking for nearby devices…"
    }

    func stop() {
        isStarted = false
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        greetedPeers.removeAll()
        pendingIncoming.removeAll()
        clearAllProgressTracking()
        connectedPeerName = nil
        discoveredPeerCount = 0
        isSyncing = false
        statusText = "Off"
    }

    /// Call after a successful local download/import.
    func noteUpserted(videoID: UUID) {
        LocalSyncStore.clearDeleted(id: videoID)
        // If already connected, push this single item soon.
        Task { await pushVideoIfConnected(id: videoID) }
    }

    /// Call after removing a library row locally (or just before).
    func noteDeleted(videoID: UUID) {
        LocalSyncStore.noteDeleted(id: videoID)
        dropPendingIncoming(for: videoID)
        // Push immediately when connected; otherwise tombstone rides along in the next hello.
        sendDelete(videoID)
        if let name = connectedPeerName {
            statusText = "Connected to \(name) · delete synced"
        }
    }

    // MARK: - Private

    private static func makeDisplayName() -> String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #elseif canImport(UIKit)
        UIDevice.current.name
        #else
        "VidoX"
        #endif
    }

    private var libraryContext: ModelContext? {
        modelContainer?.mainContext
    }

    private func currentInventory() -> (ids: [UUID], videos: [DownloadedVideo]) {
        guard let context = libraryContext else { return ([], []) }
        let videos = (try? context.fetch(FetchDescriptor<DownloadedVideo>())) ?? []
        return (videos.map(\.id), videos)
    }

    private func sendHello(to peer: MCPeerID) {
        guard let session else { return }
        let inventory = currentInventory()
        let hello = SyncHello(
            deviceName: peerID.displayName,
            videoIDs: inventory.ids,
            deletedIDs: LocalSyncStore.deletedIDs
        )
        send(.hello(hello), to: [peer], in: session)
    }

    private func handleHello(_ hello: SyncHello, from peer: MCPeerID) {
        connectedPeerName = hello.deviceName
        statusText = "Connected to \(hello.deviceName)"
        isSyncing = true

        let local = currentInventory()
        let localIDSet = Set(local.ids)
        let remoteIDSet = Set(hello.videoIDs)
        let remoteDeleted = Set(hello.deletedIDs)
        let localDeleted = Set(LocalSyncStore.deletedIDs)

        // 1) Apply their deletes first so we never re-offer those files.
        var removedCount = 0
        for id in remoteDeleted where localIDSet.contains(id) {
            deleteLocalVideo(id: id, recordTombstone: true)
            removedCount += 1
        }

        // 2) Tell them about every local tombstone they still have (and broadcast deletes).
        for id in localDeleted where remoteIDSet.contains(id) {
            sendDelete(id)
        }

        // 3) Refresh inventory after deletes, then send only non-tombstoned missing videos.
        let refreshed = currentInventory()
        let toSend = refreshed.videos.filter { video in
            !remoteIDSet.contains(video.id)
                && !remoteDeleted.contains(video.id)
                && !localDeleted.contains(video.id)
                && video.isFileAvailable
        }
        if toSend.isEmpty {
            isSyncing = false
            if removedCount > 0 {
                statusText = "Connected to \(hello.deviceName) · removed \(removedCount)"
            } else {
                statusText = "Connected to \(hello.deviceName) · up to date"
            }
        } else {
            statusText = "Connected to \(hello.deviceName) · sending \(toSend.count)…"
            for video in toSend {
                sendOffer(for: video, to: peer)
            }
        }
    }

    private func sendOffer(for video: DownloadedVideo, to peer: MCPeerID) {
        guard let session else { return }
        // Never push something we (or a peer) already deleted.
        guard !LocalSyncStore.deletedIDs.contains(video.id) else { return }

        let fileURL = video.fileURL
        let resourceName = "\(video.id.uuidString).\(video.fileExtension)"
        let manifest = SyncVideoManifest(
            id: video.id,
            title: video.title,
            author: video.author,
            sourceURL: video.sourceURL,
            platformRaw: video.platformRaw,
            fileExtension: video.fileExtension,
            fileSize: video.fileSize,
            downloadedAt: video.downloadedAt,
            isPinned: video.isPinned,
            pinnedAt: video.pinnedAt,
            resourceName: resourceName
        )

        send(.offer(manifest), to: [peer], in: session)

        let label = "Sending \(video.title)"
        let progress = session.sendResource(at: fileURL, withName: resourceName, toPeer: peer) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.refreshAggregateProgress()
                if let error {
                    self.lastError = error.localizedDescription
                    self.statusText = "Transfer failed"
                } else if !self.hasTransferActivity, let name = self.connectedPeerName {
                    self.statusText = "Connected to \(name)"
                }
            }
        }
        if let progress {
            trackProgress(progress, label: label)
        } else {
            // Immediate completion / failure path — still pulse activity briefly.
            isSyncing = true
            transferDetail = label
            transferFraction = 0
        }
    }

    private func pushVideoIfConnected(id: UUID) async {
        guard let session, let peer = session.connectedPeers.first else { return }
        guard !LocalSyncStore.deletedIDs.contains(id) else { return }
        guard let context = libraryContext else { return }
        let targetID = id
        var descriptor = FetchDescriptor<DownloadedVideo>(predicate: #Predicate { $0.id == targetID })
        descriptor.fetchLimit = 1
        guard let video = try? context.fetch(descriptor).first, video.isFileAvailable else { return }
        sendOffer(for: video, to: peer)
    }

    private func sendDelete(_ id: UUID) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        send(.delete(id), to: session.connectedPeers, in: session)
    }

    private func dropPendingIncoming(for id: UUID) {
        let keys = pendingIncoming.compactMap { key, manifest in
            manifest.id == id ? key : nil
        }
        for key in keys {
            pendingIncoming.removeValue(forKey: key)
        }
    }

    private func send(_ message: SyncWireMessage, to peers: [MCPeerID], in session: MCSession) {
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: peers, with: .reliable)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handleOffer(_ manifest: SyncVideoManifest) {
        // Ignore if we already have it.
        let local = currentInventory()
        if local.ids.contains(manifest.id) { return }

        // If we deleted this item, refuse the file and remind the peer to delete too.
        if LocalSyncStore.deletedIDs.contains(manifest.id) {
            sendDelete(manifest.id)
            return
        }

        pendingIncoming[manifest.resourceName] = manifest
        statusText = "Receiving \(manifest.title)…"
        transferDetail = "Receiving \(manifest.title)"
        isSyncing = true
    }

    private func trackProgress(_ progress: Progress, label: String) {
        let key = ObjectIdentifier(progress)
        trackedProgresses[key] = progress
        progressLabels[key] = label
        transferDetail = label
        isSyncing = true

        let observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshAggregateProgress()
            }
        }
        progressObservations[key] = observation
        refreshAggregateProgress()
    }

    private func refreshAggregateProgress() {
        let finishedKeys = trackedProgresses.compactMap { key, progress -> ObjectIdentifier? in
            (progress.isFinished || progress.isCancelled) ? key : nil
        }
        for key in finishedKeys {
            progressObservations[key]?.invalidate()
            progressObservations.removeValue(forKey: key)
            trackedProgresses.removeValue(forKey: key)
            progressLabels.removeValue(forKey: key)
        }

        let active = trackedProgresses.values.filter { !$0.isFinished && !$0.isCancelled }
        activeTransferCount = active.count

        if active.isEmpty {
            transferFraction = nil
            transferDetail = ""
            isSyncing = false
            if let name = connectedPeerName {
                statusText = "Connected to \(name)"
            }
            return
        }

        isSyncing = true
        let totalUnit = active.reduce(0.0) { partial, progress in
            partial + max(progress.fractionCompleted, 0)
        }
        transferFraction = min(max(totalUnit / Double(active.count), 0), 1)
        if let firstKey = trackedProgresses.first(where: { !$0.value.isFinished && !$0.value.isCancelled })?.key,
           let label = progressLabels[firstKey] {
            transferDetail = active.count > 1
                ? "\(label) · \(active.count) files"
                : label
        }
    }

    private func clearAllProgressTracking() {
        for observation in progressObservations.values {
            observation.invalidate()
        }
        progressObservations.removeAll()
        trackedProgresses.removeAll()
        progressLabels.removeAll()
        activeTransferCount = 0
        transferFraction = nil
        transferDetail = ""
    }

    private func importResource(localURL: URL, manifest: SyncVideoManifest) {
        // Never resurrect a deleted item if a late transfer still arrives.
        if LocalSyncStore.deletedIDs.contains(manifest.id) {
            sendDelete(manifest.id)
            refreshAggregateProgress()
            return
        }

        guard let context = libraryContext else { return }

        // Skip duplicates.
        let targetID = manifest.id
        var descriptor = FetchDescriptor<DownloadedVideo>(predicate: #Predicate<DownloadedVideo> { $0.id == targetID })
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) != nil {
            return
        }

        let destination = FileStorage.makeVideoFileURL(
            preferredName: manifest.title,
            fileExtension: manifest.fileExtension
        )
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: localURL, to: destination)
            let size = FileStorage.fileSize(at: destination)
            let record = DownloadedVideo(
                id: manifest.id,
                title: manifest.title,
                author: manifest.author,
                sourceURL: manifest.sourceURL,
                platform: VideoPlatform(rawValue: manifest.platformRaw) ?? .unknown,
                localFilePath: FileStorage.storedPath(for: destination),
                fileExtension: manifest.fileExtension,
                downloadedAt: manifest.downloadedAt,
                fileSize: size > 0 ? size : manifest.fileSize,
                isPinned: manifest.isPinned,
                pinnedAt: manifest.pinnedAt
            )
            context.insert(record)
            try context.save()
            LocalSyncStore.clearDeleted(id: manifest.id)
            statusText = connectedPeerName.map { "Connected to \($0) · imported \(manifest.title)" }
                ?? "Imported \(manifest.title)"
        } catch {
            lastError = error.localizedDescription
            statusText = "Import failed"
        }
        refreshAggregateProgress()
    }

    private func manifestFallback(fromResourceName resourceName: String) -> SyncVideoManifest? {
        // resourceName format: "{uuid}.{ext}"
        let ns = resourceName as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        guard let id = UUID(uuidString: stem), !ext.isEmpty else { return nil }
        return SyncVideoManifest(
            id: id,
            title: "Synced video",
            author: nil,
            sourceURL: "",
            platformRaw: VideoPlatform.unknown.rawValue,
            fileExtension: ext,
            fileSize: 0,
            downloadedAt: .now,
            isPinned: false,
            pinnedAt: nil,
            resourceName: resourceName
        )
    }

    private func deleteLocalVideo(id: UUID, recordTombstone: Bool) {
        dropPendingIncoming(for: id)
        if recordTombstone {
            LocalSyncStore.noteDeleted(id: id)
        }

        guard let context = libraryContext else { return }
        let targetID = id
        var descriptor = FetchDescriptor<DownloadedVideo>(predicate: #Predicate { $0.id == targetID })
        descriptor.fetchLimit = 1
        guard let video = try? context.fetch(descriptor).first else { return }
        FileStorage.removeFile(atStoredPath: video.localFilePath)
        if let thumb = video.thumbnailPath {
            FileStorage.removeFile(atStoredPath: thumb)
        }
        context.delete(video)
        try? context.save()
    }

    private func handleRemoteDelete(_ id: UUID) {
        deleteLocalVideo(id: id, recordTombstone: true)
        if let name = connectedPeerName {
            statusText = "Connected to \(name) · removed synced item"
        }
    }
}

// MARK: - MCSessionDelegate

extension LocalSyncService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.connectedPeerName = peerID.displayName
                self.statusText = "Connected to \(peerID.displayName)"
                if !self.greetedPeers.contains(peerID) {
                    self.greetedPeers.insert(peerID)
                    self.sendHello(to: peerID)
                }
            case .connecting:
                self.statusText = "Connecting to \(peerID.displayName)…"
            case .notConnected:
                self.greetedPeers.remove(peerID)
                if self.session?.connectedPeers.isEmpty != false {
                    self.connectedPeerName = nil
                    self.statusText = self.isEnabled ? "Looking for nearby devices…" : "Off"
                }
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let message = try JSONDecoder().decode(SyncWireMessage.self, from: data)
                switch message {
                case .hello(let hello):
                    self.handleHello(hello, from: peerID)
                case .offer(let manifest):
                    self.handleOffer(manifest)
                case .delete(let id):
                    self.handleRemoteDelete(id)
                }
            } catch {
                self.lastError = "Bad sync message"
            }
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        Task { @MainActor in
            let title = self.pendingIncoming[resourceName]?.title
            let label = title.map { "Receiving \($0)" } ?? "Receiving file…"
            self.statusText = label
            self.trackProgress(progress, label: label)
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        Task { @MainActor in
            // Drop matching progress entries for this resource label if still tracked.
            self.refreshAggregateProgress()

            if let error {
                self.lastError = error.localizedDescription
                self.pendingIncoming.removeValue(forKey: resourceName)
                self.refreshAggregateProgress()
                return
            }
            guard let localURL else {
                self.refreshAggregateProgress()
                return
            }
            let manifest = self.pendingIncoming.removeValue(forKey: resourceName)
                ?? self.manifestFallback(fromResourceName: resourceName)
            guard let manifest else {
                self.lastError = "Received a file without metadata"
                self.refreshAggregateProgress()
                return
            }
            self.importResource(localURL: localURL, manifest: manifest)
            self.refreshAggregateProgress()
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        certificateHandler(true)
    }
}

// MARK: - Advertiser

extension LocalSyncService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor in
            self.lastError = Self.friendlyBonjourError(error)
            self.statusText = "Couldn’t advertise"
        }
    }
}

// MARK: - Browser

extension LocalSyncService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            self.discoveredPeerCount += 1
            guard let session = self.session else { return }
            // Avoid inviting ourselves / already connected.
            guard !session.connectedPeers.contains(peerID) else { return }
            // Only one side invites to reduce double-handshake races.
            guard self.peerID.displayName < peerID.displayName else { return }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
            self.statusText = "Inviting \(peerID.displayName)…"
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredPeerCount = max(0, self.discoveredPeerCount - 1)
        }
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        Task { @MainActor in
            self.lastError = Self.friendlyBonjourError(error)
            self.statusText = "Couldn’t browse"
        }
    }
}

extension LocalSyncService {
    fileprivate static func friendlyBonjourError(_ error: Error) -> String {
        let ns = error as NSError
        // -72008 = missing Bonjour / local-network Info.plist configuration
        if ns.domain == "NSNetServicesErrorDomain", ns.code == -72008 {
            return "Local Network / Bonjour isn’t configured. Delete the app, rebuild, and allow Local Network when asked."
        }
        return error.localizedDescription
    }
}
