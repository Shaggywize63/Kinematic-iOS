import Foundation
import Combine
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
 * Idempotency-Key (server honours it for replay).
 *
 * Implementation note: the lead payload is stored as a pre-encoded
 * JSON string rather than wrapped in an AnyCodable type, both because
 * the codebase already declares a single-purpose `AnyCodable` in
 * Models/CRM/Lead.swift (string-only) and because a JSON-string blob
 * keeps the queue file self-describing for any future on-device tools
 * that want to peek at pending captures.
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
        /// JSON-string of the body the form built — replayed verbatim.
        let payloadJSON: String
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
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            self?.drain()
        }
        monitor.start(queue: queueQueue)
        refreshCount()
    }

    // MARK: - Enqueue
    func enqueue(payload: [String: Any], clientId: String?, lastError: String? = nil) -> String {
        let id = UUID().uuidString
        let idempotencyKey = "lead-\(id)"
        let bodyData = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()
        let payloadJSON = String(data: bodyData, encoding: .utf8) ?? "{}"
        let row = QueuedLead(
            id: id,
            idempotencyKey: idempotencyKey,
            payloadJSON: payloadJSON,
            clientId: clientId,
            createdAt: Date(),
            attempt: 0,
            lastError: lastError
        )
        let file = dir.appendingPathComponent("\(id).json")
        do {
            let data = try JSONEncoder().encode(row)
            // Encrypt at rest (M-2). `untilFirstUserAuthentication` keeps the
            // file readable for background drain after the first post-boot
            // unlock, while still protecting it in device backups and against
            // at-rest extraction from a locked/powered-off device.
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
                // Stop on first transient failure — wait for the next path
                // update to retry. Avoids burning battery on a flapping link.
                if !ok { break }
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
            try? FileManager.default.removeItem(at: file)
            return true
        }
        // Decode the persisted JSON string back into a dictionary the
        // typed API helper can re-serialise.
        let payload: [String: Any]
        if let bodyData = row.payloadJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any] {
            payload = dict
        } else {
            // Corrupt — drop it.
            try? FileManager.default.removeItem(at: file)
            return true
        }
        var success = false
        let group = DispatchGroup()
        group.enter()
        Task {
            do {
                _ = try await CRMService.shared.createLeadDirect(
                    body: payload,
                    idempotencyKey: row.idempotencyKey,
                    clientId: row.clientId
                )
                success = true
                try? FileManager.default.removeItem(at: file)
            } catch let e as URLError where [.notConnectedToInternet, .timedOut, .cannotConnectToHost, .networkConnectionLost, .dataNotAllowed].contains(e.code) {
                row.attempt += 1
                row.lastError = e.localizedDescription
                if let d = try? JSONEncoder().encode(row) { try? d.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
                success = false
            } catch {
                row.attempt += 1
                row.lastError = error.localizedDescription
                if row.attempt >= 8 {
                    try? FileManager.default.removeItem(at: file)
                    success = true
                } else {
                    if let d = try? JSONEncoder().encode(row) { try? d.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
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
