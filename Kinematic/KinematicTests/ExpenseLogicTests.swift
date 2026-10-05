//
//  ExpenseLogicTests.swift
//  KinematicTests
//
//  The rules behind the expense screens: what a line must have to be saved, how a receipt scan fills
//  a line, how a removed receipt is expressed, what a reviewer must write before rejecting, how a
//  claim's history reads — and that the server's JSON decodes into the models.
//

import XCTest
@testable import Kinematic

final class ExpenseLogicTests: XCTestCase {

    private func decodeClaim(_ json: String) throws -> ExpenseClaim {
        try JSONDecoder().decode(ExpenseClaim.self, from: Data(json.utf8))
    }

    private func item(_ id: String, _ amount: Double, _ category: String = "food") throws -> ExpenseClaimItem {
        let json = #"{"id":"\#(id)","category":"\#(category)","amount":\#(amount)}"#
        return try JSONDecoder().decode(ExpenseClaimItem.self, from: Data(json.utf8))
    }

    // MARK: - Decoding what the server sends

    func testDecodesARejectedClaimWithItsRemarksAndLineDecisions() throws {
        let c = try decodeClaim("""
        {"id":"c1","claim_no":"EXP-0007","title":"Pune visit","status":"rejected","currency":"INR","total_amount":1850,
         "approved_amount":null,"review_note":"Hotel receipt is unreadable.","reviewer_name":"Meera Rao","policy_name":"Field sales rep",
         "submit_count":1,"created_at":"2026-10-01T09:00:00Z",
         "ai_flags":[{"code":"receipt_missing","severity":"warn","detail":"Lodging has no receipt.","item_id":"i1","blocking":false}],
         "items":[{"id":"i1","category":"lodging","amount":1500,"receipt_url":"https://x/r.jpg","receipt_signed_url":"https://x/r.jpg?t=1",
                   "decision":"rejected","decision_note":"Blurry"}],
         "approvals":[{"id":"a1","level":1,"round":1,"status":"rejected","note":"Hotel receipt is unreadable.","approver_name":"Meera Rao",
                       "item_decisions":[{"item_id":"i1","category":"lodging","amount":1500,"decision":"rejected","note":"Blurry"}]}]}
        """)
        XCTAssertEqual(c.review_note, "Hotel receipt is unreadable.")
        XCTAssertEqual(c.reviewer_name, "Meera Rao")
        XCTAssertEqual(c.items?.first?.decision, "rejected")
        XCTAssertEqual(c.items?.first?.decision_note, "Blurry")
        XCTAssertEqual(c.items?.first?.receipt_signed_url, "https://x/r.jpg?t=1")
        XCTAssertEqual(c.approvals?.first?.item_decisions?.first?.note, "Blurry")
        XCTAssertEqual(c.ai_flags?.first?.item_id, "i1")
    }

