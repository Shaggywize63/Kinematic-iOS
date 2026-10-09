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
        XCTAssertEqual(t.from_location, "A")   // the route is sent unless the policy turned it off
        XCTAssertNil(t.merchant)
        XCTAssertNil(t.amount)   // priced by the server at the policy rate
    }

    func testTheRouteIsLeftOutWhenThePolicyTurnsItOff() throws {
        var trip = ExpenseLineFields()
        trip.category = "mileage"; trip.distanceKm = "10"; trip.fromLocation = "Pune"; trip.toLocation = "Nashik"
        let off = trip.toInput(routeFields: false)
        XCTAssertNil(off.from_location)
        XCTAssertNil(off.to_location)
        XCTAssertEqual(off.distance_km, 10)   // everything else is unchanged
        // nil is dropped from the wire body, which on an edit means "keep what is on file".
        let json = try String(data: JSONEncoder().encode(off), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("from_location"))
        XCTAssertFalse(json.contains("to_location"))
        let on = try String(data: JSONEncoder().encode(trip.toInput()), encoding: .utf8) ?? ""
        XCTAssertTrue(on.contains("\"from_location\":\"Pune\""))
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

    // MARK: - Per-client policy switches (all optional: absent = today)

    private func rules(_ json: String) throws -> ExpensePolicyRules {
        try JSONDecoder().decode(ExpensePolicyRules.self, from: Data(json.utf8))
    }

    /// Every category switched off except `only`.
    private func onlyOne(_ only: String) throws -> ExpensePolicyRules {
        let cats = ExpenseLogic.categories
            .map { "\"\($0)\":{\"enabled\":\($0 == only)}" }
            .joined(separator: ",")
        return try rules("{\"categories\":{\(cats)}}")
    }

    func testAPolicyWithoutTheNewSwitchesBehavesAsBefore() throws {
        let plain = try rules(#"{"mileage_rate":12}"#)
        XCTAssertNil(plain.category_labels)
        XCTAssertNil(plain.route_fields)
        XCTAssertNil(plain.single_line)
        XCTAssertNil(plain.odometer_camera_only)
        XCTAssertTrue(ExpenseLogic.showsRoute(plain))
        XCTAssertFalse(ExpenseLogic.isSingleLine(plain))
        XCTAssertFalse(ExpenseLogic.odometerCameraOnly(plain))
        XCTAssertNil(ExpenseLogic.singleCategory(plain))
        XCTAssertEqual(ExpenseLogic.defaultCategory(plain), "food")
        // No policy at all is the same.
        XCTAssertTrue(ExpenseLogic.showsRoute(nil))
        XCTAssertFalse(ExpenseLogic.isSingleLine(nil))
        XCTAssertFalse(ExpenseLogic.odometerCameraOnly(nil))
        XCTAssertNil(ExpenseLogic.singleCategory(nil))
        XCTAssertTrue(ExpenseLogic.showsCategoryPicker(nil, current: "food"))
        XCTAssertEqual(ExpenseLogic.allowedCategories(nil, current: "food"), ExpenseLogic.categories)
    }

    func testTheNewSwitchesDecodeFromThePolicy() throws {
        let r = try rules(#"{"category_labels":{"mileage":"Travel"},"route_fields":false,"single_line":true,"odometer_camera_only":true}"#)
        XCTAssertEqual(r.category_labels, ["mileage": "Travel"])
        XCTAssertFalse(ExpenseLogic.showsRoute(r))
        XCTAssertTrue(ExpenseLogic.isSingleLine(r))
        XCTAssertTrue(ExpenseLogic.odometerCameraOnly(r))
    }

    func testEveryCategoryNameGoesThroughTheLabelOverride() {
        XCTAssertEqual(ExpenseLogic.categoryLabel("mileage"), "Mileage")
        XCTAssertEqual(ExpenseLogic.categoryLabel("misc"), "Other")
        XCTAssertEqual(ExpenseLogic.categoryLabel("mileage", labels: ["mileage": "Travel"]), "Travel")
        // Other categories keep their names; a blank override counts as none.
        XCTAssertEqual(ExpenseLogic.categoryLabel("food", labels: ["mileage": "Travel"]), "Food")
        XCTAssertEqual(ExpenseLogic.categoryLabel("mileage", labels: ["mileage": "  "]), "Mileage")
        XCTAssertNil(ExpenseLogic.customLabel("mileage", labels: ["mileage": " "]))
        XCTAssertEqual(ExpenseLogic.customLabel("mileage", labels: ["mileage": " Travel "]), "Travel")
    }

    func testTheHistoryAndTheLineNamesUseTheRenamedCategory() throws {
        let c = try decodeClaim("""
        {"id":"c","status":"rejected","currency":"INR","total_amount":900,"submit_count":1,
         "approvals":[{"id":"a1","level":1,"round":1,"status":"rejected","approver_name":"Meera","note":"No",
           "item_decisions":[{"item_id":"i1","category":"mileage","amount":400,"decision":"rejected","note":"Too far"}]}]}
        """)
        let plain = expenseTimeline(c).last?.rejectedLines.first ?? ""
        XCTAssertTrue(plain.hasPrefix("Mileage"), plain)
        let renamed = expenseTimeline(c, categoryLabels: ["mileage": "Travel"]).last?.rejectedLines.first ?? ""
        XCTAssertTrue(renamed.hasPrefix("Travel"), renamed)
    }

    func testSingleCategoryModeNeedsExactlyOneEnabledCategory() throws {
        let travelOnly = try onlyOne("mileage")
        XCTAssertEqual(ExpenseLogic.enabledCategories(travelOnly), ["mileage"])
        XCTAssertEqual(ExpenseLogic.singleCategory(travelOnly), "mileage")
        XCTAssertEqual(ExpenseLogic.defaultCategory(travelOnly), "mileage")

        // Two on (or a category the policy never mentions) is not single-category mode.
        let two = try rules(#"{"categories":{"food":{"enabled":false},"travel":{"enabled":false},"lodging":{"enabled":false},"fuel":{"enabled":false},"toll":{"enabled":false}}}"#)
        XCTAssertEqual(ExpenseLogic.enabledCategories(two), ["mileage", "misc"])
        XCTAssertNil(ExpenseLogic.singleCategory(two))
        XCTAssertEqual(ExpenseLogic.defaultCategory(two), "food")
        // Everything off is not "one category" either.
        let none = try rules(#"{"categories":{"mileage":{"enabled":false},"travel":{"enabled":false},"food":{"enabled":false},"lodging":{"enabled":false},"fuel":{"enabled":false},"toll":{"enabled":false},"misc":{"enabled":false}}}"#)
        XCTAssertNil(ExpenseLogic.singleCategory(none))
    }

    func testTheCategoryPickerIsHiddenOnlyWhereThereIsNothingToChoose() throws {
        let travelOnly = try onlyOne("mileage")
        XCTAssertFalse(ExpenseLogic.showsCategoryPicker(travelOnly, current: "mileage"))
        XCTAssertEqual(ExpenseLogic.allowedCategories(travelOnly, current: "mileage"), ["mileage"])
        // An older claim line on another category still renders, and can be moved to the allowed one.
        XCTAssertTrue(ExpenseLogic.showsCategoryPicker(travelOnly, current: "food"))
        XCTAssertEqual(ExpenseLogic.allowedCategories(travelOnly, current: "food"), ["mileage", "food"])
        // A policy that leaves several on keeps the picker.
        let several = try rules(#"{"categories":{"misc":{"enabled":false}}}"#)
        XCTAssertTrue(ExpenseLogic.showsCategoryPicker(several, current: "food"))
        XCTAssertFalse(ExpenseLogic.allowedCategories(several, current: "food").contains("misc"))
    }

    func testAReceiptScanCannotMoveALineOffTheOnlyAllowedCategory() {
        let scan = ExpenseReceiptFields(merchant: "Hotel", txn_date: nil, amount: 900, currency: nil, tax_amount: nil, category: "lodging")
        var line = ExpenseLineFields(); line.category = "food"
        XCTAssertEqual(line.withScan(scan, receiptUrl: "u").category, "lodging")                              // as before
        XCTAssertEqual(line.withScan(scan, receiptUrl: "u", allowedCategories: ["food"]).category, "food")   // single-category mode
        XCTAssertEqual(line.withScan(scan, receiptUrl: "u", allowedCategories: ["food", "lodging"]).category, "lodging")
    }

    func testAMileageLineWithoutARouteReadsWithoutOne() throws {
        func decodeItem(_ json: String) throws -> ExpenseClaimItem { try JSONDecoder().decode(ExpenseClaimItem.self, from: Data(json.utf8)) }
        XCTAssertNil(try decodeItem(#"{"id":"a","category":"mileage","amount":0,"distance_km":10}"#).routeText)
        XCTAssertNil(try decodeItem(#"{"id":"a","category":"mileage","amount":0,"from_location":"  ","to_location":""}"#).routeText)
        XCTAssertEqual(try decodeItem(#"{"id":"a","category":"mileage","amount":0,"from_location":"Pune","to_location":"Nashik"}"#).routeText, "Pune → Nashik")
        // One end is enough to print it; the missing end shows a dash.
        XCTAssertEqual(try decodeItem(#"{"id":"a","category":"mileage","amount":0,"from_location":"Pune"}"#).routeText, "Pune → —")
        XCTAssertEqual(try decodeItem(#"{"id":"a","category":"mileage","amount":0,"to_location":"Nashik"}"#).routeText, "— → Nashik")
    }

    // MARK: - Reading the odometer from the photo

    func testAnOdometerScanDecodesAndNeverFailsTheUpload() throws {
        func up(_ extra: String) throws -> ExpenseUploadedReceipt {
            try JSONDecoder().decode(ExpenseUploadedReceipt.self, from: Data(#"{"url":"https://x/o.jpg","signed_url":"https://x/o.jpg?t=1"\#(extra)}"#.utf8))
        }
        let read = try up(#","odometer":{"reading":12340.5,"confidence":"high"}"#)
        XCTAssertEqual(read.odometer?.reading, 12340.5)
        XCTAssertEqual(read.odometer?.confidence, "high")
        // Not readable, absent, or in a shape nobody expected: the photo is still stored, there is just no number.
        XCTAssertNil(try up(#","odometer":{"reading":null,"confidence":"low"}"#).odometer?.reading)
        XCTAssertNil(try up("").odometer)
        XCTAssertEqual(try up(#","odometer":{"reading":"12340"}"#).odometer?.reading, 12340)
        XCTAssertNil(try up(#","odometer":{"reading":{"x":1}}"#).odometer?.reading)
        XCTAssertNil(try up(#","odometer":"nope""#).odometer)
        XCTAssertEqual(try up(#","odometer":"nope""#).url, "https://x/o.jpg")
    }

    func testTheUploadAsksForTheReadThePolicyWants() {
        XCTAssertEqual(ExpenseUploadScan.receipt.path, "/expenses/receipts")
        XCTAssertEqual(ExpenseUploadScan.storeOnly.path, "/expenses/receipts?scan=0")
        XCTAssertEqual(ExpenseUploadScan.odometer.path, "/expenses/receipts?scan=odometer")
    }

    func testAReadingFromThePhotoFillsTheMatchingSlotAndStaysEditable() {
        var line = ExpenseLineFields()
        line.category = "mileage"; line.odometerStart = "100"; line.odometerEnd = "250"
        // Before: replaces what was there.
        XCTAssertEqual(line.applyOdometerScan(ExpenseOdometerScan(reading: 12340), start: true), .read)
        XCTAssertEqual(line.odometerStart, "12340")
        XCTAssertEqual(line.odometerEnd, "250")
        // After: only its own slot moves.
        XCTAssertEqual(line.applyOdometerScan(ExpenseOdometerScan(reading: 12392.5), start: false), .read)
        XCTAssertEqual(line.odometerStart, "12340")
        XCTAssertEqual(line.odometerEnd, "12392.5")
        // It is plain text in the field, so the person can still type over it.
        line.odometerEnd = "12400"
        XCTAssertEqual(line.odometerKm, 60)
    }

    func testAPhotoThatCouldNotBeReadAsksForTheNumberAndKeepsWhatWasTyped() {
        var line = ExpenseLineFields()
        line.odometerStart = "500"
        for scan in [nil, ExpenseOdometerScan(reading: nil), ExpenseOdometerScan(reading: -3), ExpenseOdometerScan(reading: .nan), ExpenseOdometerScan(reading: .infinity)] {
            XCTAssertEqual(line.applyOdometerScan(scan, start: true), .unreadable)
            XCTAssertEqual(line.odometerStart, "500")
        }
        XCTAssertEqual(OdometerScanNote.read.text, "Read from the photo — please check")
        XCTAssertEqual(OdometerScanNote.unreadable.text, "Couldn't read the number — please enter it")
        // A zero reading is a real reading.
        XCTAssertEqual(line.applyOdometerScan(ExpenseOdometerScan(reading: 0), start: true), .read)
        XCTAssertEqual(line.odometerStart, "0")
    }

    // MARK: - Odometer history

    private func entries() throws -> [ExpenseOdometerEntry] {
        let json = """
        [{"id":"l2","claim_id":"c2","claim_no":"EXP-0009","claim_status":"submitted","user_id":"u","user_name":"Asha","item_date":"2026-10-05",
          "vehicle_type":"two_wheeler","vehicle_label":"Two-wheeler","odometer_start":12340,"odometer_end":12392,"distance_km":52,"amount":208,
          "start_photo_url":"https://x/a.jpg","end_photo_url":"https://x/b.jpg","created_at":"2026-10-05T09:00:00Z"},
         {"id":"l1","claim_id":"c1","claim_status":"approved","item_date":"2026-10-01T00:00:00Z","vehicle_type":"car","odometer_start":12000,"odometer_end":null}]
        """
        return try JSONDecoder().decode([ExpenseOdometerEntry].self, from: Data(json.utf8))
    }

    func testTheOdometerHistoryDecodesWhatTheServerSends() throws {
        let rows = try entries()
        XCTAssertEqual(rows.map { $0.id }, ["l2", "l1"])
        XCTAssertEqual(rows[0].vehicleText, "Two-wheeler")
        XCTAssertEqual(rows[0].readingsText, "12340 → 12392")
        XCTAssertEqual(rows[0].statusText, "Submitted")
        XCTAssertEqual(rows[0].start_photo_url, "https://x/a.jpg")
        // No label from the server: a readable vehicle id; a missing end reading shows a dash.
        XCTAssertEqual(rows[1].vehicleText, "Car")
        XCTAssertEqual(rows[1].readingsText, "12000 → —")
        XCTAssertNil(rows[1].distance_km)
    }

    func testTheLastReadingIsTheNewestOneOnFile() throws {
        let rows = try entries()
        let last = try XCTUnwrap(ExpenseLogic.lastReading(in: rows))
        XCTAssertEqual(last.km, 12392)
        XCTAssertEqual(ExpenseLogic.lastReadingText(last), "Last reading: 12392 km (5 Oct 2026)")
        // The claim being edited does not offer its own reading back; the next-newest line does (its start when it has no end).
        let other = try XCTUnwrap(ExpenseLogic.lastReading(in: rows, excludingClaim: "c2"))
        XCTAssertEqual(other.km, 12000)
        XCTAssertEqual(ExpenseLogic.lastReadingText(other), "Last reading: 12000 km (1 Oct 2026)")
        XCTAssertNil(ExpenseLogic.lastReading(in: []))
        XCTAssertNil(ExpenseLogic.lastReading(in: [rows[0]], excludingClaim: "c2"))
    }

    func testShortDatesReadAsDayMonthYear() {
        XCTAssertEqual(ExpenseLogic.shortDate("2026-10-05"), "5 Oct 2026")
        XCTAssertEqual(ExpenseLogic.shortDate("2026-12-31T23:59:00Z"), "31 Dec 2026")
        XCTAssertNil(ExpenseLogic.shortDate(nil))
        XCTAssertNil(ExpenseLogic.shortDate("2026"))
        XCTAssertEqual(ExpenseLogic.shortDate("not-a-date-at-all"), "not-a-date")
    }
}
