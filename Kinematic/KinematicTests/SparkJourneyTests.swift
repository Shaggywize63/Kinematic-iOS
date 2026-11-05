//
//  SparkJourneyTests.swift
//  KinematicTests
//
//  Spark & Ray account-journey logic: the client gate, account-update bodies, form-serial
//  normalising, the multi-assignee ordering (first = Primary), the activity / deal request bodies, the
//  product-lines total, and decoding the new optional fields (which must stay nil for every other tenant).
//

import XCTest
import Foundation
@testable import Kinematic

@MainActor
final class SparkJourneyTests: XCTestCase {

    // MARK: - client gate

    func testOnlyTheSparkClientIdPassesTheGate() {
        XCTAssertTrue(SparkJourney.isSpark(clientId: "c0218852-0a19-4dd0-b9fa-72f9e32ed0d8"))
        XCTAssertTrue(SparkJourney.isSpark(clientId: "C0218852-0A19-4DD0-B9FA-72F9E32ED0D8"))
        XCTAssertFalse(SparkJourney.isSpark(clientId: nil))
        XCTAssertFalse(SparkJourney.isSpark(clientId: ""))
        XCTAssertFalse(SparkJourney.isSpark(clientId: "a1f67468-0000-0000-0000-000000000000"))
    }

    // MARK: - account update body

    func testBlankUpdateTextBuildsNoBody() {
        XCTAssertNil(SparkJourney.updateBody(text: "", contactId: nil))
        XCTAssertNil(SparkJourney.updateBody(text: "  \n\t ", contactId: "c1"))
    }

    func testUpdateBodyTrimsAndOmitsContactWhenNoneIsPicked() {
        let body = SparkJourney.updateBody(text: "  Called the plant head \n", contactId: nil)
        XCTAssertEqual(body?["body"] as? String, "Called the plant head")
        XCTAssertNil(body?["contact_id"])
        XCTAssertEqual(body?.count, 1)
    }

    func testUpdateBodyCarriesThePickedContact() {
        let body = SparkJourney.updateBody(text: "Quote sent", contactId: "c-123")
        XCTAssertEqual(body?["contact_id"] as? String, "c-123")
        XCTAssertNil(SparkJourney.updateBody(text: "x", contactId: "")?["contact_id"])
    }

    func testUpdateBodyIsClampedToTheBackendLimit() {
        let long = String(repeating: "a", count: 4500)
        let text = SparkJourney.updateBody(text: long, contactId: nil)?["body"] as? String
        XCTAssertEqual(text?.count, 4000)
    }

    func testRelativeTimeParsesBothTimestampShapesAndIgnoresGarbage() {
        XCTAssertNotNil(SparkJourney.parseISO("2026-10-08T04:12:00.000Z"))
        XCTAssertNotNil(SparkJourney.parseISO("2026-10-08T04:12:00Z"))
        XCTAssertNil(SparkJourney.parseISO("yesterday"))
        XCTAssertNil(SparkJourney.parseISO(nil))
        XCTAssertEqual(SparkJourney.relativeTime("nope"), "")
        XCTAssertFalse(SparkJourney.relativeTime("2026-10-08T04:12:00Z").isEmpty)
    }

    // MARK: - form serial

    func testSerialIsUppercasedAndStrippedOfWhitespace() {
        XCTAssertEqual(SparkJourney.normalizedSerial("srpr2627-12"), "SRPR2627-12")
        XCTAssertEqual(SparkJourney.normalizedSerial("  srpr2627-12 \n"), "SRPR2627-12")
        XCTAssertEqual(SparkJourney.normalizedSerial("srpr 2627 - 12"), "SRPR2627-12")
        XCTAssertEqual(SparkJourney.normalizedSerial("   "), "")
    }

    func testServerMessagesAboutTheSerialAreRoutedToTheSerialField() {
        XCTAssertTrue(SparkJourney.isSerialError("No form submission found for serial SRPR2627-99"))
        XCTAssertTrue(SparkJourney.isSerialError("Unknown form reference"))
        XCTAssertFalse(SparkJourney.isSerialError("Assignee is not in your organisation"))
    }

    // MARK: - multi-select ordering

    func testToggleAppendsInTapOrderAndRemoves() {
        var ids: [String] = []
        ids = SparkJourney.toggled("a", in: ids)
        ids = SparkJourney.toggled("b", in: ids)
        ids = SparkJourney.toggled("c", in: ids)
        XCTAssertEqual(ids, ["a", "b", "c"])
        ids = SparkJourney.toggled("b", in: ids)
        XCTAssertEqual(ids, ["a", "c"])
    }

