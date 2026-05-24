//
//  CRMWriteQueue.swift
//  Kinematic CRM
//
//  Disk-persisted offline mutation queue for CRM (leads / contacts /
//  accounts / deals / activities). Mirrors OrderCache + AttendanceCache:
//  every queued mutation gets a stable Idempotency-Key so retries on the
//  same server row are idempotent.
//
//  Lifecycle:
//    1) ViewModel calls CRMService.createLead(...) — the service either
//       hits the network successfully (best path), or detects offline /
//       network failure and routes through CRMWriteQueue.enqueue(...).
//    2) Enqueue stamps the row with a tmp id (`pending:<uuid>`) and a
//       UUID-based Idempotency-Key, persists to disk, and returns.
//    3) CRMSyncEngine drains the queue oldest-first on a reachability
//       transition (or manual flush from settings).
//    4) On success: the server returns the canonical row. SyncEngine
//       replaces the local optimistic row's id (pending:* → real uuid)
//       and marks the queue entry synced.
//    5) Permanent failures (4xx) stop retrying. Network errors + 5xx
//       keep retrying with exponential backoff up to 5 attempts.
//

import Foundation
import Combine

enum CRMEntityType: String, Codable, CaseIterable {
    case lead, contact, account, deal, activity
}

enum CRMOperation: String, Codable {
    case create
    case update
}

/// Single queued mutation. `payload` is a JSON-encoded `[String: Any]` body
/// — encoded once at enqueue time so we don't need to drag the original
/// dictionary across actor hops.
struct PendingCRMMutation: Codable, Identifiable {
    let id: UUID
    let idempotencyKey: String
    let userKey: String
    let entityType: CRMEntityType
    let operation: CRMOperation
    /// For updates this is the real server id; for creates it's the
    /// local `pending:<uuid>` token the UI is showing. SyncEngine rewrites
    /// `entityId` from pending → real once create completes.
    var entityId: String?
    /// Endpoint variant for non-CRUD mutations (move-stage / win / lose).
    /// `nil` for plain create / update.
    let variant: String?
    let payload: Data
    let createdAt: Date
    var attempt: Int
    var lastError: String?
    /// Set true when the server has acknowledged. Permanent 4xx failures
    /// keep `synced = false` but `permanentFailure = true`.
    var synced: Bool
    var permanentFailure: Bool
}

@MainActor
final class CRMWriteQueue: ObservableObject {
    static let shared = CRMWriteQueue()

    @Published private(set) var rows: [PendingCRMMutation] = []

    private let ioQueue = DispatchQueue(label: "com.kinematic.crmwritequeue", qos: .utility)
    private var file: URL { docs.appendingPathComponent("pending_crm_mutations.json") }
    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    init() { load() }

    private func load() {
        rows = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([PendingCRMMutation].self, from: $0) } ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        let url = file
        ioQueue.async { try? data.write(to: url, options: .atomic) }
    }

    static func userKey() -> String { String(Session.sharedToken.suffix(24)) }

    // ── Idempotency key helpers ─────────────────────────────────────
    /// Stable key for an update. We hash the payload + entity id so the same
    /// edit retried later replays cleanly; a *different* edit (different
    /// fields) generates a different key so the server applies it as a new
    /// PATCH instead of returning the cached response from the prior edit.
    static func updateKey(entityId: String, payload: Data) -> String {
        var hasher = Hasher()
        hasher.combine(payload)
        let h = abs(hasher.finalize())
        return "upd-\(entityId)-\(String(h, radix: 16))"
    }

    static func createKey(entity: CRMEntityType) -> String {
        "crt-\(entity.rawValue)-\(UUID().uuidString)"
    }

    static func pendingId() -> String { "pending:\(UUID().uuidString)" }

    // ── Enqueue ─────────────────────────────────────────────────────
    /// Append a mutation to the queue. `payload` is the raw POST/PATCH body
    /// the service would have sent online — re-encoded as Data so the row
    /// stays Codable across app restarts.
    @discardableResult
    func enqueue(
        entityType: CRMEntityType,
        operation: CRMOperation,
        entityId: String?,
        payload: [String: Any],
        variant: String? = nil
    ) -> PendingCRMMutation {
        // [String: Any] is not Codable directly; round-trip through JSONSerialization
        // so we get a clean Data blob.
        let encoded = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data("{}".utf8)
        let key: String
        switch operation {
        case .create: key = Self.createKey(entity: entityType)
        case .update:
            // For updates we want the same edit, retried, to dedupe server-side.
            key = Self.updateKey(entityId: entityId ?? UUID().uuidString, payload: encoded)
        }
        let row = PendingCRMMutation(
            id: UUID(),
            idempotencyKey: key,
            userKey: Self.userKey(),
            entityType: entityType,
            operation: operation,
            entityId: entityId,
            variant: variant,
            payload: encoded,
            createdAt: Date(),
            attempt: 0,
            lastError: nil,
            synced: false,
            permanentFailure: false
        )
        rows.append(row)
        persist()
        return row
    }

    // ── State updates ───────────────────────────────────────────────
    func markSynced(_ id: UUID, realEntityId: String? = nil) {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i].synced = true
            rows[i].lastError = nil
            if let realEntityId, rows[i].operation == .create {
                rows[i].entityId = realEntityId
            }
            persist()
        }
    }

    func recordError(_ id: UUID, error: String, permanent: Bool) {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i].attempt += 1
            rows[i].lastError = error
            if permanent { rows[i].permanentFailure = true }
            persist()
        }
    }

    func remove(_ id: UUID) {
        rows.removeAll { $0.id == id }
        persist()
    }

    func resetForRetry(_ id: UUID) {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            rows[i].attempt = 0
            rows[i].lastError = nil
            rows[i].permanentFailure = false
            persist()
        }
    }

    // ── Queries ─────────────────────────────────────────────────────
    /// Pending rows scoped to the current user. Excludes already-synced rows
    /// but includes permanent failures so the UI can surface them with a
    /// retry / delete button.
    func pendingForCurrentUser() -> [PendingCRMMutation] {
        let key = Self.userKey()
        return rows.filter { !$0.synced && $0.userKey == key }
    }

    /// Number of rows still owed to the server (used by the offline banner).
    var pendingCount: Int { pendingForCurrentUser().count }

    /// Pending rows for a specific entity type — list views call this so a
    /// freshly-created lead can be merged into the on-screen list before the
    /// server has confirmed it.
    func pending(for entity: CRMEntityType) -> [PendingCRMMutation] {
        pendingForCurrentUser().filter { $0.entityType == entity }
    }

    func clearSynced() {
        rows.removeAll { $0.synced }
        persist()
    }
}
