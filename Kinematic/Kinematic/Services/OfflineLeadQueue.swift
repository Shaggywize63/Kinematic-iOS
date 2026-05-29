import Foundation
import Network

/**
 * Offline-first lead queue.
 *
 * When the rep is mid-visit on patchy cell, `CRMService.createLead`
 * hands the payload to this queue if the POST fails (no network,
 * transient 5xx, timeout). The queue persists each pending lead as
 * a JSON file under Application Support and replays them on:
 *   - app launch
 *   - app foreground
 *   - network path becoming `.satisfied` (NWPathMonitor)
 *
 * Idempotent: every queued lead carries a stable UUID-based
 * Idempotency-Key (server is expected to honour it for replay).
 *
 * Single-file queue keeps the moving parts to a minimum — we don't
 * need a real database for one entity. Reps rarely accumulate more
 * than a handful of leads between sync windows; the on-disk file is
 * < 100 KB even at the high end.
 */
final class OfflineLeadQueue: ObservableObject {
    static let shared = OfflineLeadQueue()

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastError: String?

    private let monitor = NWPathMonitor()
    private let queueQueue = DispatchQueue(label: "ai.kinematic.offline-leads")
    private var isSyncing = false

    private struct QueuedLead: Codable {
        let id: String
        let idempotencyKey: String
        let payload: [String: AnyCodable]
        let clientId: String?
        let createdAt: Date
        var attempt: Int
        var lastError: String?
    }

    // MARK: - File location
    private var dir: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("KinematicOfflineLeads", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private init() {
        // Listen for connectivity transitions and drain when the path
        // becomes satisfied. Idempotent — drain() guards against double-fire.
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            self?.drain()
        }
        monitor.start(queue: queueQueue)
        refreshCount()
    }

    // MARK: - Enqueue
    /// Persist a lead payload for later replay. Returns the synthesised
    /// lead id (a local UUID) so the form can dismiss with consistent
    /// behaviour.
    func enqueue(payload: [String: Any], clientId: String?, lastError: String? = nil) -> String {
        let id = UUID().uuidString
        let idempotencyKey = "lead-\(id)"
        let row = QueuedLead(
            id: id,
            idempotencyKey: idempotencyKey,
            payload: payload.mapValues { AnyCodable($0) },
            clientId: clientId,
            createdAt: Date(),
            attempt: 0,
            lastError: lastError
        )
        let file = dir.appendingPathComponent("\(id).json")
        do {
            let data = try JSONEncoder().encode(row)
            try data.write(to: file, options: .atomic)
        } catch {
            self.lastError = "Failed to queue: \(error.localizedDescription)"
        }
        refreshCount()
        return id
    }

    // MARK: - Drain
    func drain() {
        queueQueue.async { [weak self] in
            guard let self else { return }
            if self.isSyncing { return }
            self.isSyncing = true
            defer { self.isSyncing = false }

            let files = (try? FileManager.default.contentsOfDirectory(at: self.dir, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
            if files.isEmpty {
                DispatchQueue.main.async { self.pendingCount = 0 }
                return
            }

            for file in files {
                let ok = self.replayOne(file: file)
                if !ok {
                    // Stop draining on first transient failure — wait for
                    // the next path-update to retry. Avoids burning battery
                    // on a still-flapping connection.
                    break
                }
            }
            DispatchQueue.main.async {
                self.lastSyncedAt = Date()
                self.refreshCount()
            }
        }
    }

    private func replayOne(file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file),
              var row = try? JSONDecoder().decode(QueuedLead.self, from: data) else {
            // Corrupt row — drop it.
            try? FileManager.default.removeItem(at: file)
            return true
        }
        var success = false
        let group = DispatchGroup()
        group.enter()
        Task {
            do {
                let body = row.payload.mapValues { $0.value }
                _ = try await CRMService.shared.createLeadDirect(
                    body: body,
                    idempotencyKey: row.idempotencyKey,
                    clientId: row.clientId
                )
                success = true
                try? FileManager.default.removeItem(at: file)
            } catch let e as URLError where [.notConnectedToInternet, .timedOut, .cannotConnectToHost].contains(e.code) {
                row.attempt += 1
                row.lastError = e.localizedDescription
                if let d = try? JSONEncoder().encode(row) { try? d.write(to: file, options: .atomic) }
                success = false
            } catch {
                // 4xx permanent — drop so we don't retry forever.
                row.attempt += 1
                row.lastError = error.localizedDescription
                if row.attempt >= 8 {
                    try? FileManager.default.removeItem(at: file)
                    success = true
                } else {
                    if let d = try? JSONEncoder().encode(row) { try? d.write(to: file, options: .atomic) }
                    success = false
                }
            }
            group.leave()
        }
        group.wait()
        return success
    }

    private func refreshCount() {
        let n = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .count) ?? 0
        DispatchQueue.main.async { self.pendingCount = n }
    }
}

// MARK: - AnyCodable helper
/// Minimal Codable wrapper so we can persist arbitrary `[String: Any]`
/// without inflating the dependency footprint.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            value = NSNull()
        } else if let b = try? c.decode(Bool.self) { value = b
        } else if let i = try? c.decode(Int.self) { value = i
        } else if let d = try? c.decode(Double.self) { value = d
        } else if let s = try? c.decode(String.self) { value = s
        } else if let a = try? c.decode([AnyCodable].self) { value = a.map { $0.value }
        } else if let o = try? c.decode([String: AnyCodable].self) { value = o.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull:                       try c.encodeNil()
        case let b as Bool:                   try c.encode(b)
        case let i as Int:                    try c.encode(i)
        case let i as Int64:                  try c.encode(i)
        case let d as Double:                 try c.encode(d)
        case let s as String:                 try c.encode(s)
        case let a as [Any]:                  try c.encode(a.map { AnyCodable($0) })
        case let o as [String: Any]:          try c.encode(o.mapValues { AnyCodable($0) })
        default:                              try c.encode(String(describing: value))
        }
    }
}