    func testStillDecodesAnOlderClaimWithoutTheNewFields() throws {
        let c = try decodeClaim(#"{"id":"c1","status":"draft","currency":"INR","total_amount":100}"#)
        XCTAssertNil(c.approved_amount)
        XCTAssertNil(c.review_note)
        XCTAssertNil(c.items)
    }

    func testDecodesAPolicyCheckAndAnUploadedReceipt() throws {
        let check = try JSONDecoder().decode(ExpenseClaimCheck.self, from: Data("""
        {"policy":{"currency":"INR","mileage_rate":12,"require_receipt_over":500,"rules":{"enforcement":"block","categories":{"food":{"enabled":true,"per_day_limit":500}}}},
         "total":900,"blocking":true,"would_auto_approve":false,
         "violations":[{"code":"receipt_missing","severity":"warn","detail":"Needs a receipt.","item_id":"0","blocking":true}]}
        """.utf8))
        XCTAssertEqual(check.blocking, true)
        XCTAssertEqual(check.policy?.rules?.enforcement, "block")
        XCTAssertEqual(check.policy?.rules?.categories?["food"]?.per_day_limit, 500)
        XCTAssertEqual(check.violations?.first?.blocking, true)

        let up = try JSONDecoder().decode(ExpenseUploadedReceipt.self, from: Data("""
        {"url":"https://x/o/u/r.jpg","path":"o/u/r.jpg","content_type":"image/jpeg","size":123,"signed_url":"https://x/r.jpg?t=2",
         "scan":{"merchant":"Hotel","txn_date":"2026-10-01","amount":1500,"category":"lodging"}}
        """.utf8))
        XCTAssertEqual(up.scan?.amount, 1500)
        XCTAssertEqual(up.signed_url, "https://x/r.jpg?t=2")
    }

    // MARK: - Lines

    func testABlankLineIsNotFilled_andAnAmountlessOneIsNotValid() {
        XCTAssertFalse(ExpenseLineFields().isFilled)
        var typed = ExpenseLineFields(); typed.merchant = "Cafe"
        XCTAssertTrue(typed.isFilled)
        XCTAssertFalse(typed.isValid)
        typed.amount = "120"; XCTAssertTrue(typed.isValid)
        typed.amount = "0"; XCTAssertFalse(typed.isValid)
    }

    func testMileageIsValidWithOnlyADistance_andPricedAtThePolicyRate() {
        var km = ExpenseLineFields(); km.category = "mileage"; km.distanceKm = "40"
        XCTAssertTrue(km.isValid)
        XCTAssertEqual(km.effectiveAmount(mileageRate: 12), 480)
        km.amount = "500"; XCTAssertEqual(km.effectiveAmount(mileageRate: 12), 500)
        var food = ExpenseLineFields(); food.distanceKm = "40"
        XCTAssertFalse(food.isValid)
    }

    func testSaveOnlyCarriesTheFieldsThatBelongToTheCategory() {
        var food = ExpenseLineFields()
        food.id = "l1"; food.amount = "250"; food.merchant = " Cafe "; food.fromLocation = "A"; food.toLocation = "B"; food.distanceKm = "3"
        let f = food.toInput()
        XCTAssertEqual(f.merchant, "Cafe")
        XCTAssertNil(f.from_location)
        XCTAssertNil(f.distance_km)
        XCTAssertEqual(f.id, "l1")

        var trip = ExpenseLineFields(); trip.category = "mileage"; trip.distanceKm = "10"; trip.fromLocation = "A"; trip.merchant = "ignored"
        let t = trip.toInput()
        XCTAssertEqual(t.distance_km, 10)
        XCTAssertNil(t.merchant)
        XCTAssertNil(t.amount)   // priced by the server at the policy rate
    }

    // MARK: - Receipts

    func testAKeptReceiptIsSent_aRemovedOneIsClearedWithAnEmptyString_andNoReceiptIsOmitted() throws {
        var kept = ExpenseLineFields(); kept.amount = "1"; kept.receiptUrl = "https://x/r.jpg"; kept.hadReceipt = true
        XCTAssertEqual(kept.toInput().receipt_url, "https://x/r.jpg")

        // nil is dropped by the encoder, and an omitted receipt means "keep what is on file" — so a removal must be "".
        var removed = ExpenseLineFields(); removed.amount = "1"; removed.hadReceipt = true
        XCTAssertEqual(removed.toInput().receipt_url, "")
        let json = try String(data: JSONEncoder().encode(removed.toInput()), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"receipt_url\":\"\""))

        var none = ExpenseLineFields(); none.amount = "1"
        XCTAssertNil(none.toInput().receipt_url)
        let omitted = try String(data: JSONEncoder().encode(none.toInput()), encoding: .utf8) ?? ""
        XCTAssertFalse(omitted.contains("receipt_url"))
    }

    func testAScanFillsOnlyWhatIsEmpty() {
        let scan = ExpenseReceiptFields(merchant: "Hotel Sahyadri", txn_date: "2026-10-01", amount: 1500, currency: nil, tax_amount: nil, category: "lodging")
        var blank = ExpenseLineFields(); blank.itemDate = "2026-10-05"
        let fresh = blank.withScan(scan, receiptUrl: "https://x/r.jpg")
        XCTAssertEqual(fresh.amount, "1500")
        XCTAssertEqual(fresh.merchant, "Hotel Sahyadri")
        XCTAssertEqual(fresh.itemDate, "2026-10-01")
        XCTAssertEqual(fresh.category, "lodging")
        XCTAssertEqual(fresh.receiptUrl, "https://x/r.jpg")
        XCTAssertEqual(fresh.ocr, scan)

        // What the person already typed is never overwritten, and the category and date stay put.
        var typed = ExpenseLineFields(); typed.category = "food"; typed.amount = "900"; typed.merchant = "Own"; typed.itemDate = "2026-10-05"
        let kept = typed.withScan(scan, receiptUrl: "u")
        XCTAssertEqual(kept.amount, "900")
        XCTAssertEqual(kept.merchant, "Own")
        XCTAssertEqual(kept.category, "food")
        XCTAssertEqual(kept.itemDate, "2026-10-05")
    }