    func testToggleStopsAtTheLimit() {
        let full = (1...20).map { "u\($0)" }
        XCTAssertEqual(SparkJourney.toggled("extra", in: full, limit: SparkJourney.maxAssignees), full)
        // Removing is always allowed at the limit.
        XCTAssertEqual(SparkJourney.toggled("u1", in: full, limit: SparkJourney.maxAssignees).count, 19)
    }

    func testMakingPrimaryMovesToFrontAndKeepsTheRestInOrder() {
        XCTAssertEqual(SparkJourney.makingPrimary("c", in: ["a", "b", "c", "d"]), ["c", "a", "b", "d"])
        XCTAssertEqual(SparkJourney.makingPrimary("a", in: ["a", "b"]), ["a", "b"])
        XCTAssertEqual(SparkJourney.makingPrimary("zzz", in: ["a", "b"]), ["a", "b"])
    }

    func testDedupedDropsBlanksAndRepeatsKeepingFirst() {
        XCTAssertEqual(SparkJourney.deduped(["a", "", "b", "a", "c", "b"]), ["a", "b", "c"])
    }

    // MARK: - activity extras on the wire

    func testCreateSendsAssigneesInOrderProductsAndNormalisedSerial() {
        let extras = SparkActivityExtras(assigneeIds: ["u2", "u1", "u2"], productIds: ["p1", "p2"], formSerial: " srpr2627-12 ")
        var body: [String: Any] = ["type": "task"]
        extras.apply(to: &body)
        XCTAssertEqual(body["assignee_ids"] as? [String], ["u2", "u1"])
        XCTAssertEqual(body["product_ids"] as? [String], ["p1", "p2"])
        XCTAssertEqual(body["form_serial"] as? String, "SRPR2627-12")
    }

    func testCreateWithNothingPickedSendsNoSparkKeys() {
        var body: [String: Any] = ["type": "task"]
        SparkActivityExtras().apply(to: &body)
        XCTAssertEqual(body.count, 1)
    }

    func testAssigneesAreCappedAtTwenty() {
        let ids = (1...25).map { "u\($0)" }
        var body: [String: Any] = [:]
        SparkActivityExtras(assigneeIds: ids).apply(to: &body)
        XCTAssertEqual((body["assignee_ids"] as? [String])?.count, 20)
        XCTAssertEqual((body["assignee_ids"] as? [String])?.first, "u1")
    }

    func testEditSendsOnlyWhatChanged() {
        let before = SparkActivityExtras(assigneeIds: ["u1"], productIds: ["p1"], formSerial: "SRPR2627-12")
        var untouched: [String: Any] = [:]
        before.apply(to: &untouched, previous: before)
        XCTAssertTrue(untouched.isEmpty)

        var after = before
        after.assigneeIds = ["u2", "u1"]
        var changed: [String: Any] = [:]
        after.apply(to: &changed, previous: before)
        XCTAssertEqual(changed["assignee_ids"] as? [String], ["u2", "u1"])
        XCTAssertNil(changed["product_ids"])
        XCTAssertNil(changed["form_serial"])
    }

    func testEditClearsProductsWithAnEmptyArrayAndTheSerialWithAnEmptyString() {
        let before = SparkActivityExtras(assigneeIds: ["u1"], productIds: ["p1"], formSerial: "SRPR2627-12")
        var after = before
        after.productIds = []
        after.formSerial = "  "
        var body: [String: Any] = [:]
        after.apply(to: &body, previous: before)
        XCTAssertEqual(body["product_ids"] as? [String], [])
        XCTAssertEqual(body["form_serial"] as? String, "")
        XCTAssertNil(body["assignee_ids"])
    }

    // MARK: - activity bodies

    private func result(type: String = "task", extras: SparkActivityExtras = SparkActivityExtras()) -> ActivityComposeResult {
        ActivityComposeResult(
            type: type, subject: "  Follow up  ", description: " call back ", imageUrl: nil,
            when: Date(timeIntervalSince1970: 1_791_432_720), leadId: nil, customFields: [:], extras: extras
        )
    }

