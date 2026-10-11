//
//  DistributionQueuePolicyTests.swift
//  KinematicTests
//
//  The distribution offline write queue's rules: one stable Idempotency-Key per submission, what a server answer
//  means (done / hold / reject), how a refused row is marked and stays visible, which rows the sender may send
//  (the signed-in user's, not synced, not refused, oldest first), and the summary the rep sees.
//

import XCTest
@testable import Kinematic

private struct Boom: Error {}

@MainActor
final class DistributionQueuePolicyTests: XCTestCase {

    private typealias Policy = DistributionQueuePolicy

    // MARK: - Idempotency keys

    func testANewKeyCarriesTheKindPrefixAndIsUnique() {
        let a = Policy.newKey(prefix: Policy.paymentKeyPrefix)
        let b = Policy.newKey(prefix: Policy.paymentKeyPrefix)
        XCTAssertTrue(a.hasPrefix("pay-"))
        XCTAssertTrue(Policy.newKey(prefix: Policy.orderKeyPrefix).hasPrefix("ord-"))
        XCTAssertTrue(Policy.newKey(prefix: Policy.returnKeyPrefix).hasPrefix("ret-"))
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(Policy.isUsableKey(a))
    }

    func testTheCallersKeyIsReusedOnEveryRetryAndAFreshOneOnlyWhenNoneIsUsable() {
        let key = Policy.newKey(prefix: "pay-")
        // Same key in, same key out — however many times the submission is retried.
        for _ in 0..<3 { XCTAssertEqual(Policy.keyOrNew(key, prefix: "pay-"), key) }
        XCTAssertTrue(Policy.keyOrNew(nil, prefix: "pay-").hasPrefix("pay-"))
        XCTAssertTrue(Policy.keyOrNew("  ", prefix: "pay-").hasPrefix("pay-"))
        XCTAssertTrue(Policy.keyOrNew(String(repeating: "x", count: 201), prefix: "pay-").hasPrefix("pay-"))
    }

    func testKeysLongerThanTheServerAcceptsAreNotUsable() {
        XCTAssertTrue(Policy.isUsableKey(String(repeating: "k", count: 200)))
        XCTAssertFalse(Policy.isUsableKey(String(repeating: "k", count: 201)))
        XCTAssertFalse(Policy.isUsableKey(""))
        XCTAssertFalse(Policy.isUsableKey(nil))
    }

    // MARK: - What an HTTP answer means

    func test2xxFinishesTheRow() {
        for code in [200, 201, 204] { XCTAssertEqual(Policy.verdict(httpStatus: code), .done, "\(code)") }
    }

    func test408429And5xxHoldTheRowForARetry() {
        for code in [408, 429, 500, 502, 503, 504] { XCTAssertEqual(Policy.verdict(httpStatus: code), .hold, "\(code)") }
    }

    func testAnyOther4xxIsAFinalRejectionNotARetry() {
        for code in [400, 403, 404, 405, 410, 413, 422] { XCTAssertEqual(Policy.verdict(httpStatus: code), .reject, "\(code)") }
    }

    func test401HoldsTheRowBecauseAMoneyRowIsNotThrownAwayForASessionThatNeedsRefreshing() {
        XCTAssertEqual(Policy.verdict(httpStatus: 401), .hold)
    }

    func testNoHTTPAnswerAtAllIsAHoldNotARejection() {
        XCTAssertEqual(Policy.verdict(httpStatus: 0), .hold)
    }

    func testAnExplicitDuplicateOfThisKey409FinishesTheRowForOrdersPaymentsAndReturns() {
        for message in ["Duplicate payment (idempotency or payment_no)",
                        "Duplicate order (idempotency or order_no)",
                        "Duplicate return (idempotency or return_no)"] {
            XCTAssertEqual(Policy.verdict(httpStatus: 409, serverMessage: message), .done, message)
        }
    }

    func testOtherOrderConflictsStayRejections() {
        XCTAssertEqual(Policy.verdict(httpStatus: 409, serverMessage: "PRICE_MISMATCH: server=100 client=90"), .reject)
        XCTAssertEqual(Policy.verdict(httpStatus: 409, serverMessage: nil), .reject)
    }

    func testForPaymentsAny409MeansAlreadyRecorded() {
        XCTAssertEqual(Policy.verdict(httpStatus: 409, serverMessage: nil, conflictMeansRecorded: true), .done)
        XCTAssertEqual(Policy.verdict(httpStatus: 409, serverMessage: "Duplicate payment (idempotency or payment_no)",
                                      conflictMeansRecorded: true), .done)
        XCTAssertEqual(Policy.verdict(httpStatus: 409, serverMessage: "Conflict", conflictMeansRecorded: true), .done)
    }