    func testAMileageLineKeepsItsCategoryWhateverTheScanSays() {
        var l = ExpenseLineFields(); l.category = "mileage"
        let scan = ExpenseReceiptFields(merchant: nil, txn_date: nil, amount: nil, currency: nil, tax_amount: nil, category: "lodging")
        XCTAssertEqual(l.withScan(scan, receiptUrl: "u").category, "mileage")
    }

    func testASavedLineRoundTripsIntoTheEditor() throws {
        let it = try JSONDecoder().decode(ExpenseClaimItem.self, from: Data(#"{"id":"i","category":"lodging","item_date":"2026-10-01","amount":1500,"merchant":"Hotel","receipt_url":"https://x/r.jpg"}"#.utf8))
        let f = it.toFields()
        XCTAssertEqual(f.amount, "1500")
        XCTAssertTrue(f.hadReceipt)
        XCTAssertEqual(f.id, "i")
    }

    // MARK: - Policy findings

    private func flag(_ code: String, item: String? = nil, severity: String? = nil) -> ExpenseFlag {
        ExpenseFlag(code: code, severity: severity, detail: nil, item_id: item, category: nil, blocking: nil)
    }

    func testFindingsAreMatchedToTheirLineByPosition() {
        let flags = [flag("receipt_missing", item: "0"), flag("over_category_limit", item: "1"), flag("over_claim_limit")]
        XCTAssertEqual(ExpenseLogic.flags(forLine: 1, in: flags).map { $0.code }, ["over_category_limit"])
        XCTAssertEqual(ExpenseLogic.claimLevelFlags(flags).map { $0.code }, ["over_claim_limit"])
        XCTAssertEqual(ExpenseLogic.flagLabel("receipt_missing"), "Receipt needed")
    }

    func testASeriousFlagTakesAwayTheOneTapApproval() throws {
        let warn = try decodeClaim(#"{"id":"c","currency":"INR","total_amount":1,"ai_flags":[{"code":"x","severity":"warn"}]}"#)
        let high = try decodeClaim(#"{"id":"c","currency":"INR","total_amount":1,"ai_flags":[{"code":"x","severity":"high"}]}"#)
        let none = try decodeClaim(#"{"id":"c","currency":"INR","total_amount":1}"#)
        XCTAssertTrue(ExpenseLogic.canQuickApprove(warn))
        XCTAssertFalse(ExpenseLogic.canQuickApprove(high))
        XCTAssertTrue(ExpenseLogic.canQuickApprove(none))
    }

    // MARK: - Reviewing

    func testARejectedLineNeedsARemarkBeforeTheClaimCanBeApproved() {
        let reviews = [
            ExpenseLineReview(id: "a"),
            ExpenseLineReview(id: "b", approved: false),
            ExpenseLineReview(id: "c", approved: false, note: "  "),
            ExpenseLineReview(id: "d", approved: false, note: "Not business"),
        ]
        XCTAssertEqual(ExpenseReview.linesMissingRemark(reviews), ["b", "c"])
    }

    func testPartialApprovalPaysOnlyTheApprovedLines() throws {
        let items = [try item("a", 400), try item("b", 500), try item("c", 100)]
        let reviews = [ExpenseLineReview(id: "a"), ExpenseLineReview(id: "b", approved: false, note: "no"), ExpenseLineReview(id: "c")]
        XCTAssertEqual(ExpenseReview.approvedTotal(items: items, reviews: reviews), 500)
        let body = ExpenseReview.body(reviews)
        XCTAssertEqual(body.map { $0.decision }, ["approved", "rejected", "approved"])
        XCTAssertEqual(body[1].note, "no")
        XCTAssertNil(body[0].note)
    }

    func testRejectingTheWholeClaimOnlySendsTheLinesThatHaveTheirOwnRemark() {
        let reviews = [ExpenseLineReview(id: "a"), ExpenseLineReview(id: "b", approved: false, note: "blurry"), ExpenseLineReview(id: "c", approved: false)]
        XCTAssertEqual(ExpenseReview.ownRemarks(reviews).map { $0.id }, ["b"])
    }

    // MARK: - Claims

    func testPartlyApprovedMeansApprovedForLessThanClaimed() throws {
        let c = try decodeClaim(#"{"id":"c","status":"approved","currency":"INR","total_amount":900,"approved_amount":400}"#)
        XCTAssertTrue(ExpenseLogic.isPartlyApproved(c))
        XCTAssertEqual(ExpenseLogic.payable(c), 400)
        let full = try decodeClaim(#"{"id":"c","status":"approved","currency":"INR","total_amount":900,"approved_amount":900}"#)
        XCTAssertFalse(ExpenseLogic.isPartlyApproved(full))
        // Until a decision, what is on the table is the claimed total.
        let waiting = try decodeClaim(#"{"id":"c","status":"submitted","currency":"INR","total_amount":900,"approved_amount":400}"#)
        XCTAssertEqual(ExpenseLogic.payable(waiting), 900)
    }

    func testAClaimCanBeEditedUntilItIsApproved() {
        for s in ["draft", "submitted", "rejected"] { XCTAssertTrue(ExpenseLogic.isEditable(s), s) }
        for s in ["approved", "reimbursed", "cancelled"] { XCTAssertFalse(ExpenseLogic.isEditable(s), s) }
    }

    func testTheHistoryShowsEachAttemptAndTheRemarkOnTheRejection() throws {
        let c = try decodeClaim("""
        {"id":"c","status":"rejected","currency":"INR","total_amount":1850,"created_at":"2026-10-01T09:00:00Z","submit_count":1,
         "approvals":[{"id":"a1","level":1,"round":1,"status":"rejected","approver_name":"Meera","note":"Receipt unreadable","decided_at":"2026-10-03T10:00:00Z",
           "item_decisions":[{"item_id":"i1","category":"lodging","amount":1500,"decision":"rejected","note":"Blurry"},
                             {"item_id":"i2","category":"food","amount":350,"decision":"approved"}]}]}
        """)
        let steps = expenseTimeline(c)
        XCTAssertEqual(steps.map { $0.title }, ["Claim created", "Submitted for approval", "Rejected by Meera"])
        let rejection = try XCTUnwrap(steps.last)
        XCTAssertEqual(rejection.tone, .bad)
        XCTAssertEqual(rejection.remark, "Receipt unreadable")
        XCTAssertTrue(try XCTUnwrap(rejection.rejectedLines.first).contains("Blurry"))
    }

    func testAResubmissionIsLabelledAsASecondAttempt() throws {
        let c = try decodeClaim("""
        {"id":"c","status":"submitted","currency":"INR","total_amount":1,"submit_count":2,
         "approvals":[{"id":"a1","level":1,"round":1,"status":"rejected","approver_name":"Meera","note":"Fix it"},
                      {"id":"a2","level":1,"round":2,"status":"pending","approver_name":"Meera"}]}
        """)
        let titles = expenseTimeline(c).map { $0.title }
        XCTAssertTrue(titles.contains("Submitted (attempt 1)"))
        XCTAssertTrue(titles.contains("Submitted again (attempt 2)"))
        XCTAssertTrue(titles.contains("Waiting for Meera"))
    }

    // MARK: - Who sees what, money, errors

    func testOnlyApproverRolesSeeApprovals_andAFieldExecutiveNever() {
        XCTAssertTrue(ExpenseLogic.canApprove(role: "supervisor", dataScope: "team"))
        XCTAssertTrue(ExpenseLogic.canApprove(role: "admin", dataScope: nil))
        XCTAssertFalse(ExpenseLogic.canApprove(role: "executive", dataScope: nil))
        // Flat field-force tenants give reps the sub_admin role; only the data scope tells them apart.
        XCTAssertFalse(ExpenseLogic.canApprove(role: "sub_admin", dataScope: "own"))
        // Unknown role: keep the entry, the API decides.
        XCTAssertTrue(ExpenseLogic.canApprove(role: nil, dataScope: nil))
    }

    func testMoneyReadsAsRupeesWithGrouping() {
        XCTAssertEqual(ExpenseLogic.money(1850, "INR"), "₹1,850")
        XCTAssertEqual(ExpenseLogic.money(99.5, "INR"), "₹99.5")
        XCTAssertEqual(ExpenseLogic.money(40, "USD"), "USD 40")
    }

    func testAFailedCallShowsTheServersOwnWords() {
        let body = Data(#"{"success":false,"error":"Add a remark explaining why this claim is rejected.","code":"REMARK_REQUIRED"}"#.utf8)
        XCTAssertEqual(ExpenseErrors.serverMessage(in: body), "Add a remark explaining why this claim is rejected.")
        let nested = Data(#"{"error":{"message":"Nope"}}"#.utf8)
        XCTAssertEqual(ExpenseErrors.serverMessage(in: nested), "Nope")
        XCTAssertEqual(ExpenseErrors.message(serverMessage: nil, status: 403), "You don't have permission to do that.")
        XCTAssertTrue(ExpenseErrors.message(serverMessage: nil, status: 413).contains("10 MB"))
        XCTAssertEqual(ExpenseErrors.message(serverMessage: "  ", status: 400), "Request failed (400)")
    }
}
