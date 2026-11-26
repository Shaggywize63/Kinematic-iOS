//
//  OfflinePingCache.swift
//  Kinematic
//
//  Disk-persisted OFFLINE LOCATION-PING queue. When a live heartbeat can't be uploaded (the rep is in a
//  no-signal zone — a basement, a rural route, a warehouse), the good GPS fix is parked here instead of
//  being dropped, and replayed on the next successful heartbeat (and the moment the network returns)
//  carrying its original capture time, so the server backfills the trail at the right place.
//
//  Deliberately separate from AttendanceCache / OfflineMutationQueue: pings are high-frequency, carry no
//  selfie / idempotency key / ordering, and have their own age + size pruning (PingQueuePolicy). Mirrors
//  the Android implementation (OfflinePing + PingDao + PingQueuePolicy).
//

import Foundation
import Network

/// One GPS fix that failed to upload. `userKey` scopes it to the rep (so a shared phone never replays
/// one rep's trail under another's session). Replay order is by `capturedAt` (oldest first).
struct PendingPing: Codable, Identifiable {
    let id: UUID
    var userKey: String
    let lat: Double
    let lng: Double
    let battery: Int?
    let capturedAt: Date
    let accuracyM: Double?
    let isMock: Bool
    let precise: Bool?
    let createdAt: Date
}

/// The result of one replay attempt — drives whether the row is dequeued or kept.
enum PingSendResult {
    /// The server has it (2xx — a stored backfill or an ACK-and-drop): remove the row.
    case synced
    /// Not delivered (a connectivity failure): keep the row and stop this flush pass.
    case held
    /// The server gave a final "no" (4xx / success:false): remove the row so it can't loop forever.
    case rejected
}

@MainActor
final class OfflinePingCache {
    static let shared = OfflinePingCache()

    private(set) var rows: [PendingPing] = []
    private var isOnline = true
    private var isFlushing = false

    private let ioQueue = DispatchQueue(label: "com.kinematic.pingcache", qos: .utility)
    private let pathMonitor = NWPathMonitor()
    private var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first! }
    private var file: URL { docs.appendingPathComponent("offline_pings.json") }

    init() {
        load()
        startWatchingConnectivity()
    }

    // MARK: persistence

    private func load() {
        rows = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([PendingPing].self, from: $0) } ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        let url = file
        ioQueue.async { try? data.write(to: url, options: .atomic) }
    }

    /// The signed-in rep's id — the queue's owner key. Empty when unknown (won't happen mid-shift).
    private func currentUserKey() -> String {
        Session.currentUser?.id ?? ""
    }

    // MARK: connectivity-triggered flush

    private func startWatchingConnectivity() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = satisfied
                if satisfied { await self?.flush() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.kinematic.pingcache.path", qos: .utility))
    }

    // MARK: enqueue

    /// Park a fix that failed to upload (the caller has already checked `PingQueuePolicy.shouldEnqueue`).
    func enqueue(lat: Double, lng: Double, battery: Int?, capturedAt: Date,
                 accuracyM: Double?, isMock: Bool, precise: Bool?) {
        let key = currentUserKey()
        rows.append(PendingPing(
            id: UUID(), userKey: key, lat: lat, lng: lng, battery: battery,
            capturedAt: capturedAt, accuracyM: accuracyM, isMock: isMock, precise: precise,
            createdAt: Date()
        ))
        trim(now: Date())
        persist()
    }

    /// Drop stale rows (older than the honoured window) and keep at most `maxQueue` of this rep's rows.
    private func trim(now: Date) {
        let cutoff = PingQueuePolicy.pruneCutoff(now: now)
        rows.removeAll { $0.capturedAt < cutoff }
        let mineNewestFirst = rows
            .enumerated()
            .filter { $0.element.userKey == currentUserKey() }
            .sorted { $0.element.capturedAt > $1.element.capturedAt }
        if mineNewestFirst.count > PingQueuePolicy.maxQueue {
            let doomed = Set(mineNewestFirst.dropFirst(PingQueuePolicy.maxQueue).map { $0.element.id })
            rows.removeAll { doomed.contains($0.id) }
        }
    }

    // MARK: flush

    /// Replay the queue oldest-first on reconnect (connectivity proven). Prunes stale rows first; stops
    /// at the first connectivity failure (still patchy) and keeps the rest; drops a server-refused row.
    func flush() async {
        guard !isFlushing, Session.isAuthenticated else { return }
        isFlushing = true
        defer { isFlushing = false }

        let now = Date()
        trim(now: now)
        persist()

        let key = currentUserKey()
        let batch = rows
            .filter { $0.userKey == key }
            .sorted { $0.capturedAt < $1.capturedAt }
            .prefix(PingQueuePolicy.flushBatch)

        for ping in batch {
            let result = await KinematicRepository.shared.sendBackfillPing(
                lat: ping.lat, lng: ping.lng, battery: ping.battery,
                capturedAtIso: PingQueuePolicy.formatCapturedAt(ping.capturedAt),
                accuracyM: ping.accuracyM, isMock: ping.isMock, precise: ping.precise
            )
            switch result {
            case .synced, .rejected:
                rows.removeAll { $0.id == ping.id }
                persist()
            case .held:
                return // still offline — keep this row and the rest for next time
            }
        }
    }
}
