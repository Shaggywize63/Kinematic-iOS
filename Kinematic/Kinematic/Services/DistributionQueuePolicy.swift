// DistributionQueuePolicy — the rules of the distribution offline write queue (orders, payments, returns) as pure
// functions, so they are unit-tested (see KinematicTests/DistributionQueuePolicyTests) and the sender
// (DistributionSync) only acts on the answer. Mirrors the Android `OfflineWriteQueue`.
//
//  * ONE stable Idempotency-Key per submission: made when the screen opens / the person taps submit and reused by
//    every retry (the inline attempt, a background replay, a second tap), so the server records it once.
//  * What a server answer means — DONE (2xx, or "this key is already recorded"), HOLD (not delivered yet: keep the
//    row and try again later) or REJECT (a final "no": never replay it, keep the row visible as failed).
//  * A rejected row keeps `isSynced == false` and gets `lastError == "Rejected: <reason>"`; the sender skips it, the
//    queue list shows it until the rep dismisses it.
//  * The one-line summary shown to the rep ("2 items saved — will upload when online").

import Foundation

/// The three kinds of write the distribution queue holds.
enum DistributionWriteKind: String, Codable, Equatable {
    case order
    case payment
    case goodsReturn
}

/// What the queue needs from a row of any kind (`PendingOrder`, `PendingPayment`, `PendingReturn`).
protocol DistributionQueueRow: QueueOwned {
    var id: UUID { get }
    var idempotencyKey: String { get }
    var attempt: Int { get set }
    var lastError: String? { get set }
    var isSynced: Bool { get set }
}

enum DistributionQueuePolicy {

    // MARK: - Idempotency keys

    static let orderKeyPrefix = "ord-"
    static let paymentKeyPrefix = "pay-"
    static let returnKeyPrefix = "ret-"

    /// The server accepts keys up to 200 characters.
    static let maxKeyLength = 200

    /// A fresh key. Make it ONCE per submission and reuse it for every retry of that same submission.
    static func newKey(prefix: String) -> String { prefix + UUID().uuidString }