    func testTheIdempotencyMiddlewaresOwnRefusalsAreNeverTreatedAsRecorded() {
        for message in ["Idempotency-Key reused with a different request body",
                        "Idempotency-Key belongs to a different user",
                        "Idempotency-Key too long"] {
            XCTAssertEqual(Policy.verdict(httpStatus: 409, serverMessage: message, conflictMeansRecorded: true), .reject, message)
            XCTAssertEqual(Policy.verdict(httpStatus: 409, serverMessage: message), .reject, message)
        }
    }

    func testOnly409CanMeanAlreadyRecorded() {
        XCTAssertFalse(Policy.isAlreadyRecorded(httpStatus: 400, serverMessage: "Duplicate payment (idempotency)", anyConflict: true))
        XCTAssertTrue(Policy.isAlreadyRecorded(httpStatus: 409, serverMessage: "Duplicate payment (idempotency)"))
    }

    // MARK: - What a request that threw means

    func testNoConnectionTimeoutsAndOtherTransportFailuresHoldTheRow() {
        let codes: [URLError.Code] = [.notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotFindHost,
                                      .cancelled, .secureConnectionFailed, .badServerResponse]
        for code in codes {
            XCTAssertEqual(Policy.verdict(forThrown: URLError(code)), .hold, "\(code)")
        }
        XCTAssertEqual(Policy.verdict(forThrown: CancellationError()), .hold)
    }

    func testARequestThatCanNeverBeBuiltOrABugIsARejectionNotARetryLoop() {
        XCTAssertEqual(Policy.verdict(forThrown: URLError(.badURL)), .reject)
        XCTAssertEqual(Policy.verdict(forThrown: URLError(.unsupportedURL)), .reject)
        XCTAssertEqual(Policy.verdict(forThrown: Boom()), .reject)
    }

    func testOnlyAMissingConnectionStopsTheDrain() {
        XCTAssertTrue(Policy.isOffline(URLError(.notConnectedToInternet)))
        XCTAssertTrue(Policy.isOffline(URLError(.timedOut)))
        XCTAssertTrue(Policy.isOffline(CancellationError()))
        XCTAssertFalse(Policy.isOffline(URLError(.secureConnectionFailed)))
        XCTAssertFalse(Policy.isOffline(Boom()))
    }

    func testThrownErrorsReadAsPlainSentences() {
        XCTAssertEqual(Policy.message(forThrown: URLError(.notConnectedToInternet)), "No internet connection")
        XCTAssertEqual(Policy.message(forThrown: URLError(.timedOut)), "The request timed out")
        XCTAssertEqual(Policy.message(forThrown: URLError(.cannotFindHost)), "Couldn't reach the server")
    }

    // MARK: - The server's reason

    private func body(_ json: String) -> Data { Data(json.utf8) }

