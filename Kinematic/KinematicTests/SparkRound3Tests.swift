//
//  SparkRound3Tests.swift
//  KinematicTests
//
//  Spark & Ray round 3: the activity Outcome (and the rule that makes it required once completed), the
//  Company on an activity row, the Activities list Account / User filters, the account Addresses (sites)
//  request bodies, and the contact "Company" wording.
//

import XCTest
@testable import Kinematic

@MainActor
final class SparkRound3Tests: XCTestCase {

    private func activity(_ json: String) throws -> Activity {
        try JSONDecoder().decode(Activity.self, from: Data(json.utf8))
    }

    private func place(_ json: String) throws -> CRMPlaceDetail {
        try JSONDecoder().decode(CRMPlaceDetail.self, from: Data(json.utf8))
    }

    // MARK: - outcome rule

    func testOutcomeIsRequiredWhenLoggingACompletedActivity() {
        // Logging a call / meeting / visit completes it.
        XCTAssertTrue(SparkActivityOutcome.isRequired(creating: true, scheduled: false, type: "call", existingCompleted: false))
        XCTAssertTrue(SparkActivityOutcome.isRequired(creating: true, scheduled: false, type: "meeting", existingCompleted: false))
        // A logged task only gets a due date, so it stays open: optional.
        XCTAssertFalse(SparkActivityOutcome.isRequired(creating: true, scheduled: false, type: "task", existingCompleted: false))
        // A scheduled reminder is optional whatever its type.
        XCTAssertFalse(SparkActivityOutcome.isRequired(creating: true, scheduled: true, type: "call", existingCompleted: false))
        XCTAssertFalse(SparkActivityOutcome.isRequired(creating: true, scheduled: true, type: "task", existingCompleted: false))
    }

    func testOutcomeWhenEditingFollowsTheStoredStatus() {
        XCTAssertTrue(SparkActivityOutcome.isRequired(creating: false, scheduled: false, type: "call", existingCompleted: true))
        XCTAssertFalse(SparkActivityOutcome.isRequired(creating: false, scheduled: false, type: "call", existingCompleted: false))
        // Editing ignores the type picker: only the stored state decides.
        XCTAssertTrue(SparkActivityOutcome.isRequired(creating: false, scheduled: false, type: "task", existingCompleted: true))
    }

    func testMissingOutcomeMessageOnlyWhenRequiredAndBlank() {
        XCTAssertEqual(SparkActivityOutcome.validationError("", required: true), SparkActivityOutcome.missingMessage)
        XCTAssertEqual(SparkActivityOutcome.validationError(" \n\t ", required: true), SparkActivityOutcome.missingMessage)
        XCTAssertNil(SparkActivityOutcome.validationError("Quote requested", required: true))
        XCTAssertNil(SparkActivityOutcome.validationError("", required: false))
    }

    func testOutcomeIsTrimmedAndClampedTo500() {
        XCTAssertEqual(SparkActivityOutcome.clamped("  Order confirmed \n"), "Order confirmed")
        let long = String(repeating: "x", count: 700)
        XCTAssertEqual(SparkActivityOutcome.clamped(long).count, SparkActivityOutcome.maxLength)
        XCTAssertEqual(SparkActivityOutcome.maxLength, 500)
    }

