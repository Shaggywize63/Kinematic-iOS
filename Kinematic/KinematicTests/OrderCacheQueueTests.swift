//
//  OrderCacheQueueTests.swift
//  KinematicTests
//
//  The distribution offline queue (OrderCache): one row per Idempotency-Key so a second tap or a retry can never
//  become a second order / payment, a refused row is kept visible and never sent again, a synced row is finished,
//  and every list is scoped to the signed-in user. Runs against a temporary directory, never the app's Documents.
//

import XCTest
@testable import Kinematic

@MainActor
final class OrderCacheQueueTests: XCTestCase {

    private func makeCache(user: String = "user-1") -> OrderCache {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ordercache-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { _ = try? FileManager.default.removeItem(at: dir) }
        let cache = OrderCache(directory: dir)
        cache.identityProvider = { QueueOwnership.Identity(userId: user, token: "", sessionStart: nil) }
        return cache
    }

    private func becomeUser(_ user: String, in cache: OrderCache) {
        cache.identityProvider = { QueueOwnership.Identity(userId: user, token: "", sessionStart: nil) }
    }

    private func paymentInput(amount: Double = 500) -> PaymentInput {
        PaymentInput(outlet_id: "o-1", mode: "cash", amount: amount, reference: nil, cheque_bank: nil, cheque_date: nil,
                     cheque_image_url: nil, applied_to_invoices: nil, gps: nil, auto_allocate: true)
    }

    private func orderInput() -> OrderInput {
        OrderInput(outlet_id: "o-1", distributor_id: "d-1", visit_id: nil, items: [], gps: nil, notes: nil, client_total: 100)
    }

    private func returnInput() -> ReturnInput {
        ReturnInput(outlet_id: "o-1", original_invoice_id: "i-1", reason_code: "damaged", reason_notes: nil,
                    photo_urls: ["https://x/y.jpg"], items: [], gps: nil)
    }

    // MARK: - One row per Idempotency-Key

