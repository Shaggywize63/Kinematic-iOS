// DistributionSync — sends the distribution writes (orders, payments, returns): saved to the OrderCache queue FIRST
// under one stable Idempotency-Key, sent straight away while the rep waits on the screen, and whatever could not be
// delivered stays queued and is retried — when the app returns to the foreground, when the network comes back, and
// on a backoff while something is still waiting. Mirrors the Android `DistributionRepository` + sync worker.
//
// The rules live in DistributionQueuePolicy (pure, unit-tested):
//   * 2xx, or "this key is already recorded"  → the row is finished (synced);
//   * no connection / timeout / 408 / 429 / 5xx / 401 → the row is kept and tried again (same key — no duplicate);
//   * any other 4xx → the server's final "no": the row is marked failed, never replayed, shown to the rep.
// A payment the server accepted but whose reply could not be read is still finished: a 2xx is a 2xx.

import Foundation
import Combine
import Network

@MainActor
final class DistributionSync: ObservableObject {
    static let shared = DistributionSync()

    /// What happened to a write the rep just submitted.
    enum SubmitOutcome: Equatable {
        /// The server accepted it. `reference` = the order / payment / return number when the reply was readable;
        /// `detail` = for a payment, where the money went ("₹300.00 → INV-1 · ₹200.00 on account").
        case synced(key: String, reference: String?, detail: String?)
        /// Saved on the phone; it will be uploaded when it can be (`DistributionQueuePolicy.savedMessage`).
        case queued(key: String)
        /// The server said no and it will not be retried. Nothing was saved: the rep can fix it and resubmit
        /// (the screen must then use a NEW key — this one is spent).
        case rejected(message: String)
    }

    /// What one send of a queued row came to.
    private enum SyncOutcome {
        case synced(reference: String?, detail: String?)
        case retry(message: String, offline: Bool)
        case rejected(message: String)
    }

    private struct SendPlan {
        let kind: DistributionWriteKind
        let rowId: UUID
        let key: String
        let path: String
        let body: Encodable
        /// Payments answer a retry of an already-recorded payment with 409: that row is done, not failed.
        let conflictMeansRecorded: Bool
        /// The company the write was taken for (nil = the live selection).
        var clientId: String? = nil
    }

    /// True while a drain of the queue is running (for a spinner on "Retry").
    @Published private(set) var isSending = false

    /// How long the rep waits on the screen for the first send before it is left to the background retry.
    static let inlineTimeout: TimeInterval = 12
    /// How long a background send may take.
    static let backgroundTimeout: TimeInterval = 30
    /// Synced rows are kept this long so a repeated call with the same key is answered "already done".
    static let syncedRetention: TimeInterval = 24 * 3600

    private let cache: OrderCache
    private var inFlight = Set<UUID>()
    private var isFlushing = false
    private var retryTask: Task<Void, Never>?
    private var retryRound = 0
    private var pathMonitor: NWPathMonitor?

    private init() {
        self.cache = OrderCache.shared
        startWatchingConnectivity()
    }

