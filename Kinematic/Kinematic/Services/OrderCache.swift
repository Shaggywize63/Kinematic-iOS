// OrderCache — disk-persisted offline queue for distribution mutations.
//
// Mirrors the Android Room queue: every queued order/payment/return is given a
// stable Idempotency-Key at confirm time and persisted to a JSON file in the
// app's Documents directory. DistributionSync sends the rows: right after the
// rep taps submit, again when the app returns to the foreground, when the
// network comes back, and on a backoff while something is still waiting.
// The queue is keyed by user (the stable user id — see QueueOwnership; it used to be the last 24 chars of the access
// token, which every silent refresh changes) so a re-login under a different account never flushes the
// previous user's pending writes.
//
// A row is in one of three states (no extra column — the rules live in DistributionQueuePolicy):
//   waiting : isSynced == false and lastError does not start with "Rejected" — the sender sends it;
//   failed  : isSynced == false and lastError starts with "Rejected"        — the server finally refused it; it is
//             never replayed, stays in the list until the rep dismisses it;
//   synced  : isSynced == true — the server has it.
// One row per Idempotency-Key: queuing the same key twice keeps the one row, so a second tap or a retry can never
// become a second order / payment.

import Foundation
import Combine

struct PendingOrder: Codable, Identifiable {
    let id: UUID
    let idempotencyKey: String
    /// Who queued it: "u:<user id>" — or, on rows queued by older builds, a token suffix (see QueueOwnership).
    var userKey: String
    let outletId: String
    let outletName: String?
    let visitId: String?
    let input: OrderInput
    let clientTotal: Double
    let createdAt: Date
    var attempt: Int
    var lastError: String?
    var isSynced: Bool
    /// Company the order was taken for; replayed as X-Client-Id. Nil on rows queued by older builds.
    var clientId: String? = nil
}

struct PendingPayment: Codable, Identifiable {
    let id: UUID
    let idempotencyKey: String
    /// Who queued it: "u:<user id>" — or, on rows queued by older builds, a token suffix (see QueueOwnership).
    var userKey: String
    let input: PaymentInput
    let createdAt: Date
    var attempt: Int
    var lastError: String?
    var isSynced: Bool
    /// For the queue list only (never sent). Nil on rows queued by older builds.
    var outletName: String? = nil
    /// Company the payment was collected for; replayed as X-Client-Id. Nil on rows queued by older builds.
    var clientId: String? = nil
}

struct PendingReturn: Codable, Identifiable {
    let id: UUID
    let idempotencyKey: String
    /// Who queued it: "u:<user id>" — or, on rows queued by older builds, a token suffix (see QueueOwnership).
    var userKey: String
    let input: ReturnInput
    let createdAt: Date
    var attempt: Int
    var lastError: String?
    var isSynced: Bool
    /// For the queue list only (never sent). Nil on rows queued by older builds.
    var outletName: String? = nil
    /// Company the return was booked for; replayed as X-Client-Id. Nil on rows queued by older builds.
    var clientId: String? = nil
}

extension PendingOrder: QueueOwned {}
extension PendingPayment: QueueOwned {}
extension PendingReturn: QueueOwned {}
extension PendingOrder: DistributionQueueRow {}
extension PendingPayment: DistributionQueueRow {}
extension PendingReturn: DistributionQueueRow {}

@MainActor
final class OrderCache: ObservableObject {
    static let shared = OrderCache()

    @Published private(set) var orders: [PendingOrder] = []
    @Published private(set) var payments: [PendingPayment] = []
    @Published private(set) var returns: [PendingReturn] = []

    /// Who is signed in, as far as the queue cares. Replaceable so tests can run without a real session.
    var identityProvider: @MainActor () -> QueueOwnership.Identity = { QueueOwnership.currentIdentity() }

    private let queue = DispatchQueue(label: "com.kinematic.ordercache", qos: .utility)
    private let directory: URL
    private var ordersFile: URL  { directory.appendingPathComponent("pending_orders.json") }
    private var paymentsFile: URL { directory.appendingPathComponent("pending_payments.json") }
    private var returnsFile: URL  { directory.appendingPathComponent("pending_returns.json") }

    /// `directory` is where the three JSON files live (the app's Documents directory when nil).
    init(directory: URL? = nil) {
        if let directory = directory {
            self.directory = directory
        } else {
            self.directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        load()
    }

    private func load() {
        orders = (try? Data(contentsOf: ordersFile)).flatMap { try? JSONDecoder().decode([PendingOrder].self, from: $0) } ?? []
        payments = (try? Data(contentsOf: paymentsFile)).flatMap { try? JSONDecoder().decode([PendingPayment].self, from: $0) } ?? []
        returns = (try? Data(contentsOf: returnsFile)).flatMap { try? JSONDecoder().decode([PendingReturn].self, from: $0) } ?? []
    }

    private func persistOrders() { writeAtomically(orders, to: ordersFile) }
    private func persistPayments() { writeAtomically(payments, to: paymentsFile) }
    private func persistReturns() { writeAtomically(returns, to: returnsFile) }

    private func writeAtomically<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        queue.async { try? data.write(to: url, options: .atomic) }
    }