    func testScheduledBodyIsOpenWithADueDateAndTheAccountLink() {
        let body = SparkActivityBody.createBody(result(), scheduled: true, links: ["account_id": "acc-1", "lead_id": ""])
        XCTAssertEqual(body["type"] as? String, "task")
        XCTAssertEqual(body["subject"] as? String, "Follow up")
        XCTAssertEqual(body["description"] as? String, "call back")
        XCTAssertEqual(body["status"] as? String, "open")
        XCTAssertNotNil(body["due_at"] as? String)
        XCTAssertNil(body["completed_at"])
        XCTAssertEqual(body["account_id"] as? String, "acc-1")
        XCTAssertNil(body["lead_id"])
    }

    func testLoggedBodyIsCompletedExceptForTasks() {
        let call = SparkActivityBody.createBody(result(type: "call"), scheduled: false, links: [:])
        XCTAssertEqual(call["status"] as? String, "completed")
        XCTAssertNotNil(call["completed_at"])
        XCTAssertNil(call["due_at"])

        let task = SparkActivityBody.createBody(result(type: "task"), scheduled: false, links: [:])
        XCTAssertNil(task["status"])
        XCTAssertNotNil(task["due_at"])
    }

    func testEditBodyKeepsAnOpenActivityOpen() throws {
        let open = try JSONDecoder().decode(Activity.self, from: Data(#"{"id":"a1","status":"open"}"#.utf8))
        let body = SparkActivityBody.updateBody(result(type: "meeting"), existing: open)
        XCTAssertNil(body["status"])
        XCTAssertNil(body["completed_at"])
        XCTAssertNotNil(body["due_at"])
    }

    func testEditBodyKeepsACompletedActivityCompleted() throws {
        let done = try JSONDecoder().decode(
            Activity.self,
            from: Data(#"{"id":"a1","status":"completed","completed_at":"2026-10-08T04:12:00Z","body":"notes"}"#.utf8)
        )
        let body = SparkActivityBody.updateBody(result(type: "call"), existing: done)
        XCTAssertNil(body["status"])
        XCTAssertNotNil(body["completed_at"])
        XCTAssertNil(body["due_at"])
    }

    func testEditBodyOnlyClearsTheDescriptionWhenTheRowHadOne() throws {
        let blank = ActivityComposeResult(
            type: "task", subject: "S", description: "  ", imageUrl: nil,
            when: Date(), leadId: nil, customFields: [:], extras: SparkActivityExtras()
        )
        let without = try JSONDecoder().decode(Activity.self, from: Data(#"{"id":"a1"}"#.utf8))
        XCTAssertNil(SparkActivityBody.updateBody(blank, existing: without)["description"])

        let with = try JSONDecoder().decode(Activity.self, from: Data(#"{"id":"a1","body":"had notes"}"#.utf8))
        XCTAssertTrue(SparkActivityBody.updateBody(blank, existing: with)["description"] is NSNull)
    }

    // MARK: - decoding (new fields are optional and nil elsewhere)

    func testActivityDecodesSparkFields() throws {
        let json = """
        {"id":"a1","assignees":[{"id":"u1","name":"Asha"},{"id":"u2","name":"Ravi"}],
         "form_ref_no":"SRPR2627-12","form_submission_id":"f1",
         "product_ids":["p1"],"products":[{"id":"p1","name":"Valve"}]}
        """
        let a = try JSONDecoder().decode(Activity.self, from: Data(json.utf8))
        XCTAssertEqual(a.assignees?.map { $0.name }, ["Asha", "Ravi"])
        XCTAssertEqual(a.formRefNo, "SRPR2627-12")
        XCTAssertEqual(a.formSubmissionId, "f1")
        XCTAssertEqual(a.products?.first?.name, "Valve")
        XCTAssertEqual(a.sparkExtras, SparkActivityExtras(assigneeIds: ["u1", "u2"], productIds: ["p1"], formSerial: "SRPR2627-12"))
        XCTAssertEqual(a.sparkNames["u2"], "Ravi")
        XCTAssertEqual(a.sparkNames["p1"], "Valve")
    }

    func testActivityWithoutSparkFieldsDecodesToNil() throws {
        let a = try JSONDecoder().decode(Activity.self, from: Data(#"{"id":"a1","type":"call"}"#.utf8))
        XCTAssertNil(a.assignees)
        XCTAssertNil(a.formRefNo)
        XCTAssertNil(a.products)
        XCTAssertNil(a.productIds)
        XCTAssertEqual(a.sparkExtras, SparkActivityExtras())
    }

    func testAnOddAssigneeRowDoesNotFailTheActivity() throws {
        let a = try JSONDecoder().decode(Activity.self, from: Data(#"{"id":"a1","assignees":[{"id":"u1"}]}"#.utf8))
        XCTAssertEqual(a.assignees?.count, 1)
        XCTAssertEqual(a.assignees?.first?.name, "")
    }

    func testCompletionMergeKeepsTheSparkFields() throws {
        let row = try JSONDecoder().decode(
            Activity.self,
            from: Data(#"{"id":"a1","status":"open","assignees":[{"id":"u1","name":"Asha"}],"form_ref_no":"SRPR2627-12"}"#.utf8)
        )
        let patched = try JSONDecoder().decode(Activity.self, from: Data(#"{"id":"a1","status":"completed"}"#.utf8))
        let merged = row.applyingCompletion(from: patched)
        XCTAssertEqual(merged.status, "completed")
        XCTAssertEqual(merged.assignees?.first?.name, "Asha")
        XCTAssertEqual(merged.formRefNo, "SRPR2627-12")
    }

    func testDealDecodesQuotationNumber() throws {
        let d = try JSONDecoder().decode(Deal.self, from: Data(#"{"id":"d1","name":"Plant A","quotation_no":"Q-2026-07"}"#.utf8))
        XCTAssertEqual(d.quotationNo, "Q-2026-07")
        let plain = try JSONDecoder().decode(Deal.self, from: Data(#"{"id":"d2","name":"Other"}"#.utf8))
        XCTAssertNil(plain.quotationNo)
    }

    func testAccountUpdateDecodes() throws {
        let json = """
        {"id":"u1","account_id":"acc","contact_id":null,"body":"Met the buyer","created_by":"me",
         "created_at":"2026-10-08T04:12:00.000Z","updated_at":"2026-10-08T04:12:00.000Z",
         "contact_name":null,"author_name":"Asha"}
        """
        let u = try JSONDecoder().decode(AccountUpdate.self, from: Data(json.utf8))
        XCTAssertEqual(u.body, "Met the buyer")
        XCTAssertNil(u.contactId)
        XCTAssertNil(u.contactName)
        XCTAssertEqual(u.authorName, "Asha")
        XCTAssertEqual(u.createdBy, "me")
    }

    // MARK: - deal lines

    func testLineTotalIsQuantityTimesUnitPrice() {
        let line = DealLineDraft(name: "Valve", quantityText: "3", unitPriceText: "1,250.50")
        XCTAssertEqual(line.quantity, 3)
        XCTAssertEqual(line.unitPrice, 1250.5)
        XCTAssertEqual(line.lineTotal, 3751.5, accuracy: 0.0001)
    }

    func testLineTotalRoundsToTwoDecimals() {
        let line = DealLineDraft(name: "Seal", quantityText: "3", unitPriceText: "0.333")
        XCTAssertEqual(line.lineTotal, 1.0, accuracy: 0.0001)
    }

    func testGrandTotalSumsValidFilledLinesAndSkipsBlankAndInvalid() {
        let lines = [
            DealLineDraft(name: "A", quantityText: "2", unitPriceText: "100"),
            DealLineDraft(),                                                   // blank row
            DealLineDraft(name: "B", quantityText: "0", unitPriceText: "999"), // qty 0 -> invalid
            DealLineDraft(name: "C", quantityText: "1", unitPriceText: "50"),
        ]
        XCTAssertEqual(DealLines.grandTotal(lines), 250, accuracy: 0.0001)
        XCTAssertEqual(DealLines.payload(lines).count, 2)
    }

    func testAnEmptyPriceIsZeroNotInvalid() {
        let line = DealLineDraft(name: "Free sample", quantityText: "1", unitPriceText: "")
        XCTAssertTrue(line.isValid)
        XCTAssertEqual(line.lineTotal, 0)
    }

    func testNegativePriceAndNonPositiveQuantityAreInvalid() {
        XCTAssertFalse(DealLineDraft(name: "A", quantityText: "1", unitPriceText: "-5").isValid)
        XCTAssertFalse(DealLineDraft(name: "A", quantityText: "-1", unitPriceText: "5").isValid)
        XCTAssertFalse(DealLineDraft(name: "A", quantityText: "", unitPriceText: "5").isValid)
        XCTAssertFalse(DealLineDraft(name: "A", quantityText: "1", unitPriceText: "abc").isValid)
        XCTAssertFalse(DealLineDraft(productId: "p1", name: "  ", quantityText: "1", unitPriceText: "5").isValid)
    }

    func testBlankRowsAreIgnoredAndTheDefaultQuantityDoesNotMakeARowNonBlank() {
        XCTAssertTrue(DealLineDraft().isBlank)
        XCTAssertFalse(DealLineDraft(name: "x").isBlank)
        XCTAssertFalse(DealLineDraft(unitPriceText: "5").isBlank)
        XCTAssertNil(DealLines.firstProblem([DealLineDraft(), DealLineDraft()]))
    }

    func testFirstProblemNamesTheLine() {
        XCTAssertEqual(
            DealLines.firstProblem([DealLineDraft(name: "A", unitPriceText: "5"), DealLineDraft(unitPriceText: "9")]),
            "Line 2: choose a product or enter a name."
        )
        XCTAssertEqual(
            DealLines.firstProblem([DealLineDraft(name: "A", quantityText: "0", unitPriceText: "5")]),
            "Line 1: quantity must be more than 0."
        )
        XCTAssertEqual(
            DealLines.firstProblem([DealLineDraft(name: "A", quantityText: "1", unitPriceText: "-1")]),
            "Line 1: unit price must be 0 or more."
        )
    }

    func testPayloadCarriesProductIdNameQuantityAndUnitPrice() {
        let line = DealLineDraft(productId: "p1", name: " Valve ", quantityText: "2", unitPriceText: "10")
        let p = line.payload
        XCTAssertEqual(p["product_id"] as? String, "p1")
        XCTAssertEqual(p["name"] as? String, "Valve")
        XCTAssertEqual(p["quantity"] as? Double, 2)
        XCTAssertEqual(p["unit_price"] as? Double, 10)
        XCTAssertNil(DealLineDraft(name: "Custom", quantityText: "1", unitPriceText: "1").payload["product_id"])
    }

    func testPickingAProductPrefillsNameAndPrice() throws {
        let product = try JSONDecoder().decode(Product.self, from: Data(#"{"id":"p9","name":"Gate valve","price":1250}"#.utf8))
        var line = DealLineDraft()
        line.apply(product: product)
        XCTAssertEqual(line.productId, "p9")
        XCTAssertEqual(line.name, "Gate valve")
        XCTAssertEqual(line.unitPriceText, "1250")
        XCTAssertEqual(line.quantityText, "1")

        let fractional = try JSONDecoder().decode(Product.self, from: Data(#"{"id":"p8","name":"Seal","price":12.5}"#.utf8))
        line.apply(product: fractional)
        XCTAssertEqual(line.unitPriceText, "12.50")
    }

    func testNumberParsing() {
        XCTAssertEqual(SparkJourney.parseNumber(" 1,200.5 "), 1200.5)
        XCTAssertNil(SparkJourney.parseNumber(""))
        XCTAssertNil(SparkJourney.parseNumber("abc"))
        XCTAssertNil(SparkJourney.parseNumber("inf"))
        XCTAssertEqual(SparkJourney.priceText(0), "0")
    }

    // MARK: - deal body

    func testDealBodyCarriesCustomerQuotationAndItems() {
        var body: [String: Any] = ["name": "Plant A", "amount": 0.0, "status": "open"]
        let lines = [
            DealLineDraft(productId: "p1", name: "Valve", quantityText: "2", unitPriceText: "100"),
            DealLineDraft(),
        ]
        SparkDealBody.apply(to: &body, accountId: "acc-1", leadId: "lead-1", quotationNo: " Q-7 ", lines: lines)
        XCTAssertEqual(body["account_id"] as? String, "acc-1")
        XCTAssertEqual(body["lead_id"] as? String, "lead-1")
        XCTAssertEqual(body["quotation_no"] as? String, "Q-7")
        let items = body["items"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?["product_id"] as? String, "p1")
        XCTAssertEqual(body["amount"] as? Double, 200)
        XCTAssertNil(body["primary_contact_id"])
    }

    func testDealBodyLeavesOutBlankValuesAndKeepsTheTypedAmountWithoutLines() {
        var body: [String: Any] = ["name": "Plant A", "amount": 5000.0]
        SparkDealBody.apply(to: &body, accountId: nil, leadId: "", quotationNo: "  ", lines: [DealLineDraft()])
        XCTAssertNil(body["account_id"])
        XCTAssertNil(body["lead_id"])
        XCTAssertNil(body["quotation_no"])
        XCTAssertNil(body["items"])
        XCTAssertEqual(body["amount"] as? Double, 5000)
    }
}