    /// Drain the moment the network comes back (same NWPathMonitor idea as AttendanceCache). Idle when nobody is
    /// signed in or nothing is queued.
    private func startWatchingConnectivity() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.flushIfSignedIn() }
        }
        monitor.start(queue: DispatchQueue(label: "com.kinematic.distributionsync.path", qos: .utility))
        pathMonitor = monitor
    }

    // MARK: - App-level entry

    /// Called when the app starts / returns to the foreground: drains the queue, but only for a signed-in user whose
    /// client has the distribution package (nothing is created or started for anyone else).
    static func kickIfDistribution() async {
        guard Session.isAuthenticated, Session.currentUser?.hasDistribution == true else { return }
        await DistributionSync.shared.flushAll()
    }

    private func flushIfSignedIn() async {
        guard Session.isAuthenticated else { return }
        await flushAll()
    }

    // MARK: - Submitting (save first, then send)

    /// Saves an order, tries to send it, and says what happened. `idempotencyKey` is made once by the screen and
    /// reused by every retry, so one tap is one order on the server however many times it is re-sent.
    func recordOrder(input: OrderInput, clientTotal: Double, outletName: String?, visitId: String?,
                     idempotencyKey: String) async -> SubmitOutcome {
        let key = DistributionQueuePolicy.keyOrNew(idempotencyKey, prefix: DistributionQueuePolicy.orderKeyPrefix)
        let row = cache.enqueueOrder(input: input, clientTotal: clientTotal, outletName: outletName,
                                     visitId: visitId, idempotencyKey: key)
        return await submitInline(kind: .order, rowId: row.id, key: key, isSynced: row.isSynced,
                                  lastError: row.lastError, plan: plan(for: row))
    }

    /// Saves a payment, tries to send it, and says what happened (see `recordOrder`). `payload` is the allocation
    /// choice (`PaymentAllocation.payload`). Never needs the network to SAVE.
    func recordPayment(input: PaymentInput, payload: PaymentAllocation.Payload, outletName: String?,
                       idempotencyKey: String) async -> SubmitOutcome {
        let key = DistributionQueuePolicy.keyOrNew(idempotencyKey, prefix: DistributionQueuePolicy.paymentKeyPrefix)
        let row = cache.enqueuePayment(PaymentAllocation.applyTo(input, payload: payload), outletName: outletName, idempotencyKey: key)
        return await submitInline(kind: .payment, rowId: row.id, key: key, isSynced: row.isSynced,
                                  lastError: row.lastError, plan: plan(for: row))
    }

    /// Saves a return, tries to send it, and says what happened (see `recordOrder`).
    func recordReturn(input: ReturnInput, outletName: String?, idempotencyKey: String) async -> SubmitOutcome {
        let key = DistributionQueuePolicy.keyOrNew(idempotencyKey, prefix: DistributionQueuePolicy.returnKeyPrefix)
        let row = cache.enqueueReturn(input, outletName: outletName, idempotencyKey: key)
        return await submitInline(kind: .goodsReturn, rowId: row.id, key: key, isSynced: row.isSynced,
                                  lastError: row.lastError, plan: plan(for: row))
    }

    private func submitInline(kind: DistributionWriteKind, rowId: UUID, key: String, isSynced: Bool,
                              lastError: String?, plan: SendPlan) async -> SubmitOutcome {
        // The same key again: answer from what is already known instead of sending a second time.
        if isSynced { return .synced(key: key, reference: nil, detail: nil) }
        if DistributionQueuePolicy.isRejected(lastError: lastError) {
            cache.deleteUnsynced(kind, id: rowId)
            return .rejected(message: DistributionQueuePolicy.displayError(lastError) ?? "The server did not accept this")
        }
        if inFlight.contains(rowId) { return .queued(key: key) }

        let result = await attempt(plan, timeout: Self.inlineTimeout)
        switch result {
        case .synced(let reference, let detail):
            return .synced(key: key, reference: reference, detail: detail)
        case .retry:
            scheduleRetry()
            return .queued(key: key)
        case .rejected(let message):
            // The rep is told right now; nothing is kept.
            cache.deleteUnsynced(kind, id: rowId)
            return .rejected(message: message)
        }
    }

    // MARK: - Draining the queue

    /// Sends everything waiting for the signed-in user: orders, then payments, then returns, oldest first within
    /// each. Stops at the first send that failed for lack of a connection (the rest would fail the same way). A
    /// row the server refuses is marked failed and the drain carries on. If anything is still waiting afterwards a
    /// retry is scheduled with a growing delay.
    func flushAll() async {
        guard !isFlushing else { return }
        isFlushing = true
        isSending = true
        defer { isFlushing = false; isSending = false }

        cache.adoptLegacyRows()
        cache.pruneSynced(olderThan: Self.syncedRetention)
        let batch = cache.sendableForCurrentUser()
        var stillWaiting = false

        for row in batch.orders where !inFlight.contains(row.id) {
            let outcome = await attempt(plan(for: row), timeout: Self.backgroundTimeout)
            if case .retry(_, let offline) = outcome {
                stillWaiting = true
                if offline { scheduleRetry(); return }
            }
        }
        for row in batch.payments where !inFlight.contains(row.id) {
            let outcome = await attempt(plan(for: row), timeout: Self.backgroundTimeout)
            if case .retry(_, let offline) = outcome {
                stillWaiting = true
                if offline { scheduleRetry(); return }
            }
        }
        for row in batch.returns where !inFlight.contains(row.id) {
            let outcome = await attempt(plan(for: row), timeout: Self.backgroundTimeout)
            if case .retry(_, let offline) = outcome {
                stillWaiting = true
                if offline { scheduleRetry(); return }
            }
        }

        if stillWaiting {
            scheduleRetry()
        } else {
            retryRound = 0
            retryTask?.cancel()
            retryTask = nil
        }
    }

    /// Try again after a delay that grows with every round (30 s … 15 min), like the Android worker's backoff.
    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = DistributionQueuePolicy.retryDelay(attempt: retryRound)
        retryRound += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            self?.runScheduledFlush()
        }
    }

    /// Starts the drain in a task of its own, so a later `scheduleRetry()` cancelling the timer above can never
    /// cancel a drain that is already running.
    private func runScheduledFlush() {
        Task { await flushIfSignedIn() }
    }

    // MARK: - One send

    private func plan(for row: PendingOrder) -> SendPlan {
        SendPlan(kind: .order, rowId: row.id, key: row.idempotencyKey, path: "/salesman/orders",
                 body: row.input, conflictMeansRecorded: false, clientId: row.clientId)
    }

    private func plan(for row: PendingPayment) -> SendPlan {
        SendPlan(kind: .payment, rowId: row.id, key: row.idempotencyKey, path: "/salesman/payments",
                 body: row.input, conflictMeansRecorded: true, clientId: row.clientId)
    }

    private func plan(for row: PendingReturn) -> SendPlan {
        SendPlan(kind: .goodsReturn, rowId: row.id, key: row.idempotencyKey, path: "/salesman/returns",
                 body: row.input, conflictMeansRecorded: false, clientId: row.clientId)
    }

    /// Sends one queued row from what is on disk (so the first send and every replay are the same bytes) and
    /// records the answer on the row.
    private func attempt(_ plan: SendPlan, timeout: TimeInterval) async -> SyncOutcome {
        inFlight.insert(plan.rowId)
        defer { inFlight.remove(plan.rowId) }

        let response = await DistributionAPI.shared.send(path: plan.path, method: "POST", body: plan.body,
                                                         idempotencyKey: plan.key, timeout: timeout, clientId: plan.clientId)
        if let error = response.error {
            let message = DistributionQueuePolicy.message(forThrown: error)
            switch DistributionQueuePolicy.verdict(forThrown: error) {
            case .reject:
                cache.markRejected(plan.kind, id: plan.rowId, message: message)
                return .rejected(message: message)
            case .done, .hold:
                cache.recordError(plan.kind, id: plan.rowId, error: message)
                return .retry(message: message, offline: DistributionQueuePolicy.isOffline(error))
            }
        }

        let message = DistributionQueuePolicy.serverMessage(body: response.body, httpStatus: response.status)
        let verdict = DistributionQueuePolicy.verdict(httpStatus: response.status, serverMessage: message,
                                                      conflictMeansRecorded: plan.conflictMeansRecorded)
        switch verdict {
        case .done:
            cache.markSynced(plan.kind, id: plan.rowId)
            let reference = SalesmanJSON.reference(fromData: response.body)
            var detail: String? = nil
            if plan.kind == .payment { detail = PaymentAllocation.summary(fromReplyData: response.body) }
            return .synced(reference: reference, detail: detail)
        case .hold:
            cache.recordError(plan.kind, id: plan.rowId, error: "HTTP \(response.status): \(message)")
            return .retry(message: message, offline: false)
        case .reject:
            cache.markRejected(plan.kind, id: plan.rowId, message: message)
            return .rejected(message: message)
        }
    }
}