    /// A key the server will accept.
    static func isUsableKey(_ key: String?) -> Bool {
        guard let key = key else { return false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && key.count <= maxKeyLength
    }

    /// The key to use for a submission: the caller's stable one, else a fresh one.
    static func keyOrNew(_ existing: String?, prefix: String) -> String {
        if let existing = existing, isUsableKey(existing) { return existing }
        return newKey(prefix: prefix)
    }

    // MARK: - What a server answer means

    enum Verdict: Equatable {
        /// The server has the write (2xx, or "duplicate of this same key"): the row is finished.
        case done
        /// Not delivered yet — keep the row and try again later.
        case hold
        /// The server gave a final "no": stop replaying, keep the row visible as failed.
        case reject
    }

    /// 408 Request Timeout, 429 Too Many Requests and every 5xx are worth retrying.
    static func isTransient(httpStatus code: Int) -> Bool {
        code == 408 || code == 429 || (500...599).contains(code)
    }

    /// Verdict for an HTTP answer.
    ///  - 2xx: done.
    ///  - 409 that means "this Idempotency-Key is already recorded": done (see `isAlreadyRecorded`). The payments
    ///    endpoint answers a retry of an already-recorded payment with 409, so for payments the caller passes
    ///    `conflictMeansRecorded: true` and ANY 409 (bar the idempotency middleware's own refusals) finishes the row.
    ///    For orders and returns only the explicit "Duplicate … (idempotency …)" 409 does — their other 409s
    ///    (PRICE_MISMATCH, pricing conflicts) are real refusals.
    ///  - 401: hold, NOT a rejection — the session needs a refresh / sign-in and a money row must not be thrown
    ///    away for that; it waits for the same user.
    ///  - 408 / 429 / 5xx: hold. Anything that is not an HTTP answer at all (status 0): hold.
    ///  - every other status: reject.
    static func verdict(httpStatus code: Int, serverMessage: String? = nil, conflictMeansRecorded: Bool = false) -> Verdict {
        if (200..<300).contains(code) { return .done }
        if isAlreadyRecorded(httpStatus: code, serverMessage: serverMessage, anyConflict: conflictMeansRecorded) { return .done }
        if code <= 0 { return .hold }
        if code == 401 { return .hold }
        if isTransient(httpStatus: code) { return .hold }
        return .reject
    }

    /// A 409 meaning the server already holds a record with this exact key. By default that is the explicit
    /// "Duplicate … (idempotency or …)" reply; with `anyConflict` every 409 counts, except the idempotency
    /// middleware's own refusals (same key reused with a different body / by a different user / too long), which
    /// are genuine rejections.
    static func isAlreadyRecorded(httpStatus code: Int, serverMessage: String?, anyConflict: Bool = false) -> Bool {
        guard code == 409 else { return false }
        let m = (serverMessage ?? "").lowercased()
        if m.contains("different request body") || m.contains("different user") || m.contains("too long") { return false }
        if anyConflict { return true }
        return m.contains("duplicate") && m.contains("idempotency")
    }

    /// Verdict for a request that threw (it never produced an HTTP answer). A transport failure of any kind, or a
    /// cancelled request, is a hold — replaying with the SAME key is safe, whereas rejecting could make the rep
    /// enter a payment twice. Only a request that can never be built (bad URL) or an encoding bug is a rejection.
    static func verdict(forThrown error: Error) -> Verdict {
        if error is CancellationError { return .hold }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .badURL, .unsupportedURL: return .reject
            default: return .hold
            }
        }
        return .reject
    }

    /// Transport failures that mean "the network is not there right now" — after one of these the rest of the queue
    /// would fail the same way, so the drain stops.
    static let offlineURLErrorCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .timedOut, .cannotConnectToHost, .networkConnectionLost, .dataNotAllowed,
        .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .callIsActive,
    ]

    static func isOffline(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        guard let urlError = error as? URLError else { return false }
        return offlineURLErrorCodes.contains(urlError.code)
    }

    // MARK: - Messages

    /// What to store / show for a request that threw.
    static func message(forThrown error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost, .internationalRoamingOff, .callIsActive:
                return "No internet connection"
            case .timedOut:
                return "The request timed out"
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Couldn't reach the server"
            default:
                break
            }
        }
        let description = error.localizedDescription
        return description.isEmpty ? "Could not send" : description
    }

    /// The human reason in an error body `{ success:false, error:"…", details:[{message}] }`: the first
    /// `details[].message` (most specific), else `error` (a string, or an object with a `message`), else the raw
    /// text, else "HTTP <code>". At most 300 characters.
    static func serverMessage(body: Data?, httpStatus: Int) -> String {
        guard let body = body, !body.isEmpty else { return "HTTP \(httpStatus)" }
        let raw = (String(data: body, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "HTTP \(httpStatus)" }
        if let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
            if let details = root["details"] as? [Any] {
                for entry in details {
                    if let dict = entry as? [String: Any], let text = nonBlank(dict["message"] as? String) {
                        return String(text.prefix(300))
                    }
                }
            }
            if let text = nonBlank(root["error"] as? String) { return String(text.prefix(300)) }
            if let dict = root["error"] as? [String: Any], let text = nonBlank(dict["message"] as? String) {
                return String(text.prefix(300))
            }
        }
        return String(raw.prefix(300))
    }

    // MARK: - Rejected rows stay visible

    /// Written in front of `lastError` once the server has given a final "no".
    static let rejectedPrefix = "Rejected: "

    /// What the rep is told when a write was saved on the phone but not delivered yet.
    static let savedMessage = "Saved — will upload when online"

    /// `lastError` for a row the server has finally refused.
    static func rejectedError(_ message: String) -> String { rejectedPrefix + message }

    /// True when `lastError` marks a row the server finally refused.
    static func isRejected(lastError: String?) -> Bool {
        guard let lastError = lastError else { return false }
        return lastError.hasPrefix("Rejected")
    }

    /// `lastError` without the marker, for display; nil when there is none.
    static func displayError(_ lastError: String?) -> String? {
        guard let lastError = lastError, nonBlank(lastError) != nil else { return nil }
        var text = lastError
        if isRejected(lastError: lastError) {
            text = String(lastError.dropFirst("Rejected".count))
            while let first = text.first, first == ":" || first == " " { text.removeFirst() }
        }
        return nonBlank(text)
    }

    // MARK: - Replay timing

    /// How long to wait before the next background retry after `attempt` failed rounds: 30 s, 1 min, 2, 4, 8, then
    /// 15 min at most (the Android worker's exponential backoff, capped).
    static func retryDelay(attempt: Int) -> TimeInterval {
        let n = min(max(attempt, 0), 5)
        return min(30.0 * Double(1 << n), 900.0)
    }

    // MARK: - Which rows

    /// The rows the sender may send now: the signed-in user's, not yet synced, not finally refused — oldest first.
    static func sendable<R: DistributionQueueRow>(_ rows: [R], identity: QueueOwnership.Identity) -> [R] {
        let mine: [R] = rows.filter { (row: R) -> Bool in
            !row.isSynced
                && !isRejected(lastError: row.lastError)
                && QueueOwnership.owns(rowKey: row.userKey, createdAt: row.createdAt, identity: identity)
        }
        return mine.sorted { (a: R, b: R) -> Bool in a.createdAt < b.createdAt }
    }

    /// The rows to show the rep: the signed-in user's, not yet accepted — waiting and refused alike.
    static func visible<R: DistributionQueueRow>(_ rows: [R], identity: QueueOwnership.Identity) -> [R] {
        rows.filter { (row: R) -> Bool in
            !row.isSynced && QueueOwnership.owns(rowKey: row.userKey, createdAt: row.createdAt, identity: identity)
        }
    }

    /// The index of the row that already carries `key` (one row per Idempotency-Key), whoever queued it.
    static func rowIndex<R: DistributionQueueRow>(withKey key: String, in rows: [R]) -> Int? {
        rows.firstIndex(where: { (row: R) -> Bool in row.idempotencyKey == key })
    }

    // MARK: - The visible queue

    /// One row of the queue list (My Orders → "Waiting to upload" / "Failed"): an order, payment or return that is
    /// either still waiting for the sender (`failed == false`) or that the server finally refused.
    struct QueueItem: Identifiable, Equatable {
        let kind: DistributionWriteKind
        let rowId: UUID
        let key: String
        let title: String
        let detail: String
        let attempt: Int
        let error: String?
        let failed: Bool
        let createdAt: Date
        var id: String { kind.rawValue + "-" + rowId.uuidString }
    }

    static func item(for row: PendingOrder) -> QueueItem {
        QueueItem(kind: .order, rowId: row.id, key: row.idempotencyKey,
                  title: nonBlank(row.outletName) ?? "Order",
                  detail: "Order · " + DistributionMoney.rupees(row.clientTotal),
                  attempt: row.attempt, error: displayError(row.lastError),
                  failed: isRejected(lastError: row.lastError), createdAt: row.createdAt)
    }

    static func item(for row: PendingPayment) -> QueueItem {
        QueueItem(kind: .payment, rowId: row.id, key: row.idempotencyKey,
                  title: nonBlank(row.outletName) ?? "Payment",
                  detail: "Payment · " + DistributionMoney.rupees(row.input.amount) + " · " + modeLabel(row.input.mode),
                  attempt: row.attempt, error: displayError(row.lastError),
                  failed: isRejected(lastError: row.lastError), createdAt: row.createdAt)
    }

    static func item(for row: PendingReturn) -> QueueItem {
        QueueItem(kind: .goodsReturn, rowId: row.id, key: row.idempotencyKey,
                  title: nonBlank(row.outletName) ?? "Return",
                  detail: "Return · " + row.input.reason_code.replacingOccurrences(of: "_", with: " "),
                  attempt: row.attempt, error: displayError(row.lastError),
                  failed: isRejected(lastError: row.lastError), createdAt: row.createdAt)
    }

    static func modeLabel(_ mode: String) -> String {
        switch mode {
        case "cash": return "Cash"
        case "upi": return "UPI"
        case "cheque": return "Cheque"
        case "credit_adjustment": return "Credit"
        default: return mode
        }
    }

    // MARK: - The summary shown to the rep

    /// How many queued uploads are waiting and how many were finally refused.
    struct QueueSummary: Equatable {
        var pending: Int = 0
        var failed: Int = 0
        var isEmpty: Bool { pending == 0 && failed == 0 }
    }

    static func summary(of items: [QueueItem]) -> QueueSummary {
        var result = QueueSummary()
        for item in items {
            if item.failed { result.failed += 1 } else { result.pending += 1 }
        }
        return result
    }

    /// One line for the rep, or nil when there is nothing to say.
    static func summaryLine(_ s: QueueSummary) -> String? {
        if s.isEmpty { return nil }
        let waiting = s.pending == 1 ? "1 item saved — will upload when online"
                                     : "\(s.pending) items saved — will upload when online"
        let failed = s.failed == 1 ? "1 failed — tap to review" : "\(s.failed) failed — tap to review"
        if s.pending > 0 && s.failed > 0 { return waiting + " · " + failed }
        if s.pending > 0 { return waiting }
        return failed
    }

    /// Short suffix for a menu label — " (2 waiting, 1 failed)" — or "" when the queue is empty.
    static func badgeSuffix(_ s: QueueSummary) -> String {
        if s.isEmpty { return "" }
        if s.pending > 0 && s.failed > 0 { return " (\(s.pending) waiting, \(s.failed) failed)" }
        if s.pending > 0 { return " (\(s.pending) waiting)" }
        return " (\(s.failed) failed)"
    }

    // MARK: - Small helpers

    /// The trimmed text, or nil when it is nil or blank.
    static func nonBlank(_ text: String?) -> String? {
        guard let text = text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
