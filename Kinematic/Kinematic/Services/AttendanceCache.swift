// AttendanceCache — disk-persisted offline queue for attendance check-in /
// check-out. Mirrors OrderCache from the distribution module. Each pending
// row carries a stable Idempotency-Key; on flush, the server returns the
// canonical record (replays return the original response, never duplicates).
//
// A row stays queued only while the failure is about getting through to the
// server (see AttendanceSyncPolicy). A punch the server refused is marked
// rejected and never sent again.

import Foundation
import Combine
import Network

struct PendingAttendance: Codable, Identifiable {
    let id: UUID
    let idempotencyKey: String
    let userKey: String
    let kind: String                 // "checkin" | "checkout"
    let lat: Double
    let lng: Double
    let selfieUrl: String?
    let battery: Int?
    let createdAt: Date
    var attempt: Int
    var lastError: String?
    var isSynced: Bool
    // What the live call sends besides the position, kept so a replay carries the same evidence. All optional
    // (and defaulted) so rows queued by an older build still load.
    var faceScore: Double? = nil
    var faceVerified: Bool? = nil
    var faceModelId: String? = nil
    var isMock: Bool? = nil
    var locationAccuracyM: Double? = nil
    /// Set when the server refused this punch (a 4xx, a "no"): it is never replayed. Nil while it can still go.
    var rejectedReason: String? = nil
}

@MainActor
final class AttendanceCache: ObservableObject {
    static let shared = AttendanceCache()

    @Published private(set) var rows: [PendingAttendance] = []

    private let queue = DispatchQueue(label: "com.kinematic.attendancecache", qos: .utility)
    private var file: URL { docs.appendingPathComponent("pending_attendance.json") }
    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Rows whose first send is still in flight in the foreground (`toggleAttendance`): a background flush
    /// must leave them alone rather than race the call that created them.
    private var inFlight = Set<UUID>()
    private var isFlushing = false
    private let pathMonitor = NWPathMonitor()

    /// How long a refused punch is kept on disk (for support) before it is pruned.
    private static let rejectedRetention: TimeInterval = 14 * 24 * 3600

    init() {
        load()
        startWatchingConnectivity()
    }

    private func load() {
        rows = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([PendingAttendance].self, from: $0) } ?? []
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        let url = file
        queue.async { try? data.write(to: url, options: .atomic) }
    }

    /// Flush the moment the network comes back (same NWPathMonitor idea as OfflineMutationQueue), as well as
    /// whenever the app returns to the foreground. Idle when nobody is signed in or nothing is queued.
    private func startWatchingConnectivity() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.flushIfSignedIn() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.kinematic.attendancecache.path", qos: .utility))
    }

    private func flushIfSignedIn() async {
        guard Session.isAuthenticated else { return }
        await flush()
    }

    static func userKey() -> String { String(Session.sharedToken.suffix(24)) }

    /// Enqueue an attendance event and return the row (with its idempotency
    /// key). Caller is responsible for kicking the flush.
    func enqueue(kind: String, lat: Double, lng: Double, selfieUrl: String?, battery: Int?,
                 isMock: Bool? = nil, locationAccuracyM: Double? = nil) -> PendingAttendance {
        var row = PendingAttendance(
            id: UUID(),
            idempotencyKey: "att-\(kind == "checkin" ? "ci" : "co")-\(UUID().uuidString)",
            userKey: Self.userKey(),
            kind: kind,
            lat: lat, lng: lng,
            selfieUrl: selfieUrl,
            battery: battery,
            createdAt: Date(),
            attempt: 0,
            lastError: nil,
            isSynced: false
        )
        row.isMock = isMock
        row.locationAccuracyM = locationAccuracyM
        rows.insert(row, at: 0)
        persist()
        return row
    }

    /// The foreground call for this row is about to run / has finished: keep the background flush off it meanwhile.
    func beginInline(_ id: UUID) { inFlight.insert(id) }
    func endInline(_ id: UUID) { inFlight.remove(id) }

    /// Record the on-device face match on a row (computed after the row was queued), so a replay carries it.
    func annotateFace(_ id: UUID, score: Double?, verified: Bool?, modelId: String?) {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i].faceScore = score
            rows[i].faceVerified = verified
            rows[i].faceModelId = modelId
            persist()
        }
    }

    func markSynced(_ id: UUID) {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i].isSynced = true
            persist()
        }
    }
    func recordError(_ id: UUID, error: String) {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i].attempt += 1
            rows[i].lastError = error
            persist()
        }
    }
    /// The server refused this punch (or it can never succeed as sent): stop sending it. The reason stays on
    /// the row for a while for support, then it is pruned.
    func markRejected(_ id: UUID, error: String) {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i].attempt += 1
            rows[i].lastError = error
            rows[i].rejectedReason = error
            persist()
        }
    }

    func pendingForCurrentUser() -> [PendingAttendance] {
        let key = Self.userKey()
        return rows.filter { !$0.isSynced && $0.rejectedReason == nil && $0.userKey == key }
    }

    func clearSynced() {
        rows.removeAll { $0.isSynced }
        persist()
    }

    /// Drop refused punches that have been kept long enough.
    private func pruneRejected(now: Date = Date()) {
        let before = rows.count
        rows.removeAll { $0.rejectedReason != nil && now.timeIntervalSince($0.createdAt) > Self.rejectedRetention }
        if rows.count != before { persist() }
    }

    /// Drain — sync each pending row through KinematicRepository.markAttendance, oldest first (a check-out
    /// must never go ahead of the check-in it follows).
    ///  - success: the row is synced.
    ///  - a failure to get through (offline, timeout, 408 / 429 / 5xx) or an expired sign-in: the error is
    ///    recorded, the row stays queued and the drain stops — the rest would fail the same way, and order matters.
    ///  - anything else (the server refused the punch): the row is marked rejected and never sent again; the
    ///    drain carries on with the next one.
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        pruneRejected()

        let pending = AttendanceSyncPolicy.drainOrder(pendingForCurrentUser().filter { !inFlight.contains($0.id) })
        for row in pending {
            let result = await KinematicRepository.shared.markAttendance(
                isCheckIn: row.kind == "checkin",
                lat: row.lat, lng: row.lng,
                selfieUrl: row.selfieUrl,
                battery: row.battery,
                faceScore: row.faceScore, faceVerified: row.faceVerified, faceModelId: row.faceModelId,
                isMock: row.isMock, locationAccuracyM: row.locationAccuracyM,
                idempotencyKey: row.idempotencyKey
            )
            if result.success { markSynced(row.id); continue }
            let reason = result.message ?? "Unknown error"
            switch AttendanceSyncPolicy.queueAction(for: result.failure ?? .rejected) {
            case .keepAndStop:
                recordError(row.id, error: reason)
                return
            case .drop:
                markRejected(row.id, error: reason)
            }
        }
    }
}
