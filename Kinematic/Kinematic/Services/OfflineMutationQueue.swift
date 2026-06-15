import Foundation
import Combine
import Network

/**
 * Generic offline-first mutation queue. Captures any (method, path,
 * body) tuple the rep tried to send while offline / on weak signal,
 * persists it under Application Support, and drains on:
 *   - app launch
 *   - app foreground
 *   - network path becoming `.satisfied` (NWPathMonitor)
 *
 * Designed to subsume every CRM write surface (activities pilot the
 * queue; lead-edit / note / deal mutations fold in next).
 *
 * Each row carries a stable Idempotency-Key so the server returns the
 * original response on replay — no phantom duplicate rows. Each row
 * also carries a short `displayLabel` so the pending-sync sheet (and
 * any future per-row UI) can show what's queued without decoding the
 * payload.
 *
 * Why a separate file from OfflineLeadQueue: the lead queue pre-dates
 * this and has live queued rows in the field. Re-using its on-disk
 * format would risk migrating real reps' captured work. The two
 * queues run side-by-side; the lead path eventually folds in but only
 * when its in-flight rows have drained.
 */
@MainActor
final class OfflineMutationQueue: ObservableObject {
    static let shared = OfflineMutationQueue()

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastError: String?

    private let monitor = NWPathMonitor()
    private let queueQueue = DispatchQueue(label: "ai.kinematic.offline-mutations")
    private var isSyncing = false

    struct QueuedMutation: Codable {
        let id: String
        let idempotencyKey: String
        let displayLabel: String
        /// POST | PATCH | DELETE
        let method: String
        /// Full API path, e.g. `/api/v1/crm/activities`
        let path: String
        /// JSON string of the body the form built — replayed verbatim
        /// after any kinematic-offline:// placeholders have been
        /// swapped for real uploaded URLs.
        var payloadJSON: String
        let clientId: String?
        let createdAt: Date
        var attempt: Int
        var lastError: String?
    }

    private enum ImageResolution {
        case ok(String)
        case deferred
    }