    /// The key new rows are written with: the stable user id (see QueueOwnership).
    static func userKey() -> String { QueueOwnership.keyForNewRow(QueueOwnership.currentIdentity()) }

    private func newRowKey() -> String { QueueOwnership.keyForNewRow(identityProvider()) }

    /// Move rows queued by older builds (keyed by an access-token suffix that has since rotated) onto the
    /// stable user key, wherever it is provable they are the signed-in user's. Nothing is removed. Idempotent.
    /// Called when a row is added and before the queue is read for sending — never from a view update.
    func adoptLegacyRows() {
        let who = identityProvider()
        // Work on copies and only assign when something moved, so a no-op never notifies observers.
        var o = orders, p = payments, r = returns
        if QueueOwnership.migrate(&o, identity: who) > 0 { orders = o; persistOrders() }
        if QueueOwnership.migrate(&p, identity: who) > 0 { payments = p; persistPayments() }
        if QueueOwnership.migrate(&r, identity: who) > 0 { returns = r; persistReturns() }
    }

    // ── Queue ────────────────────────────────────────────────────────

    /// Queues an order under `idempotencyKey`. If a row with that key already exists it is returned unchanged
    /// (whatever its state), so the same submission can never become two rows.
    @discardableResult
    func enqueueOrder(input: OrderInput, clientTotal: Double, outletName: String?, visitId: String?, idempotencyKey: String) -> PendingOrder {
        if let i = DistributionQueuePolicy.rowIndex(withKey: idempotencyKey, in: orders) { return orders[i] }
        adoptLegacyRows()
        let row = PendingOrder(
            id: UUID(),
            idempotencyKey: idempotencyKey,
            userKey: newRowKey(),
            outletId: input.outlet_id,
            outletName: outletName,
            visitId: visitId,
            input: input,
            clientTotal: clientTotal,
            createdAt: Date(),
            attempt: 0,
            lastError: nil,
            isSynced: false,
            clientId: SellingCompany.selectedId()
        )
        orders.insert(row, at: 0)
        persistOrders()
        return row
    }

    func enqueueOrder(input: OrderInput, clientTotal: Double, outletName: String?, visitId: String?) -> PendingOrder {
        enqueueOrder(input: input, clientTotal: clientTotal, outletName: outletName, visitId: visitId,
                     idempotencyKey: DistributionQueuePolicy.newKey(prefix: DistributionQueuePolicy.orderKeyPrefix))
    }

    /// Queues a payment under `idempotencyKey` (one row per key — see `enqueueOrder`).
    @discardableResult
    func enqueuePayment(_ input: PaymentInput, outletName: String?, idempotencyKey: String) -> PendingPayment {
        if let i = DistributionQueuePolicy.rowIndex(withKey: idempotencyKey, in: payments) { return payments[i] }
        adoptLegacyRows()
        let row = PendingPayment(id: UUID(), idempotencyKey: idempotencyKey, userKey: newRowKey(), input: input,
                                 createdAt: Date(), attempt: 0, lastError: nil, isSynced: false, outletName: outletName,
                                 clientId: SellingCompany.selectedId())
        payments.insert(row, at: 0)
        persistPayments()
        return row
    }

    func enqueuePayment(_ input: PaymentInput) -> PendingPayment {
        enqueuePayment(input, outletName: nil, idempotencyKey: DistributionQueuePolicy.newKey(prefix: DistributionQueuePolicy.paymentKeyPrefix))
    }

    /// Queues a return under `idempotencyKey` (one row per key — see `enqueueOrder`).
    @discardableResult
    func enqueueReturn(_ input: ReturnInput, outletName: String?, idempotencyKey: String) -> PendingReturn {
        if let i = DistributionQueuePolicy.rowIndex(withKey: idempotencyKey, in: returns) { return returns[i] }
        adoptLegacyRows()
        let row = PendingReturn(id: UUID(), idempotencyKey: idempotencyKey, userKey: newRowKey(), input: input,
                                createdAt: Date(), attempt: 0, lastError: nil, isSynced: false, outletName: outletName,
                                clientId: SellingCompany.selectedId())
        returns.insert(row, at: 0)
        persistReturns()
        return row
    }

    func enqueueReturn(_ input: ReturnInput) -> PendingReturn {
        enqueueReturn(input, outletName: nil, idempotencyKey: DistributionQueuePolicy.newKey(prefix: DistributionQueuePolicy.returnKeyPrefix))
    }

    // ── Mutate ───────────────────────────────────────────────────────

    /// The server has the write: the row is finished (and any earlier error forgotten).
    func markSynced(_ kind: DistributionWriteKind, id: UUID) {
        switch kind {
        case .order:
            if let i = orders.firstIndex(where: { $0.id == id }) { orders[i].isSynced = true; orders[i].lastError = nil; persistOrders() }
        case .payment:
            if let i = payments.firstIndex(where: { $0.id == id }) { payments[i].isSynced = true; payments[i].lastError = nil; persistPayments() }
        case .goodsReturn:
            if let i = returns.firstIndex(where: { $0.id == id }) { returns[i].isSynced = true; returns[i].lastError = nil; persistReturns() }
        }
    }