    func testTheMostSpecificServerReasonIsShown() {
        XCTAssertEqual(
            Policy.serverMessage(body: body(#"{"success":false,"error":"Validation failed","details":[{"path":["amount"],"message":"Number must be greater than 0"}]}"#), httpStatus: 400),
            "Number must be greater than 0")
        XCTAssertEqual(
            Policy.serverMessage(body: body(#"{"success":false,"error":"No distributor for this outlet"}"#), httpStatus: 400),
            "No distributor for this outlet")
        // details with nothing usable falls back to the error line.
        XCTAssertEqual(
            Policy.serverMessage(body: body(#"{"error":"E","details":[{"path":["a"]}]}"#), httpStatus: 400), "E")
        // An error that is an object with a message.
        XCTAssertEqual(
            Policy.serverMessage(body: body(#"{"error":{"code":"X","message":"Boom"}}"#), httpStatus: 400), "Boom")
    }

    func testAnEmptyOrNonJSONBodyFallsBackToSomethingReadable() {
        XCTAssertEqual(Policy.serverMessage(body: nil, httpStatus: 403), "HTTP 403")
        XCTAssertEqual(Policy.serverMessage(body: Data(), httpStatus: 403), "HTTP 403")
        XCTAssertEqual(Policy.serverMessage(body: body("   "), httpStatus: 500), "HTTP 500")
        XCTAssertEqual(Policy.serverMessage(body: body("Bad Gateway"), httpStatus: 502), "Bad Gateway")
        XCTAssertEqual(Policy.serverMessage(body: body(#"{"success":false}"#), httpStatus: 400), #"{"success":false}"#)
    }

    func testALongReasonIsCutAt300Characters() {
        let long = String(repeating: "a", count: 400)
        XCTAssertEqual(Policy.serverMessage(body: body("{\"error\":\"\(long)\"}"), httpStatus: 400).count, 300)
    }

    // MARK: - Refused rows stay visible

    func testARejectedRowIsMarkedAndRecognised() {
        let stored = Policy.rejectedError("Daily collection cap exceeded")
        XCTAssertEqual(stored, "Rejected: Daily collection cap exceeded")
        XCTAssertTrue(Policy.isRejected(lastError: stored))
        XCTAssertEqual(Policy.displayError(stored), "Daily collection cap exceeded")
    }

    func testATransientErrorIsNotARejection() {
        XCTAssertFalse(Policy.isRejected(lastError: "HTTP 503: Service Unavailable"))
        XCTAssertFalse(Policy.isRejected(lastError: "No internet connection"))
        XCTAssertFalse(Policy.isRejected(lastError: nil))
        XCTAssertEqual(Policy.displayError("HTTP 503: x"), "HTTP 503: x")
        XCTAssertNil(Policy.displayError(nil))
        XCTAssertNil(Policy.displayError("  "))
    }

    func testTheSavedMessageIsTheOneTheContractAsksFor() {
        XCTAssertEqual(Policy.savedMessage, "Saved — will upload when online")
    }

    // MARK: - Replay timing

    func testTheRetryDelayGrowsAndIsCapped() {
        XCTAssertEqual(Policy.retryDelay(attempt: 0), 30)
        XCTAssertEqual(Policy.retryDelay(attempt: 1), 60)
        XCTAssertEqual(Policy.retryDelay(attempt: 2), 120)
        XCTAssertEqual(Policy.retryDelay(attempt: 3), 240)
        XCTAssertEqual(Policy.retryDelay(attempt: 4), 480)
        XCTAssertEqual(Policy.retryDelay(attempt: 5), 900)
        XCTAssertEqual(Policy.retryDelay(attempt: 40), 900)
        XCTAssertEqual(Policy.retryDelay(attempt: -3), 30)
    }

    // MARK: - Which rows

    private let me = QueueOwnership.Identity(userId: "user-1", token: "", sessionStart: nil)

    private func paymentInput(amount: Double = 500, mode: String = "cash") -> PaymentInput {
        PaymentInput(outlet_id: "o-1", mode: mode, amount: amount, reference: nil, cheque_bank: nil, cheque_date: nil,
                     cheque_image_url: nil, applied_to_invoices: nil, gps: nil)
    }

    private func payment(_ key: String, user: String = "u:user-1", at seconds: TimeInterval = 0, error: String? = nil,
                         synced: Bool = false, outlet: String? = nil, amount: Double = 500, mode: String = "cash") -> PendingPayment {
        PendingPayment(id: UUID(), idempotencyKey: key, userKey: user, input: paymentInput(amount: amount, mode: mode),
                       createdAt: Date(timeIntervalSince1970: seconds), attempt: 0, lastError: error, isSynced: synced,
                       outletName: outlet)
    }

    func testTheSenderGetsOnlyTheSignedInUsersWaitingRowsOldestFirst() {
        let rows = [
            payment("newer", at: 200),
            payment("older", at: 100),
            payment("refused", at: 50, error: Policy.rejectedError("No distributor for this outlet")),
            payment("done", at: 60, synced: true),
            payment("someone-else", user: "u:user-2", at: 70),
        ]
        let sendable = Policy.sendable(rows, identity: me)
        XCTAssertEqual(sendable.map { $0.idempotencyKey }, ["older", "newer"])
    }

    func testTheRepSeesWaitingAndRefusedRowsOfTheirOwnOnly() {
        let rows = [
            payment("waiting", at: 100),
            payment("refused", at: 50, error: Policy.rejectedError("no")),
            payment("done", at: 60, synced: true),
            payment("someone-else", user: "u:user-2", at: 70),
        ]
        let visible = Policy.visible(rows, identity: me)
        XCTAssertEqual(Set(visible.map { $0.idempotencyKey }), Set(["waiting", "refused"]))
    }

    func testARowWithNoOwnerIsNobodysToSend() {
        // Queued with no user id and an empty token (never sent by this user): not provably the signed-in user's.
        let rows = [payment("orphan", user: "")]
        XCTAssertTrue(Policy.sendable(rows, identity: me).isEmpty)
    }

    func testOneRowPerIdempotencyKey() {
        let rows = [payment("a"), payment("b")]
        XCTAssertEqual(Policy.rowIndex(withKey: "b", in: rows), 1)
        XCTAssertNil(Policy.rowIndex(withKey: "missing", in: rows))
    }

    // MARK: - The queue list

    func testAPaymentRowReadsAsTheOutletAmountAndMode() {
        let item = Policy.item(for: payment("p", error: "No internet connection", outlet: " Sri Balaji ", amount: 1250.5, mode: "upi"))
        XCTAssertEqual(item.kind, .payment)
        XCTAssertEqual(item.title, "Sri Balaji")
        XCTAssertEqual(item.detail, "Payment · ₹1,250.50 · UPI")
        XCTAssertEqual(item.error, "No internet connection")
        XCTAssertFalse(item.failed)
        XCTAssertEqual(item.key, "p")
    }

    func testARefusedPaymentShowsTheReasonAndIsMarkedFailed() {
        let item = Policy.item(for: payment("p", error: Policy.rejectedError("Daily collection cap exceeded")))
        XCTAssertTrue(item.failed)
        XCTAssertEqual(item.error, "Daily collection cap exceeded")
        XCTAssertEqual(item.title, "Payment")
    }

    func testAnOrderAndAReturnRowReadAsTheyShould() {
        let orderInput = OrderInput(outlet_id: "o-1", distributor_id: nil, visit_id: nil, items: [], gps: nil, notes: nil, client_total: 1234.5)
        let order = PendingOrder(id: UUID(), idempotencyKey: "ord-1", userKey: "u:user-1", outletId: "o-1", outletName: nil,
                                 visitId: nil, input: orderInput, clientTotal: 1234.5, createdAt: Date(timeIntervalSince1970: 1),
                                 attempt: 2, lastError: nil, isSynced: false)
        let orderItem = Policy.item(for: order)
        XCTAssertEqual(orderItem.kind, .order)
        XCTAssertEqual(orderItem.title, "Order")
        XCTAssertEqual(orderItem.detail, "Order · ₹1,234.50")
        XCTAssertEqual(orderItem.attempt, 2)

        let returnInput = ReturnInput(outlet_id: "o-1", original_invoice_id: "i-1", reason_code: "near_expiry", reason_notes: nil,
                                      photo_urls: ["https://x/y.jpg"], items: [], gps: nil)
        let ret = PendingReturn(id: UUID(), idempotencyKey: "ret-1", userKey: "u:user-1", input: returnInput,
                                createdAt: Date(timeIntervalSince1970: 2), attempt: 0, lastError: nil, isSynced: false)
        let returnItem = Policy.item(for: ret)
        XCTAssertEqual(returnItem.kind, .goodsReturn)
        XCTAssertEqual(returnItem.detail, "Return · near expiry")
        XCTAssertNotEqual(orderItem.id, returnItem.id)
    }

    // MARK: - What the rep sees

    private func summary(pending: Int = 0, failed: Int = 0) -> Policy.QueueSummary {
        Policy.QueueSummary(pending: pending, failed: failed)
    }

    func testNothingIsShownWhenNothingIsQueued() {
        XCTAssertNil(Policy.summaryLine(Policy.QueueSummary()))
        XCTAssertEqual(Policy.badgeSuffix(Policy.QueueSummary()), "")
    }

    func testTheSummaryNamesWhatIsWaitingAndWhatFailed() {
        XCTAssertEqual(Policy.summaryLine(summary(pending: 1)), "1 item saved — will upload when online")
        XCTAssertEqual(Policy.summaryLine(summary(pending: 3)), "3 items saved — will upload when online")
        XCTAssertEqual(Policy.summaryLine(summary(failed: 1)), "1 failed — tap to review")
        XCTAssertEqual(Policy.summaryLine(summary(failed: 2)), "2 failed — tap to review")
        XCTAssertEqual(Policy.summaryLine(summary(pending: 2, failed: 1)),
                       "2 items saved — will upload when online · 1 failed — tap to review")
    }

    func testTheMenuBadgeCountsWaitingAndFailed() {
        XCTAssertEqual(Policy.badgeSuffix(summary(pending: 2)), " (2 waiting)")
        XCTAssertEqual(Policy.badgeSuffix(summary(failed: 1)), " (1 failed)")
        XCTAssertEqual(Policy.badgeSuffix(summary(pending: 2, failed: 1)), " (2 waiting, 1 failed)")
    }

    func testTheSummaryCountsWaitingAndFailedItems() {
        let items = [
            Policy.item(for: payment("a")),
            Policy.item(for: payment("b")),
            Policy.item(for: payment("c", error: Policy.rejectedError("no"))),
        ]
        XCTAssertEqual(Policy.summary(of: items), Policy.QueueSummary(pending: 2, failed: 1))
    }
}