    // MARK: - File location
    private var dir: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("KinematicOfflineMutations", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.drain() }
        }
        monitor.start(queue: queueQueue)
        refreshCount()
    }

    // MARK: - Enqueue

    /// Persist a mutation for later replay. Returns the row id so the
    /// caller can correlate UI affordances (snackbar, retry button)
    /// with the on-disk record.
    @discardableResult
    func enqueue(method: String, path: String, body: [String: Any], displayLabel: String, clientId: String?, lastError: String? = nil) -> String {
        let id = UUID().uuidString
        let idempotencyKey = "mut-\(id)"
        let bodyData = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data()
        let payloadJSON = String(data: bodyData, encoding: .utf8) ?? "{}"
        let row = QueuedMutation(
            id: id,
            idempotencyKey: idempotencyKey,
            displayLabel: displayLabel,
            method: method.uppercased(),
            path: path,
            payloadJSON: payloadJSON,
            clientId: clientId,
            createdAt: Date(),
            attempt: 0,
            lastError: lastError,
        )
        let file = dir.appendingPathComponent("\(id).json")
        do {
            let data = try JSONEncoder().encode(row)
            try data.write(to: file, options: [.atomic])
        } catch {
            self.lastError = "Failed to queue: \(error.localizedDescription)"
        }
        refreshCount()
        return id
    }

    // MARK: - Drain

    func drain() {
        Task.detached(priority: .utility) { [weak self] in
            await self?.drainInternal()
        }
    }

    private nonisolated func drainInternal() async {
        let dirURL = await self.dir
        let files = (try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        if files.isEmpty {
            await MainActor.run { self.pendingCount = 0 }
            return
        }
        for file in files {
            let ok = await replayOne(file: file)
            if !ok { break }
        }
        await MainActor.run {
            self.lastSyncedAt = Date()
            self.refreshCount()
        }
    }

    private nonisolated func replayOne(file: URL) async -> Bool {
        guard let data = try? Data(contentsOf: file),
              var row = try? JSONDecoder().decode(QueuedMutation.self, from: data) else {
            try? FileManager.default.removeItem(at: file)
            return true
        }
        // Resolve any kinematic-offline://image-… placeholders first.
        // If an upload defers (no signal mid-replay), leave the row
        // queued for the next path-satisfied callback so the activity
        // doesn't post with a dangling placeholder URL.
        let resolved = await drainOfflineImages(in: row.payloadJSON)
        switch resolved {
        case .deferred:
            row.attempt += 1
            row.lastError = "Image upload deferred"
            if let d = try? JSONEncoder().encode(row) { try? d.write(to: file, options: [.atomic]) }
            return false
        case .ok(let rewritten):
            row.payloadJSON = rewritten
        }
        let payload: [String: Any]
        if let bodyData = row.payloadJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any] {
            payload = dict
        } else {
            try? FileManager.default.removeItem(at: file)
            return true
        }
        do {
            let status = try await CRMService.shared.sendRawMutation(
                method: row.method,
                path: row.path,
                body: payload,
                idempotencyKey: row.idempotencyKey,
                clientId: row.clientId,
            )
            // 2xx = success → drop. 4xx (non-transient) = permanent reject → drop.
            // 408 / 429 / 5xx / 0 = transient → bump attempt + retain.
            if (200..<300).contains(status) {
                try? FileManager.default.removeItem(at: file)
                return true
            }
            if status == 408 || status == 429 || status >= 500 || status == 0 {
                row.attempt += 1
                row.lastError = "HTTP \(status)"
                if row.attempt >= 8 {
                    try? FileManager.default.removeItem(at: file)
                    return true
                }
                if let d = try? JSONEncoder().encode(row) { try? d.write(to: file, options: [.atomic]) }
                return false
            }
            // Permanent failure (4xx) — drop so we don't retry forever.
            try? FileManager.default.removeItem(at: file)
            return true
        } catch {
            row.attempt += 1
            row.lastError = error.localizedDescription
            if row.attempt >= 8 {
                try? FileManager.default.removeItem(at: file)
                return true
            }
            if let d = try? JSONEncoder().encode(row) { try? d.write(to: file, options: [.atomic]) }
            return false
        }
    }

    private func refreshCount() {
        let n = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .count) ?? 0
        self.pendingCount = n
    }

    /// Walk the payload for `kinematic-offline://image-…` placeholders.
    /// Upload each backing file to `/upload/activity_form`; on any
    /// transient failure return `.deferred` so the row stays queued
    /// for the next path-satisfied tick.
    private nonisolated func drainOfflineImages(in payloadJSON: String) async -> ImageResolution {
        if !payloadJSON.contains(OfflineImageCache.placeholderPrefix) {
            return .ok(payloadJSON)
        }
        var working = payloadJSON
        // Naïve regex over the source — these placeholders only ever
        // appear inside JSON-encoded string values, so a literal scan
        // is safe enough.
        let pattern = OfflineImageCache.placeholderPrefix + "[A-Za-z0-9._-]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return .ok(working)
        }
        var matches: Set<String> = []
        let ns = working as NSString
        for m in regex.matches(in: working, range: NSRange(location: 0, length: ns.length)) {
            matches.insert(ns.substring(with: m.range))
        }
        for placeholder in matches {
            guard let file = OfflineImageCache.fileURL(for: placeholder),
                  let data = try? Data(contentsOf: file) else {
                // Local file gone — drop the placeholder so the
                // activity still persists with no attachment.
                working = working.replacingOccurrences(of: placeholder, with: "")
                continue
            }
            do {
                let url = try await uploadActivityImageData(data)
                working = working.replacingOccurrences(of: placeholder, with: url)
                OfflineImageCache.delete(placeholder)
            } catch {
                return .deferred
            }
        }
        return .ok(working)
    }

    /// Multipart upload to /upload/activity_form. Mirrors the
    /// KinematicRepository.uploadImage shape so the server stores the
    /// asset in the same bucket the live (online) path uses.
    private nonisolated func uploadActivityImageData(_ data: Data) async throws -> String {
        struct UploadOutcome: Decodable { let url: String? }
        let token = Session.sharedToken
        // Same endpoint the online ActivityComposeView path uses, so
        // the queued attachment lands in the same bucket as live
        // captures. Kept inline to avoid coupling the queue to
        // CRMService internals (makeRequest / perform are private).
        guard !token.isEmpty,
              let url = URL(string: "https://api.kinematicapp.com/api/v1/upload/activity_form") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let orgId = Session.currentUser?.orgId { req.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"queued.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // Backend wraps responses in `{ success, data: { url } }` for
        // most upload endpoints; fall back to a bare top-level `url`
        // if the shape changes.
        if let any = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] {
            if let data = any["data"] as? [String: Any], let url = data["url"] as? String { return url }
            if let url = any["url"] as? String { return url }
        }
        throw URLError(.cannotParseResponse)
    }
}