    /// A send that did not get through (offline, 5xx, …): remember why, keep the row waiting.
    func recordError(_ kind: DistributionWriteKind, id: UUID, error: String) {
        switch kind {
        case .order:
            if let i = orders.firstIndex(where: { $0.id == id }) { orders[i].attempt += 1; orders[i].lastError = error; persistOrders() }
        case .payment:
            if let i = payments.firstIndex(where: { $0.id == id }) { payments[i].attempt += 1; payments[i].lastError = error; persistPayments() }
        case .goodsReturn:
            if let i = returns.firstIndex(where: { $0.id == id }) { returns[i].attempt += 1; returns[i].lastError = error; persistReturns() }
        }
    }

    /// The server gave a final "no": the row is marked failed (`lastError` = "Rejected: …"), never sent again, and
    /// stays in the list until the rep dismisses it.
    func markRejected(_ kind: DistributionWriteKind, id: UUID, message: String) {
        recordError(kind, id: id, error: DistributionQueuePolicy.rejectedError(message))
    }

    /// Drops a row that has not been accepted — used for a row whose inline send was refused while the rep was
    /// still on the screen (they were told; nothing is kept). A synced row is never deleted here.
    func deleteUnsynced(_ kind: DistributionWriteKind, id: UUID) {
        switch kind {
        case .order:
            let before = orders.count
            orders.removeAll { $0.id == id && !$0.isSynced }
            if orders.count != before { persistOrders() }
        case .payment:
            let before = payments.count
            payments.removeAll { $0.id == id && !$0.isSynced }
            if payments.count != before { persistPayments() }
        case .goodsReturn:
            let before = returns.count
            returns.removeAll { $0.id == id && !$0.isSynced }
            if returns.count != before { persistReturns() }
        }
    }

    /// The rep dismissing a failed row from the list. Only a rejected row can be dismissed; a waiting one stays.
    func dismissRejected(_ item: DistributionQueuePolicy.QueueItem) {
        guard item.failed else { return }
        deleteUnsynced(item.kind, id: item.rowId)
    }

    // ── Read ─────────────────────────────────────────────────────────

    /// The rows still to be sent for the *current* user — never a previously logged-in user's (safety against a
    /// cross-user leak on logout), never a row the server finally refused. Oldest first within each kind.
    func sendableForCurrentUser() -> (orders: [PendingOrder], payments: [PendingPayment], returns: [PendingReturn]) {
        let who = identityProvider()
        return (
            DistributionQueuePolicy.sendable(orders, identity: who),
            DistributionQueuePolicy.sendable(payments, identity: who),
            DistributionQueuePolicy.sendable(returns, identity: who)
        )
    }

    /// Pending rows scoped to the *current* user (see `sendableForCurrentUser`).
    func pendingForCurrentUser() -> (orders: [PendingOrder], payments: [PendingPayment], returns: [PendingReturn]) {
        sendableForCurrentUser()
    }

    /// Everything the current user has queued and not yet had accepted — waiting rows and refused ones — newest first.
    func queueItemsForCurrentUser() -> [DistributionQueuePolicy.QueueItem] {
        let who = identityProvider()
        var items: [DistributionQueuePolicy.QueueItem] = []
        for row in DistributionQueuePolicy.visible(orders, identity: who) { items.append(DistributionQueuePolicy.item(for: row)) }
        for row in DistributionQueuePolicy.visible(payments, identity: who) { items.append(DistributionQueuePolicy.item(for: row)) }
        for row in DistributionQueuePolicy.visible(returns, identity: who) { items.append(DistributionQueuePolicy.item(for: row)) }
        items.sort { (a: DistributionQueuePolicy.QueueItem, b: DistributionQueuePolicy.QueueItem) -> Bool in a.createdAt > b.createdAt }
        return items
    }

    func clearSynced() {
        orders.removeAll { $0.isSynced }
        payments.removeAll { $0.isSynced }
        returns.removeAll { $0.isSynced }
        persistOrders(); persistPayments(); persistReturns()
    }

    /// Forgets synced rows older than `age` seconds. A synced row is only kept for a while so that a repeated call
    /// with the same Idempotency-Key finds it and is answered "already done" instead of sending again.
    func pruneSynced(olderThan age: TimeInterval, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-age)
        let o = orders.count, p = payments.count, r = returns.count
        orders.removeAll { $0.isSynced && $0.createdAt < cutoff }
        payments.removeAll { $0.isSynced && $0.createdAt < cutoff }
        returns.removeAll { $0.isSynced && $0.createdAt < cutoff }
        if orders.count != o { persistOrders() }
        if payments.count != p { persistPayments() }
        if returns.count != r { persistReturns() }
    }
}