    func testCompletedStatusDetection() throws {
        XCTAssertTrue(SparkActivityOutcome.isCompleted(try activity(#"{"id":"a","status":"completed"}"#)))
        XCTAssertTrue(SparkActivityOutcome.isCompleted(try activity(#"{"id":"a","status":"done"}"#)))
        XCTAssertTrue(SparkActivityOutcome.isCompleted(try activity(#"{"id":"a","completed_at":"2026-10-08T04:12:00Z"}"#)))
        XCTAssertFalse(SparkActivityOutcome.isCompleted(try activity(#"{"id":"a","status":"open"}"#)))
        XCTAssertFalse(SparkActivityOutcome.isCompleted(try activity(#"{"id":"a","status":"cancelled"}"#)))
    }

    func testMarkCompleteAsksForAMissingOutcomeForSparkOnly() {
        XCTAssertTrue(SparkActivityOutcome.needsPromptOnComplete(spark: true, action: .markComplete, existingOutcome: nil))
        XCTAssertTrue(SparkActivityOutcome.needsPromptOnComplete(spark: true, action: .markComplete, existingOutcome: "  "))
        XCTAssertFalse(SparkActivityOutcome.needsPromptOnComplete(spark: true, action: .markComplete, existingOutcome: "Done deal"))
        XCTAssertFalse(SparkActivityOutcome.needsPromptOnComplete(spark: true, action: .reopen, existingOutcome: nil))
        XCTAssertFalse(SparkActivityOutcome.needsPromptOnComplete(spark: false, action: .markComplete, existingOutcome: nil))
    }

    func testSaveBodyCarriesOnlyTheTrimmedOutcome() {
        let body = SparkActivityOutcome.saveBody("  Visited the plant \n")
        XCTAssertEqual(body.count, 1)
        XCTAssertEqual(body["outcome"] as? String, "Visited the plant")
    }

    // MARK: - outcome on the wire (create / edit bodies)

    private func result(type: String = "call", extras: SparkActivityExtras) -> ActivityComposeResult {
        ActivityComposeResult(
            type: type, subject: "Visit", description: "", imageUrl: nil,
            when: Date(timeIntervalSince1970: 1_791_432_720), leadId: nil, customFields: [:], extras: extras
        )
    }

    func testCreateSendsTheTrimmedOutcomeAndOmitsABlankOne() {
        var filled = SparkActivityExtras()
        filled.outcome = "  Sent the quote \n"
        var body = SparkActivityBody.createBody(result(extras: filled), scheduled: false, links: [:])
        filled.apply(to: &body)
        XCTAssertEqual(body["outcome"] as? String, "Sent the quote")
        XCTAssertEqual(body["status"] as? String, "completed")

        var blank = SparkActivityExtras()
        blank.outcome = "   "
        var blankBody = SparkActivityBody.createBody(result(type: "task", extras: blank), scheduled: true, links: [:])
        blank.apply(to: &blankBody)
        XCTAssertNil(blankBody["outcome"])
    }

    func testEditSendsOnlyAChangedOutcomeAndNullWhenCleared() {
        var before = SparkActivityExtras()
        before.outcome = "Quote sent"

        var untouched: [String: Any] = [:]
        before.apply(to: &untouched, previous: before)
        XCTAssertNil(untouched["outcome"])

        var edited = before
        edited.outcome = "Quote accepted"
        var changed: [String: Any] = [:]
        edited.apply(to: &changed, previous: before)
        XCTAssertEqual(changed["outcome"] as? String, "Quote accepted")

        var cleared = before
        cleared.outcome = "  "
        var nulled: [String: Any] = [:]
        cleared.apply(to: &nulled, previous: before)
        XCTAssertTrue(nulled["outcome"] is NSNull)

        // A blank outcome on a row that never had one changes nothing.
        var neverHad: [String: Any] = [:]
        SparkActivityExtras().apply(to: &neverHad, previous: SparkActivityExtras())
        XCTAssertNil(neverHad["outcome"])
    }

    func testEditSeedsTheOutcomeFromTheRowAndSparkPatchCarriesTheChange() throws {
        let row = try activity(#"{"id":"a1","status":"completed","completed_at":"2026-10-08T04:12:00Z","outcome":"Quote sent"}"#)
        XCTAssertEqual(row.sparkExtras.outcome, "Quote sent")
        var edited = row.sparkExtras
        edited.outcome = "Quote accepted"
        let parts = ActivityEditBody.sparkPatch(
            existing: row, result: result(extras: edited), canChangeAssignees: true
        )
        var body = parts.body
        parts.extras.apply(to: &body, previous: parts.previous)
        XCTAssertEqual(body["outcome"] as? String, "Quote accepted")
    }

    func testAPersonWhoCannotChangeAssigneesStillSavesTheirOutcome() throws {
        let row = try activity(#"{"id":"a1","assigned_to":"u1","outcome":"Old"}"#)
        var edited = row.sparkExtras
        edited.outcome = "New"
        edited.assigneeIds = ["u9"]
        let parts = ActivityEditBody.sparkPatch(existing: row, result: result(extras: edited), canChangeAssignees: false)
        XCTAssertEqual(parts.extras.assigneeIds, ["u1"])
        XCTAssertEqual(parts.extras.outcome, "New")
    }

    func testTheGenericEditBodyNeverCarriesAnOutcome() {
        let body = ActivityEditBody.patch(
            type: "call", subject: "S", description: "d", imageUrl: nil, completedAt: nil,
            customFields: [:], assignment: [:], canChangeAssignee: false
        )
        XCTAssertNotNil(body)
        XCTAssertNil(body?["outcome"])
    }

    func testCompletionKeepsTheRowsCompanyAndTakesTheSavedOutcome() throws {
        let row = try activity(#"{"id":"a1","status":"open","company_id":"acc-1","company_name":"Acme"}"#)
        let response = try activity(#"{"id":"a1","status":"completed","completed_at":"2026-10-08T04:12:00Z","outcome":"Closed the loop"}"#)
        let merged = row.applyingCompletion(from: response)
        XCTAssertEqual(merged.companyId, "acc-1")
        XCTAssertEqual(merged.companyName, "Acme")
        XCTAssertEqual(merged.outcome, "Closed the loop")
        XCTAssertEqual(merged.effectiveStatus, "completed")
    }

    // MARK: - company on an activity

    func testActivityDecodesTheCompany() throws {
        let a = try activity(#"{"id":"a1","company_id":"acc-1","company_name":"Acme Forge"}"#)
        XCTAssertEqual(a.companyId, "acc-1")
        XCTAssertEqual(a.companyName, "Acme Forge")
        let none = try activity(#"{"id":"a2"}"#)
        XCTAssertNil(none.companyId)
        XCTAssertNil(none.companyName)
    }

    func testCompanyIsALinkWhenThereIsAnAccountAndPlainTextWhenOnlyAName() throws {
        let linked = try activity(#"{"id":"a1","company_id":"acc-1","company_name":" Acme Forge "}"#)
        XCTAssertEqual(ActivityCompany.display(for: linked, spark: true), .link(id: "acc-1", name: "Acme Forge"))

        let textOnly = try activity(#"{"id":"a2","company_id":null,"company_name":"Lead Co"}"#)
        XCTAssertEqual(ActivityCompany.display(for: textOnly, spark: true), .text("Lead Co"))

        let idOnly = try activity(#"{"id":"a3","company_id":"acc-2"}"#)
        XCTAssertEqual(ActivityCompany.display(for: idOnly, spark: true), .link(id: "acc-2", name: "Company"))

        let neither = try activity(#"{"id":"a4","company_name":"  "}"#)
        XCTAssertEqual(ActivityCompany.display(for: neither, spark: true), .hidden)
    }

    func testOtherTenantsNeverShowACompany() throws {
        let a = try activity(#"{"id":"a1","company_id":"acc-1","company_name":"Acme"}"#)
        XCTAssertEqual(ActivityCompany.display(for: a, spark: false), .hidden)
    }

    func testAnEditResponseWithoutACompanyKeepsTheRowsOwn() throws {
        let row = try activity(#"{"id":"a1","company_id":"acc-1","company_name":"Acme"}"#)
        let patched = try activity(#"{"id":"a1","subject":"Renamed"}"#)
        let merged = patched.keepingCompany(of: row)
        XCTAssertEqual(merged.companyName, "Acme")
        XCTAssertEqual(merged.subject, "Renamed")
        // A response that has its own company wins.
        let own = try activity(#"{"id":"a1","company_id":"acc-9","company_name":"Other"}"#)
        XCTAssertEqual(own.keepingCompany(of: row).companyId, "acc-9")
        // And the list swap used by both edit paths applies it.
        XCTAssertEqual(ActivityEditRouting.replacing(patched, in: [row]).first?.companyId, "acc-1")
    }

    // MARK: - Activities list filters

    func testQueryCarriesAccountAndOwnerOnlyWhenSet() {
        let all = ActivityQuery.params(ownerId: "u-1", accountId: "acc-1", city: "Pune", from: "2026-10-01T00:00:00+05:30")
        XCTAssertEqual(all["owner_id"], "u-1")
        XCTAssertEqual(all["account_id"], "acc-1")
        XCTAssertEqual(all["city"], "Pune")
        XCTAssertEqual(all["from"], "2026-10-01T00:00:00+05:30")

        let none = ActivityQuery.params(ownerId: nil, accountId: nil, city: "", state: nil)
        XCTAssertTrue(none.isEmpty)
        XCTAssertNil(ActivityQuery.params(ownerId: "  ", accountId: "")["owner_id"])
        XCTAssertNil(ActivityQuery.params(ownerId: "  ", accountId: "")["account_id"])
    }

    func testOwnerFilterAllMeansNoParameter() {
        XCTAssertNil(ActivityQuery.ownerParam("all"))
        XCTAssertNil(ActivityQuery.ownerParam(""))
        XCTAssertEqual(ActivityQuery.ownerParam("u-9"), "u-9")
    }

    func testPickingAndClearingTheFiltersBuildsTheRightParameters() {
        // The view model only holds the choice; the request is built from it by `ActivityQuery`.
        let vm = ActivitiesViewModel()
        vm.ownerFilter = "u-5"
        vm.accountFilterId = "acc-5"
        let q = ActivityQuery.params(
            ownerId: ActivityQuery.ownerParam(vm.ownerFilter), accountId: vm.accountFilterId
        )
        XCTAssertEqual(q["owner_id"], "u-5")
        XCTAssertEqual(q["account_id"], "acc-5")
        vm.ownerFilter = "all"
        vm.accountFilterId = nil
        let cleared = ActivityQuery.params(
            ownerId: ActivityQuery.ownerParam(vm.ownerFilter), accountId: vm.accountFilterId
        )
        XCTAssertTrue(cleared.isEmpty)
        XCTAssertEqual(vm.userFilterTitle, "User")
    }

    // MARK: - account addresses (sites)

    func testSiteDecodesAndFormatsItsAddress() throws {
        let json = """
        {"id":"s1","account_id":"acc-1","name":"Head office","address_line1":"12 MG Road","address_line2":"Near Metro",
         "city":"Pune","state":"Maharashtra","postal_code":"411001","country":"India","latitude":18.52,"longitude":73.85}
        """
        let site = try JSONDecoder().decode(AccountSite.self, from: Data(json.utf8))
        XCTAssertEqual(site.title, "Head office")
        XCTAssertEqual(site.streetLine, "12 MG Road, Near Metro")
        XCTAssertEqual(site.localityLine, "Pune, Maharashtra 411001")
        XCTAssertTrue(site.hasCoordinates)

        let bare = try JSONDecoder().decode(AccountSite.self, from: Data(#"{"id":"s2","latitude":0,"longitude":0}"#.utf8))
        XCTAssertEqual(bare.title, "Address")
        XCTAssertEqual(bare.streetLine, "")
        XCTAssertEqual(bare.localityLine, "")
        XCTAssertFalse(bare.hasCoordinates)
    }

    func testAddAddressNeedsALabel() {
        var draft = AccountAddressDraft()
        XCTAssertEqual(draft.validationError, AccountAddressDraft.missingLabelMessage)
        draft.label = "   "
        XCTAssertNotNil(draft.validationError)
        draft.label = "Head office"
        XCTAssertNil(draft.validationError)
    }

    func testCreateBodyCarriesTheAccountLabelFilledFieldsAndThePin() {
        var draft = AccountAddressDraft()
        draft.label = "  Head office "
        draft.addressLine1 = " 12 MG Road "
        draft.city = "Pune"
        draft.state = "Maharashtra"
        draft.postalCode = "411001"
        draft.latitude = 18.52
        draft.longitude = 73.85
        let body = draft.createBody(accountId: "acc-1")
        XCTAssertEqual(body["account_id"] as? String, "acc-1")
        XCTAssertEqual(body["name"] as? String, "Head office")
        XCTAssertEqual(body["address_line1"] as? String, "12 MG Road")
        XCTAssertEqual(body["city"] as? String, "Pune")
        XCTAssertEqual(body["state"] as? String, "Maharashtra")
        XCTAssertEqual(body["postal_code"] as? String, "411001")
        XCTAssertEqual(body["country"] as? String, "India")
        XCTAssertEqual(body["latitude"] as? Double, 18.52)
        XCTAssertEqual(body["longitude"] as? Double, 73.85)
        // Blank optional fields are left out.
        XCTAssertNil(body["address_line2"])
        XCTAssertNil(body["phone"])
        XCTAssertNil(body["notes"])
    }

    func testCreateBodyLeavesOutAnUnusablePin() {
        var draft = AccountAddressDraft()
        draft.label = "Plant"
        draft.latitude = 0
        draft.longitude = 0
        let body = draft.createBody(accountId: "acc-1")
        XCTAssertNil(body["latitude"])
        XCTAssertNil(body["longitude"])
    }

    func testPatchBodySendsClearedFieldsAsNull() throws {
        let site = try JSONDecoder().decode(
            AccountSite.self,
            from: Data(#"{"id":"s1","name":"Plant","address_line1":"1 Ring Rd","address_line2":"Gate 2","city":"Pune","latitude":18.5,"longitude":73.8}"#.utf8)
        )
        var draft = AccountAddressDraft(site: site)
        XCTAssertEqual(draft.label, "Plant")
        XCTAssertEqual(draft.country, "India")
        draft.addressLine2 = ""
        draft.latitude = nil
        draft.longitude = nil
        let body = draft.patchBody()
        XCTAssertEqual(body["name"] as? String, "Plant")
        XCTAssertEqual(body["address_line1"] as? String, "1 Ring Rd")
        XCTAssertTrue(body["address_line2"] is NSNull)
        XCTAssertTrue(body["phone"] is NSNull)
        XCTAssertTrue(body["latitude"] is NSNull)
        XCTAssertTrue(body["longitude"] is NSNull)
    }

    func testPickingAGooglePlaceFillsTheFieldsAndThePin() throws {
        var draft = AccountAddressDraft()
        draft.addressLine2 = "Typed by hand"
        draft.apply(place: try place(#"{"address_line1":"12 MG Road","city":"Pune","state":"Maharashtra","postal_code":"411001","latitude":18.52,"longitude":73.85}"#))
        XCTAssertEqual(draft.addressLine1, "12 MG Road")
        XCTAssertEqual(draft.city, "Pune")
        XCTAssertEqual(draft.state, "Maharashtra")
        XCTAssertEqual(draft.postalCode, "411001")
        XCTAssertEqual(draft.latitude, 18.52)
        XCTAssertEqual(draft.longitude, 73.85)
        XCTAssertEqual(draft.addressLine2, "Typed by hand")
    }

    func testAPlaceWithoutCoordinatesDropsTheOldPin() throws {
        var draft = AccountAddressDraft()
        draft.latitude = 10
        draft.longitude = 20
        draft.apply(place: try place(#"{"address_line1":"5 New St","city":"Delhi"}"#))
        XCTAssertEqual(draft.city, "Delhi")
        XCTAssertNil(draft.latitude)
        XCTAssertNil(draft.longitude)
    }

    // MARK: - contacts <-> company

    private func contact(_ json: String) throws -> Contact {
        try JSONDecoder().decode(Contact.self, from: Data(json.utf8))
    }

    func testSparkCallsTheLinkCompanyEverywhereElseAccount() {
        XCTAssertEqual(SparkContactCompany.label(spark: true), "Company")
        XCTAssertEqual(SparkContactCompany.label(spark: false), "Account")
    }

    func testContactRowShowsItsCompanyAsALinkForSparkOnly() throws {
        let c = try contact(#"{"id":"c1","account_id":"acc-1","account_name":" Acme Forge "}"#)
        let line = SparkContactCompany.line(for: c, spark: true)
        XCTAssertEqual(line?.id, "acc-1")
        XCTAssertEqual(line?.name, "Acme Forge")
        XCTAssertNil(SparkContactCompany.line(for: c, spark: false))

        let unlinked = try contact(#"{"id":"c2","first_name":"Asha"}"#)
        XCTAssertNil(SparkContactCompany.line(for: unlinked, spark: true))

        let nameless = try contact(#"{"id":"c3","account_id":"acc-3"}"#)
        XCTAssertEqual(SparkContactCompany.line(for: nameless, spark: true)?.name, "Company")
    }

    func testContactCompanyPatchSetsOrClearsTheAccount() {
        XCTAssertEqual(SparkContactCompany.accountPatch(selectedId: "acc-1")["account_id"] as? String, "acc-1")
        XCTAssertTrue(SparkContactCompany.accountPatch(selectedId: "")["account_id"] is NSNull)
        XCTAssertTrue(SparkContactCompany.accountPatch(selectedId: nil)["account_id"] is NSNull)
    }

    // MARK: - account outcome (read-only legacy value)

    func testAnAccountStillDecodesItsEarlierOutcome() throws {
        let with = try JSONDecoder().decode(CRMAccount.self, from: Data(#"{"id":"a1","name":"Acme","outcome":"Rate contract"}"#.utf8))
        XCTAssertEqual(with.outcome, "Rate contract")
        let without = try JSONDecoder().decode(CRMAccount.self, from: Data(#"{"id":"a2","name":"Other"}"#.utf8))
        XCTAssertNil(without.outcome)
    }
}
