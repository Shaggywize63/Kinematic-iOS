// AttendanceCache — disk-persisted offline queue for attendance check-in /
// check-out. Mirrors OrderCache from the distribution module. Each pending
// row carries a stable Idempotency-Key; on flush, the server returns the
// canonical record (replays return the original response, never duplicates).
//
// A row stays queued only while the failure is about getting through to the
// server (see AttendanceSyncPolicy). A punch the server refused is marked
// rejected and never sent again.
//
// Two kinds of row live here:
//   • the rows this queue has always held: the selfie was uploaded BEFORE the row was needed, the server stamps the
//     punch with the time it ARRIVES, and nothing about the row changed;
//   • offline-capable rows (`capturedAt` set) — written ONLY for a client whose attendance rules say
//     `allow_offline_checkin: true` (see OfflinePunch.swift): the row carries the real capture time and attendance
//     day, the selfie waits on the phone until it can be uploaded, the replay sends `captured_at` + the same
//     Idempotency-Key and the same body every time, a check-out never goes ahead of its check-in.

import Foundation
import Combine
import Network

struct PendingAttendance: Codable, Identifiable {
    let id: UUID
    let idempotencyKey: String
    /// Who queued it: "u:<user id>" — or, on rows queued by older builds, a token suffix (see QueueOwnership).
    var userKey: String
    let kind: String                 // "checkin" | "checkout"
    let lat: Double
    let lng: Double
    var selfieUrl: String?
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
    /// The answer to "How are you travelling today?" that rode with this check-in (only for a client whose
    /// `track_transport_mode` rule is on), so a replay carries the same value.
    var transportMode: String? = nil
    // Offline-capable punches only (attendance rule allow_offline_checkin); nil on every other row.
    /// The real capture instant — becomes `captured_at`. A row with this set is an offline-capable row.
    var capturedAt: Date? = nil
    /// The India day (`yyyy-MM-dd`) the punch belongs to; sent as `?date=` when it is not today.
    var attendanceDate: String? = nil
    /// Name of the selfie JPEG kept in app-private storage, not yet uploaded.
    var photoFile: String? = nil
    /// A selfie is demanded for this punch (decides what to do if the photo is lost or cannot upload).
    var selfieRequired: Bool? = nil
    /// The rep has read the notice about a refused punch.
    var dismissed: Bool? = nil
}

extension PendingAttendance: QueueOwned {}

@MainActor
final class AttendanceCache: ObservableObject {
    static let shared = AttendanceCache()

    @Published private(set) var rows: [PendingAttendance] = []
    /// Best-effort "the phone has a network path" (from the same monitor that triggers the flush). True until the
    /// monitor says otherwise.
    @Published private(set) var isOnline: Bool = true

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
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = satisfied
                if satisfied { await self?.flushIfSignedIn() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.kinematic.attendancecache.path", qos: .utility))
    }

    private func flushIfSignedIn() async {
        guard Session.isAuthenticated else { return }
        await flush()
    }

    /// The signed-in identity. Punches orphaned by a token refresh are only adopted if they are recent
    /// (see `AttendanceSyncPolicy.legacyAdoptionWindow`).
    private static func identity() -> QueueOwnership.Identity {
        QueueOwnership.currentIdentity(adoptionWindow: AttendanceSyncPolicy.legacyAdoptionWindow)
    }

    /// Move rows queued by older builds (keyed by an access-token suffix that has since rotated) onto the
    /// stable user key, wherever it is provable they are the signed-in user's. Nothing is removed. Cheap and
    /// idempotent: runs before every send and every new row.
    private func adoptLegacyRows() {
        var copy = rows    // assign only when something moved, so a no-op never notifies observers
        if QueueOwnership.migrate(&copy, identity: Self.identity()) > 0 { rows = copy; persist() }
    }

