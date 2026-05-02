// OrderCache — disk-persisted offline queue for distribution mutations.
//
// Mirrors the Android Room queue: every queued order/payment/return is given a
// stable Idempotency-Key at confirm time and persisted to a JSON file in the
// app's Documents directory. Flush runs on app foreground / network change.
// The queue is keyed by user (last 24 chars of the access token) so a re-login
// under a different account never flushes the previous user's pending writes.

import Foundation

struct PendingOrder: Codable, Identifiable {
    let id: UUID
    let idempotencyKey: String
    let userKey: String
    let outletId: String
    let outletName: String?
    let visitId: String?
    let input: OrderInput
    let clientTotal: Double
    let createdAt: Date
    var attempt: Int
    var lastError: String?
    var isSynced: Bool
}

struct PendingPayment: Codable, Identifiable {
    let id: UUID
    let idempotencyKey: String
    let userKey: String
    let input: PaymentInput
    let createdAt: Date
    var attempt: Int
    var lastError: String?
    var isSynced: Bool
}

struct PendingReturn: Codable, Identifiable {
    let id: UUID
    let idempotencyKey: String
    let userKey: String
    let input: ReturnInput
    let createdAt: Date
    var attempt: Int
    var lastError: String?
    var isSynced: Bool
}

@MainActor
final class OrderCache: ObservableObject {
    static let shared = OrderCache()

    @Published private(set) var orders: [PendingOrder] = []
    @Published private(set) var payments: [PendingPayment] = []
    @Published private(set) var returns: [PendingReturn] = []

    private let queue = DispatchQueue(label: "com.kinematic.ordercache", qos: .utility)
    private var ordersFile: URL  { docs.appendingPathComponent("pending_orders.json") }
    private var paymentsFile: URL { docs.appendingPathComponent("pending_payments.json") }
    private var returnsFile: URL  { docs.appendingPathComponent("pending_returns.json") }

    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    init() {
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

    static func userKey() -> String { String(Session.sharedToken.suffix(24)) }

    // ── Queue ────────────────────────────────────────────────────────
    func enqueueOrder(input: OrderInput, clientTotal: Double, outletName: String?, visitId: String?) -> PendingOrder {
        let row = PendingOrder(
            id: UUID(),
            idempotencyKey: "ord-" + UUID().uuidString,
            userKey: Self.userKey(),
            outletId: input.outlet_id,
            outletName: outletName,
            visitId: visitId,
            input: input,
            clientTotal: clientTotal,
            createdAt: Date(),
            attempt: 0,
            lastError: nil,
            isSynced: false
        )
        orders.insert(row, at: 0)
        persistOrders()
        return row
    }

    func enqueuePayment(_ input: PaymentInput) -> PendingPayment {
        let row = PendingPayment(id: UUID(), idempotencyKey: "pay-" + UUID().uuidString, userKey: Self.userKey(), input: input, createdAt: Date(), attempt: 0, lastError: nil, isSynced: false)
        payments.insert(row, at: 0)
        persistPayments()
        return row
    }

    func enqueueReturn(_ input: ReturnInput) -> PendingReturn {
        let row = PendingReturn(id: UUID(), idempotencyKey: "ret-" + UUID().uuidString, userKey: Self.userKey(), input: input, createdAt: Date(), attempt: 0, lastError: nil, isSynced: false)
        returns.insert(row, at: 0)
        persistReturns()
        return row
    }

    // ── Mutate ───────────────────────────────────────────────────────
    func markOrderSynced(_ id: UUID) {
        if let i = orders.firstIndex(where: { $0.id == id }) {
            orders[i].isSynced = true
            persistOrders()
        }
    }

    func recordOrderError(_ id: UUID, error: String) {
        if let i = orders.firstIndex(where: { $0.id == id }) {
            orders[i].attempt += 1
            orders[i].lastError = error
            persistOrders()
        }
    }

    func markPaymentSynced(_ id: UUID) {
        if let i = payments.firstIndex(where: { $0.id == id }) {
            payments[i].isSynced = true; persistPayments()
        }
    }
    func recordPaymentError(_ id: UUID, error: String) {
        if let i = payments.firstIndex(where: { $0.id == id }) {
            payments[i].attempt += 1; payments[i].lastError = error; persistPayments()
        }
    }
    func markReturnSynced(_ id: UUID) {
        if let i = returns.firstIndex(where: { $0.id == id }) {
            returns[i].isSynced = true; persistReturns()
        }
    }
    func recordReturnError(_ id: UUID, error: String) {
        if let i = returns.firstIndex(where: { $0.id == id }) {
            returns[i].attempt += 1; returns[i].lastError = error; persistReturns()
        }
    }

    /// Pending rows scoped to the *current* user — never returns rows belonging
    /// to a previously logged-in user (safety against cross-user leak on logout).
    func pendingForCurrentUser() -> (orders: [PendingOrder], payments: [PendingPayment], returns: [PendingReturn]) {
        let key = Self.userKey()
        return (
            orders.filter { !$0.isSynced && $0.userKey == key },
            payments.filter { !$0.isSynced && $0.userKey == key },
            returns.filter { !$0.isSynced && $0.userKey == key }
        )
    }

    func clearSynced() {
        orders.removeAll { $0.isSynced }
        payments.removeAll { $0.isSynced }
        returns.removeAll { $0.isSynced }
        persistOrders(); persistPayments(); persistReturns()
    }
}