    func testQueuingTheSamePaymentKeyTwiceKeepsTheOneRow() {
        let cache = makeCache()
        let first = cache.enqueuePayment(paymentInput(), outletName: "Sri Balaji", idempotencyKey: "pay-abc")
        let second = cache.enqueuePayment(paymentInput(amount: 999), outletName: "Other", idempotencyKey: "pay-abc")
        XCTAssertEqual(cache.payments.count, 1)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.input.amount, 500)             // the first submission stands
        XCTAssertEqual(second.outletName, "Sri Balaji")
        XCTAssertEqual(first.userKey, "u:user-1")
        XCTAssertEqual(first.input.auto_allocate, true)
    }

    func testDifferentKeysAreDifferentRows() {
        let cache = makeCache()
        _ = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-1")
        _ = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-2")
        XCTAssertEqual(cache.payments.count, 2)
    }

    func testQueuingTheSameOrderOrReturnKeyTwiceKeepsTheOneRow() {
        let cache = makeCache()
        let o1 = cache.enqueueOrder(input: orderInput(), clientTotal: 100, outletName: "A", visitId: nil, idempotencyKey: "ord-1")
        let o2 = cache.enqueueOrder(input: orderInput(), clientTotal: 100, outletName: "A", visitId: nil, idempotencyKey: "ord-1")
        XCTAssertEqual(cache.orders.count, 1)
        XCTAssertEqual(o1.id, o2.id)
        let r1 = cache.enqueueReturn(returnInput(), outletName: nil, idempotencyKey: "ret-1")
        let r2 = cache.enqueueReturn(returnInput(), outletName: nil, idempotencyKey: "ret-1")
        XCTAssertEqual(cache.returns.count, 1)
        XCTAssertEqual(r1.id, r2.id)
    }

    func testAKeylessEnqueueStillGetsItsOwnFreshKey() {
        let cache = makeCache()
        let a = cache.enqueuePayment(paymentInput())
        let b = cache.enqueuePayment(paymentInput())
        XCTAssertNotEqual(a.idempotencyKey, b.idempotencyKey)
        XCTAssertTrue(a.idempotencyKey.hasPrefix("pay-"))
        XCTAssertEqual(cache.payments.count, 2)
    }

    // MARK: - Waiting, refused, finished

    func testAFailedSendKeepsTheRowWaitingAndRemembersWhy() {
        let cache = makeCache()
        let row = cache.enqueuePayment(paymentInput(), outletName: "Sri Balaji", idempotencyKey: "pay-1")
        cache.recordError(.payment, id: row.id, error: "No internet connection")
        XCTAssertEqual(cache.payments[0].attempt, 1)
        XCTAssertEqual(cache.sendableForCurrentUser().payments.count, 1)
        let items = cache.queueItemsForCurrentUser()
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].failed)
        XCTAssertEqual(items[0].error, "No internet connection")
        XCTAssertEqual(DistributionQueuePolicy.summary(of: items), DistributionQueuePolicy.QueueSummary(pending: 1, failed: 0))
    }

    func testARefusedRowIsKeptVisibleButNeverSentAgain() {
        let cache = makeCache()
        let row = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-1")
        cache.markRejected(.payment, id: row.id, message: "No distributor for this outlet")
        XCTAssertTrue(cache.sendableForCurrentUser().payments.isEmpty)
        let items = cache.queueItemsForCurrentUser()
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].failed)
        XCTAssertEqual(items[0].error, "No distributor for this outlet")
        XCTAssertEqual(DistributionQueuePolicy.summary(of: items), DistributionQueuePolicy.QueueSummary(pending: 0, failed: 1))
    }

    func testTheSameKeyAfterARefusalFindsTheRefusedRow() {
        let cache = makeCache()
        let row = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-1")
        cache.markRejected(.payment, id: row.id, message: "no")
        let again = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-1")
        XCTAssertEqual(again.id, row.id)
        XCTAssertTrue(DistributionQueuePolicy.isRejected(lastError: cache.payments[0].lastError))
        XCTAssertEqual(cache.payments.count, 1)
    }

    func testOnlyARefusedRowCanBeDismissed() {
        let cache = makeCache()
        let waiting = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-1")
        let refused = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-2")
        cache.markRejected(.payment, id: refused.id, message: "no")
        let items = cache.queueItemsForCurrentUser()
        let waitingItem = items.first { !$0.failed }
        let failedItem = items.first { $0.failed }
        XCTAssertNotNil(waitingItem)
        XCTAssertNotNil(failedItem)

        if let waitingItem = waitingItem { cache.dismissRejected(waitingItem) }
        XCTAssertEqual(cache.payments.count, 2)              // a waiting row stays queued

        if let failedItem = failedItem { cache.dismissRejected(failedItem) }
        XCTAssertEqual(cache.payments.count, 1)
        XCTAssertEqual(cache.payments[0].id, waiting.id)
    }

    func testASyncedRowIsFinished() {
        let cache = makeCache()
        let row = cache.enqueueOrder(input: orderInput(), clientTotal: 100, outletName: nil, visitId: nil, idempotencyKey: "ord-1")
        cache.recordError(.order, id: row.id, error: "HTTP 503: busy")
        cache.markSynced(.order, id: row.id)
        XCTAssertTrue(cache.orders[0].isSynced)
        XCTAssertNil(cache.orders[0].lastError)
        XCTAssertTrue(cache.sendableForCurrentUser().orders.isEmpty)
        XCTAssertTrue(cache.queueItemsForCurrentUser().isEmpty)
        // Still there, so the same key again is answered "already done" instead of being sent a second time.
        XCTAssertEqual(cache.enqueueOrder(input: orderInput(), clientTotal: 100, outletName: nil, visitId: nil, idempotencyKey: "ord-1").id, row.id)
    }

    func testDroppingARowNeverRemovesASyncedOne() {
        let cache = makeCache()
        let waiting = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-1")
        let done = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-2")
        cache.markSynced(.payment, id: done.id)
        cache.deleteUnsynced(.payment, id: done.id)
        XCTAssertEqual(cache.payments.count, 2)
        cache.deleteUnsynced(.payment, id: waiting.id)
        XCTAssertEqual(cache.payments.count, 1)
        XCTAssertEqual(cache.payments[0].id, done.id)
    }

    func testSyncedRowsAreForgottenAfterTheRetentionAndNothingElseIs() {
        let cache = makeCache()
        let done = cache.enqueueReturn(returnInput(), outletName: nil, idempotencyKey: "ret-1")
        _ = cache.enqueueReturn(returnInput(), outletName: nil, idempotencyKey: "ret-2")
        cache.markSynced(.goodsReturn, id: done.id)
        cache.pruneSynced(olderThan: 3600)                        // just made: kept
        XCTAssertEqual(cache.returns.count, 2)
        cache.pruneSynced(olderThan: 3600, now: Date().addingTimeInterval(2 * 3600))
        XCTAssertEqual(cache.returns.count, 1)                    // the synced one is gone, the waiting one is not
        XCTAssertFalse(cache.returns[0].isSynced)
    }

    // MARK: - Whose rows

    func testAnotherUsersRowsAreNeverSentOrShown() {
        let cache = makeCache(user: "user-1")
        _ = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-1")
        _ = cache.enqueueOrder(input: orderInput(), clientTotal: 100, outletName: nil, visitId: nil, idempotencyKey: "ord-1")
        XCTAssertEqual(cache.queueItemsForCurrentUser().count, 2)

        becomeUser("user-2", in: cache)
        XCTAssertTrue(cache.sendableForCurrentUser().payments.isEmpty)
        XCTAssertTrue(cache.sendableForCurrentUser().orders.isEmpty)
        XCTAssertTrue(cache.queueItemsForCurrentUser().isEmpty)
        XCTAssertEqual(cache.payments.count, 1)                  // not deleted — still there for its owner

        becomeUser("user-1", in: cache)
        XCTAssertEqual(cache.sendableForCurrentUser().payments.count, 1)
        XCTAssertEqual(cache.queueItemsForCurrentUser().count, 2)
    }

    func testANewRowIsKeyedByTheUserIdSoATokenRefreshCannotOrphanIt() {
        let cache = makeCache(user: "user-1")
        let row = cache.enqueuePayment(paymentInput(), outletName: nil, idempotencyKey: "pay-1")
        XCTAssertEqual(row.userKey, "u:user-1")
        // Same person, different (refreshed) token: still theirs.
        cache.identityProvider = { QueueOwnership.Identity(userId: "user-1", token: "a-brand-new-access-token-value", sessionStart: nil) }
        XCTAssertEqual(cache.sendableForCurrentUser().payments.count, 1)
    }
}