    /// Enqueue an attendance event and return the row (with its idempotency
    /// key). Caller is responsible for kicking the flush.
    ///
    /// `transportMode` rides with a check-in of a client that asks "How are you travelling today?". The `capturedAt` /
    /// `attendanceDate` / `photoFile` / `selfieRequired` group is for an OFFLINE-CAPABLE punch only (a client with
    /// `allow_offline_checkin`); leave it out and the row is exactly the one this queue always wrote.
    func enqueue(kind: String, lat: Double, lng: Double, selfieUrl: String?, battery: Int?,
                 isMock: Bool? = nil, locationAccuracyM: Double? = nil,
                 transportMode: String? = nil,
                 capturedAt: Date? = nil, attendanceDate: String? = nil,
                 photoFile: String? = nil, selfieRequired: Bool? = nil) -> PendingAttendance {
        adoptLegacyRows()
        var row = PendingAttendance(
            id: UUID(),
            idempotencyKey: "att-\(kind == "checkin" ? "ci" : "co")-\(UUID().uuidString)",
            userKey: QueueOwnership.keyForNewRow(Self.identity()),
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
        row.transportMode = transportMode
        row.capturedAt = capturedAt
        row.attendanceDate = attendanceDate
        row.photoFile = photoFile
        row.selfieRequired = selfieRequired
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

    /// Take a row out of the queue altogether (an inline attempt the server refused is not "saved": nothing remains).
    func remove(_ id: UUID) {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            let photo = rows[i].photoFile
            rows.remove(at: i)
            persist()
            deletePhoto(photo)
        }
    }

    func pendingForCurrentUser() -> [PendingAttendance] {
        let who = Self.identity()
        return rows.filter {
            !$0.isSynced && $0.rejectedReason == nil
                && QueueOwnership.owns(rowKey: $0.userKey, createdAt: $0.createdAt, identity: who)
        }
    }

    func clearSynced() {
        rows.removeAll { $0.isSynced }
        persist()
    }

    /// Drop refused punches that have been kept long enough.
    private func pruneRejected(now: Date = Date()) {
        let before = rows.count
        let doomed = rows.filter { $0.rejectedReason != nil && now.timeIntervalSince($0.createdAt) > Self.rejectedRetention }
        rows.removeAll { $0.rejectedReason != nil && now.timeIntervalSince($0.createdAt) > Self.rejectedRetention }
        for r in doomed { deletePhoto(r.photoFile) }
        if rows.count != before { persist() }
    }

    // MARK: - Offline-capable punches: what the screens read

    /// The signed-in user's offline-capable punches that have not reached the server: waiting ones and refused ones the
    /// rep has not dismissed yet. Empty for a client that never queued one — so the screens are untouched.
    func punchesForCurrentUser() -> [OfflinePunchState.PendingPunch] {
        // Nothing offline-capable in the queue (every client that never opted in): no need to look up who is signed in.
        if !rows.contains(where: { $0.capturedAt != nil && !$0.isSynced }) { return [] }
        let who = Self.identity()
        var out: [OfflinePunchState.PendingPunch] = []
        for r in rows {
            if r.isSynced || r.dismissed == true { continue }
            guard let captured = r.capturedAt, let kind = OfflinePunch.Kind(rawValue: r.kind) else { continue }
            if !QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: who) { continue }
            let day: String = r.attendanceDate ?? OfflinePunch.istDate(captured)
            out.append(OfflinePunchState.PendingPunch(
                id: r.id.uuidString, kind: kind, capturedAt: captured, queuedAt: r.createdAt,
                attendanceDate: day, rejected: r.rejectedReason != nil, error: r.rejectedReason,
                transportMode: kind == .checkIn ? r.transportMode : nil))
        }
        return out
    }

