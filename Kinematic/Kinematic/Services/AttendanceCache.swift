// AttendanceCache — disk-persisted offline queue for attendance check-in /
// check-out. Mirrors OrderCache from the distribution module. Each pending
// row carries a stable Idempotency-Key; on flush, the server returns the
// canonical record (replays return the original response, never duplicates).

import Foundation

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

    init() { load() }

    private func load() {
        rows = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([PendingAttendance].self, from: $0) } ?? []
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        queue.async { try? data.write(to: self.file, options: .atomic) }
    }

    static func userKey() -> String { String(Session.sharedToken.suffix(24)) }

    /// Enqueue an attendance event and return the row (with its idempotency
    /// key). Caller is responsible for kicking the flush.
    func enqueue(kind: String, lat: Double, lng: Double, selfieUrl: String?, battery: Int?) -> PendingAttendance {
        let row = PendingAttendance(
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
        rows.insert(row, at: 0)
        persist()
        return row
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

    func pendingForCurrentUser() -> [PendingAttendance] {
        let key = Self.userKey()
        return rows.filter { !$0.isSynced && $0.userKey == key }
    }

    func clearSynced() {
        rows.removeAll { $0.isSynced }
        persist()
    }

    /// Drain — sync each pending row through KinematicRepository.markAttendance.
    /// Errors are recorded; rows stay queued for the next flush.
    func flush() async {
        let pending = pendingForCurrentUser()
        for row in pending {
            let isCheckIn = row.kind == "checkin"
            let (ok, err, _) = await KinematicRepository.shared.markAttendance(
                isCheckIn: isCheckIn,
                lat: row.lat, lng: row.lng,
                selfieUrl: row.selfieUrl,
                battery: row.battery,
                idempotencyKey: row.idempotencyKey
            )
            if ok { markSynced(row.id) }
            else  { recordError(row.id, error: err ?? "Unknown error") }
        }
    }
}