    /// The rep has read the notice about the punches the server refused: hide them (their photos were already deleted).
    func dismissRefused() {
        let who = Self.identity()
        var changed = false
        for i in rows.indices {
            let r = rows[i]
            if r.capturedAt != nil, r.rejectedReason != nil, r.dismissed != true,
               QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: who) {
                rows[i].dismissed = true
                changed = true
            }
        }
        if changed { persist() }
    }

    // MARK: - Offline-capable punches: selfie files

    private var photoDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("KinematicOfflineAttendance", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Keep a selfie (already compressed JPEG bytes) in app-private storage under a name derived from the
    /// idempotency key; the file name, or nil when it could not be written.
    func savePhoto(_ data: Data, key: String) -> String? {
        var safe: String = ""
        for s in key.unicodeScalars where Self.isSafeFileNameScalar(s) {
            safe.unicodeScalars.append(s)
        }
        let name: String = (safe.isEmpty ? "punch" : safe) + ".jpg"
        do {
            try data.write(to: photoDir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Letters, digits, "-" and "_" only — the rest of an idempotency key never reaches a file name.
    private static func isSafeFileNameScalar(_ s: Unicode.Scalar) -> Bool {
        let v: UInt32 = s.value
        if v >= 48 && v <= 57 { return true }       // 0-9
        if v >= 65 && v <= 90 { return true }       // A-Z
        if v >= 97 && v <= 122 { return true }      // a-z
        return v == 45 || v == 95                   // - _
    }

    /// The stored selfie, or nil when there is none / it is gone. Names come from our own rows; refuse anything path-like.
    private func photoData(_ name: String?) -> Data? {
        guard let name = name, !name.isEmpty, !name.contains("/"), !name.contains("..") else { return nil }
        return try? Data(contentsOf: photoDir.appendingPathComponent(name))
    }

    private func deletePhoto(_ name: String?) {
        guard let name = name, !name.isEmpty, !name.contains("/"), !name.contains("..") else { return }
        try? FileManager.default.removeItem(at: photoDir.appendingPathComponent(name))
    }

    // MARK: - Sending one row

    /// What one attempt at an offline-capable row came to.
    enum PunchOutcome {
        /// The server has it (2xx, or 409 = already recorded). The record is the server's reply, when it sent one.
        case synced(AttendanceRecord?)
        /// Not delivered (no connection, a busy server, a sign-in that needs refreshing): the row stays queued.
        case held(String)
        /// The server gave a final "no" (or the punch can never be sent): the row is marked refused.
        case rejected(String, locationRequired: Bool)
    }

    /// Build the request from the row and send it. Every field comes from the row, so the inline attempt and every
    /// replay carry byte-identical content.
    private func send(_ row: PendingAttendance) async -> AttendanceSubmitResult {
        let isCheckIn = row.kind == "checkin"
        var capturedAt: String? = nil
        var dateQuery: String? = nil
        if let at = row.capturedAt {
            capturedAt = OfflinePunch.formatCapturedAt(at)
            dateQuery = OfflinePunch.dateQuery(attendanceDate: row.attendanceDate, now: Date())
        }
        return await KinematicRepository.shared.markAttendance(
            isCheckIn: isCheckIn,
            lat: row.lat, lng: row.lng,
            selfieUrl: row.selfieUrl,
            battery: row.battery,
            faceScore: row.faceScore, faceVerified: row.faceVerified, faceModelId: row.faceModelId,
            isMock: row.isMock, locationAccuracyM: row.locationAccuracyM,
            idempotencyKey: row.idempotencyKey,
            transportMode: isCheckIn ? row.transportMode : nil,
            capturedAt: capturedAt,
            dateQuery: dateQuery
        )
    }

    /// Send one OFFLINE-CAPABLE row: the selfie first (its URL is stored on the row before it is used, so a retry never
    /// uploads again and the body never changes), then the punch. Updates the row; the caller decides what the screens
    /// say. Safe to call for the row's first (inline) attempt — wrap it in `beginInline` / `endInline` — and from the flush.
    func attempt(_ id: UUID) async -> PunchOutcome {
        guard let startIndex = rows.firstIndex(where: { $0.id == id }) else {
            return .rejected("This punch is no longer queued.", locationRequired: false)
        }
        let first = rows[startIndex]
        guard let capturedAt = first.capturedAt else {
            return .rejected("This punch cannot be sent from the queue.", locationRequired: false)
        }
        if OfflinePunch.isTooOld(capturedAt: capturedAt, now: Date()) {
            return refuse(id, OfflinePunch.tooOldMessage, locationRequired: false)
        }
        let selfieMandatory: Bool = first.selfieRequired == true

        // 1. The selfie.
        if first.selfieUrl == nil, let photo = first.photoFile {
            if let data = photoData(photo) {
                switch await KinematicRepository.shared.uploadSelfieData(data) {
                case .uploaded(let url):
                    mutate(id) { $0.selfieUrl = url }
                case .transient(let message):
                    hold(id, message)
                    return .held(message)
                case .failed(let message):
                    if selfieMandatory { return refuse(id, "Selfie upload failed: \(message)", locationRequired: false) }
                    // Optional for this person and the server will not take it: send the punch without one, as the live
                    // flow does. Decided once and stored, so the body stays fixed.
                    deletePhoto(photo)
                    mutate(id) { $0.photoFile = nil }
                }
            } else {
                if selfieMandatory { return refuse(id, "The selfie photo is missing from this phone", locationRequired: false) }
                mutate(id) { $0.photoFile = nil }
            }
        }

        // 2. The punch itself, with the key and capture time fixed when the rep tapped.
        guard let current = rows.first(where: { $0.id == id }) else {
            return .rejected("This punch is no longer queued.", locationRequired: false)
        }
        let result = await send(current)
        if result.success {
            finish(id)
            return .synced(result.record)
        }
        let failure: AttendanceFailureKind = result.failure ?? .rejected
        let message: String = result.message ?? "Could not send"
        switch OfflinePunch.verdict(failure: failure, httpStatus: result.httpStatus, message: message, attempt: current.attempt) {
        case .done:
            finish(id)
            return .synced(nil)
        case .hold:
            hold(id, message)
            return .held(message)
        case .reject:
            return refuse(id, message, locationRequired: failure == .locationRequired)
        }
    }

    private func mutate(_ id: UUID, _ change: (inout PendingAttendance) -> Void) {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            change(&rows[i])
            persist()
        }
    }

    /// The server has it: finish the row and delete the photo.
    private func finish(_ id: UUID) {
        let photo = rows.first(where: { $0.id == id })?.photoFile
        markSynced(id)
        deletePhoto(photo)
    }

    /// Not delivered: keep the row, count the attempt.
    private func hold(_ id: UUID, _ message: String) {
        recordError(id, error: message)
    }

    /// A final "no": the row stays (so the rep sees it) but is marked refused and never replayed; its photo goes.
    private func refuse(_ id: UUID, _ message: String, locationRequired: Bool) -> PunchOutcome {
        let photo = rows.first(where: { $0.id == id })?.photoFile
        markRejected(id, error: message)
        deletePhoto(photo)
        mutate(id) { $0.photoFile = nil }
        return .rejected(message, locationRequired: locationRequired)
    }

    // MARK: - Draining

    private var retryScheduled = false
    private var retryRounds = 0

    /// An offline-capable punch is waiting and the phone may well have a network (a busy server, a flaky signal, which no
    /// reachability change will announce): while the app is open, look again in a minute — at most ten times in a row.
    /// (Getting a network back, and coming back to the foreground, flush on their own.)
    func scheduleRetry() {
        if retryScheduled { return }
        retryScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            guard let self = self else { return }
            self.retryScheduled = false
            // With no network the path monitor flushes the moment it returns.
            guard Session.isAuthenticated, self.isOnline else { return }
            await self.flush()
            if self.punchesForCurrentUser().contains(where: { !$0.rejected }) {
                self.retryRounds += 1
                if self.retryRounds < 10 { self.scheduleRetry() }
            } else {
                self.retryRounds = 0
            }
        }
    }

    /// Drain — sync each pending row through KinematicRepository.markAttendance, oldest first (a check-out
    /// must never go ahead of the check-in it follows).
    ///  - success: the row is synced.
    ///  - a failure to get through (offline, timeout, 408 / 429 / 5xx) or an expired sign-in: the error is
    ///    recorded, the row stays queued and the drain stops — the rest would fail the same way, and order matters.
    ///  - anything else (the server refused the punch): the row is marked rejected and never sent again; the
    ///    drain carries on with the next one.
    /// Offline-capable rows (`capturedAt` set) follow the same rules through `attempt` (selfie upload first, `captured_at`
    /// on the request) and are additionally held behind their own check-in; a 409 "already recorded" counts as done.
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        pruneRejected()
        adoptLegacyRows()

        let who = Self.identity()
        let mine: [PendingAttendance] = rows.filter {
            !$0.isSynced && QueueOwnership.owns(rowKey: $0.userKey, createdAt: $0.createdAt, identity: who)
        }
        // How the latest EARLIER check-in in the queue stands (decides what an offline-capable check-out may do).
        var checkin: OfflinePunch.CheckinOutcome? = nil
        for row in AttendanceSyncPolicy.drainOrder(mine) {
            let isCheckIn = row.kind == "checkin"
            // A refused punch is never replayed (but it decides what a later check-out may do); a row whose first
            // send is still in flight belongs to the foreground call that created it.
            if row.rejectedReason != nil || inFlight.contains(row.id) {
                if isCheckIn { checkin = row.rejectedReason != nil ? .rejected : .pending }
                continue
            }

            if row.capturedAt != nil {
                if let kind = OfflinePunch.Kind(rawValue: row.kind) {
                    switch OfflinePunch.gate(kind: kind, precedingCheckin: checkin) {
                    case .send:
                        break
                    case .waitForCheckin:
                        continue
                    case .rejectNoCheckin:
                        _ = refuse(row.id, OfflinePunch.checkinRefusedMessage, locationRequired: false)
                        continue
                    }
                }
                switch await attempt(row.id) {
                case .synced(let record):
                    if isCheckIn { checkin = .synced }
                    KiniAppState.shared.attendanceVM.queuedPunchReachedServer(row, record: record)
                case .rejected:
                    if isCheckIn { checkin = .rejected }
                case .held:
                    return       // an outage (or a sign-in to refresh): nothing after it could get through either
                }
                continue
            }

            // A row from before offline capture existed: exactly as it always was.
            let result = await send(row)
            if result.success {
                markSynced(row.id)
                if isCheckIn { checkin = .synced }
                KiniAppState.shared.attendanceVM.queuedPunchReachedServer(row, record: result.record)
                continue
            }
            let reason = result.message ?? "Unknown error"
            switch AttendanceSyncPolicy.queueAction(for: result.failure ?? .rejected) {
            case .keepAndStop:
                recordError(row.id, error: reason)
                return
            case .drop:
                markRejected(row.id, error: reason)
                if isCheckIn { checkin = .rejected }
            }
        }
    }
}
