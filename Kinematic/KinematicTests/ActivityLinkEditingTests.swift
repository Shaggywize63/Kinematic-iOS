//
//  ActivityLinkEditingTests.swift
//  KinematicTests
//
//  Editing an activity's "Linked entity" (Lead / Contact / Deal / Account / None) and its "Activity date &
//  time": the pre-fill from the row, the PATCH rules (link only when changed, the other three ids explicit
//  null, "None" nulls all four, a type without a record blocks the save) and the date rules (only when it was
//  edited, never in the future).
//

import XCTest
import Foundation
@testable import Kinematic

final class ActivityLinkEditingTests: XCTestCase {

    private func activity(_ json: String) throws -> Activity {
        try JSONDecoder().decode(Activity.self, from: Data(json.utf8))
    }

    private func draft(_ json: String) throws -> ActivityLinkDraft {
        ActivityLinkDraft(original: ActivityLinkEditing.initialLink(for: try activity(json)))
    }

    private func isNull(_ value: Any?) -> Bool { value is NSNull }

    // MARK: - pre-fill

    func testTheFirstPresentLinkWinsInTheOrderLeadContactDealAccount() throws {
        let all = try activity(#"{"id":"a","lead_id":"L","contact_id":"C","deal_id":"D","account_id":"A","lead_name":"Lee"}"#)
        XCTAssertEqual(ActivityLinkEditing.initialLink(for: all), ActivityLink(type: .lead, id: "L", name: "Lee"))
        let noLead = try activity(#"{"id":"a","contact_id":"C","deal_id":"D","account_id":"A","contact_name":"Cy"}"#)
        XCTAssertEqual(ActivityLinkEditing.initialLink(for: noLead), ActivityLink(type: .contact, id: "C", name: "Cy"))
        let dealOnly = try activity(#"{"id":"a","deal_id":"D","account_id":"A","deal_name":"Big deal"}"#)
        XCTAssertEqual(ActivityLinkEditing.initialLink(for: dealOnly)?.type, .deal)
        let account = try activity(#"{"id":"a","account_id":"A","account_name":"Acme"}"#)
        XCTAssertEqual(ActivityLinkEditing.initialLink(for: account), ActivityLink(type: .account, id: "A", name: "Acme"))
    }

    func testNoLinkMeansNoneAndBlankIdsAreIgnored() throws {
        XCTAssertNil(ActivityLinkEditing.initialLink(for: try activity(#"{"id":"a"}"#)))
        let blanks = try activity(#"{"id":"a","lead_id":"  ","contact_id":"","account_id":"A"}"#)
        XCTAssertEqual(ActivityLinkEditing.initialLink(for: blanks)?.type, .account)
        XCTAssertNil(try draft(#"{"id":"a"}"#).type)
    }

    func testAMissingNameIsFlaggedForALookupAndAppliedOnce() throws {
        var d = try draft(#"{"id":"a","contact_id":"C"}"#)
        XCTAssertTrue(d.needsNameLookup)
        XCTAssertNil(d.displayName)
        d.applyResolvedName("  Cy Rao ")
        XCTAssertEqual(d.displayName, "Cy Rao")
        XCTAssertFalse(d.needsNameLookup)
        // A later (stray) name never overwrites the one we have.
        d.applyResolvedName("Someone else")
        XCTAssertEqual(d.displayName, "Cy Rao")
        XCTAssertFalse(d.isChanged)
    }

    // MARK: - patch

    func testAnUntouchedLinkSendsNothing() throws {
        let d = try draft(#"{"id":"a","lead_id":"L","lead_name":"Lee"}"#)
        XCTAssertFalse(d.isChanged)
        XCTAssertNil(d.validationError)
        XCTAssertTrue(d.patch.isEmpty)
        XCTAssertTrue(ActivityLinkDraft().patch.isEmpty)
    }

    func testChangingTheRecordSetsItsIdAndNullsTheOtherThree() throws {
        var d = try draft(#"{"id":"a","lead_id":"L","lead_name":"Lee"}"#)
        d.select(.contact)
        d.pick(id: "C9", name: "Cy")
        XCTAssertTrue(d.isChanged)
        let patch = d.patch
        XCTAssertEqual(patch["contact_id"] as? String, "C9")
        XCTAssertTrue(isNull(patch["lead_id"]))
        XCTAssertTrue(isNull(patch["deal_id"]))
        XCTAssertTrue(isNull(patch["account_id"]))
        XCTAssertEqual(Set(patch.keys), ["lead_id", "contact_id", "deal_id", "account_id"])
    }

    func testPickingADifferentRecordOfTheSameTypeIsAChange() throws {
        var d = try draft(#"{"id":"a","deal_id":"D","deal_name":"Old"}"#)
        d.pick(id: "D2", name: "New")
        XCTAssertEqual(d.patch["deal_id"] as? String, "D2")
        XCTAssertTrue(isNull(d.patch["lead_id"]))
    }

    func testNoneNullsAllFourWhenTheActivityHadALink() throws {
        var d = try draft(#"{"id":"a","account_id":"A","account_name":"Acme"}"#)
        d.select(nil)
        XCTAssertTrue(d.isChanged)
        XCTAssertNil(d.validationError)
        let patch = d.patch
        XCTAssertEqual(Set(patch.keys), ["lead_id", "contact_id", "deal_id", "account_id"])
        for key in patch.keys { XCTAssertTrue(isNull(patch[key]), key) }
    }

    func testNoneOnAnUnlinkedActivityIsNotAChange() throws {
        var d = try draft(#"{"id":"a"}"#)
        d.select(nil)
        XCTAssertFalse(d.isChanged)
        XCTAssertTrue(d.patch.isEmpty)
    }

    func testChoosingATypeWithoutARecordBlocksTheSave() throws {
        var d = try draft(#"{"id":"a","lead_id":"L","lead_name":"Lee"}"#)
        d.select(.contact)
        XCTAssertEqual(d.validationError, "Pick a contact to link, or choose None.")
        XCTAssertTrue(d.patch.isEmpty)
        d.select(.deal)
        XCTAssertEqual(d.validationError, "Pick a deal to link, or choose None.")
        // Picking clears the error.
        d.pick(id: "D1", name: "Deal")
        XCTAssertNil(d.validationError)
        // Linking an unlinked activity: same rule.
        var fresh = ActivityLinkDraft()
        fresh.select(.account)
        XCTAssertEqual(fresh.validationError, "Pick a account to link, or choose None.")
    }

    func testGoingBackToTheOriginalTypeRestoresItsRecord() throws {
        var d = try draft(#"{"id":"a","lead_id":"L","lead_name":"Lee"}"#)
        d.select(.contact)
        XCTAssertNil(d.displayName)
        d.select(.lead)
        XCTAssertEqual(d.displayName, "Lee")
        XCTAssertFalse(d.isChanged)
        XCTAssertTrue(d.patch.isEmpty)
    }

    // MARK: - request bodies

    private let edited = Date(timeIntervalSince1970: 1_800_000_000)
    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    private func patchBody(completedAt: Date?, type: String = "call", linkPatch: [String: Any] = [:]) throws -> [String: Any] {
        try XCTUnwrap(ActivityEditBody.patch(
            type: type, subject: "Visit", description: "", imageUrl: nil, completedAt: completedAt,
            customFields: [:], assignment: [:], canChangeAssignee: false, linkPatch: linkPatch
        ))
    }

    func testAnUntouchedSaveSendsNoLinkOrDateKeys() throws {
        let state = ActivityEditState(activity: try activity(#"{"id":"a","lead_id":"L","completed_at":"2026-10-01T10:00:00Z"}"#))
        let body = try patchBody(completedAt: state.dateToSend(edited), linkPatch: state.link.patch)
        for key in ["lead_id", "contact_id", "deal_id", "account_id", "completed_at", "due_at", "status"] {
            XCTAssertNil(body[key], key)
        }
    }

    func testAnEditedDateIsSentAsCompletedAt() throws {
        var state = ActivityEditState(activity: try activity(#"{"id":"a","completed_at":"2026-10-01T10:00:00Z"}"#))
        state.dateEdited = true
        let body = try patchBody(completedAt: state.dateToSend(edited))
        XCTAssertEqual(body["completed_at"] as? String, iso(edited))
    }

    func testAChangedLinkIsMergedIntoTheBody() throws {
        var state = ActivityEditState(activity: try activity(#"{"id":"a","lead_id":"L"}"#))
        state.link.select(.account)
        state.link.pick(id: "A1", name: "Acme")
        let body = try patchBody(completedAt: nil, linkPatch: state.link.patch)
        XCTAssertEqual(body["account_id"] as? String, "A1")
        XCTAssertTrue(isNull(body["lead_id"]))
        XCTAssertTrue(isNull(body["contact_id"]))
        XCTAssertTrue(isNull(body["deal_id"]))
    }

    func testTheSparkPatchCarriesTheLinkAndSkipsAnUntouchedDate() throws {
        let row = try activity(#"{"id":"a","status":"completed","completed_at":"2026-10-01T10:00:00Z","contact_id":"C"}"#)
        var state = ActivityEditState(activity: row)
        state.link.select(nil)
        var result = ActivityComposeResult(
            type: "meeting", subject: "Visit", description: "", imageUrl: nil, when: edited, leadId: nil,
            customFields: [:], extras: SparkActivityExtras()
        )
        result.whenEdited = state.dateEdited
        result.linkPatch = state.link.patch
        let body = ActivityEditBody.sparkPatch(existing: row, result: result, canChangeAssignees: false).body
        XCTAssertNil(body["completed_at"])
        XCTAssertNil(body["due_at"])
        for key in ["lead_id", "contact_id", "deal_id", "account_id"] { XCTAssertTrue(isNull(body[key]), key) }

        // Edited date: the completed row gets its completed_at.
        var withDate = result
        withDate.whenEdited = true
        let dated = ActivityEditBody.sparkPatch(existing: row, result: withDate, canChangeAssignees: false).body
        XCTAssertEqual(dated["completed_at"] as? String, iso(edited))
    }

    // MARK: - date

    func testTheActivityDateShowsOnlyWhenTheActivityHasCompletedAt() throws {
        XCTAssertTrue(ActivityDateEditing.showsActivityDate(for: try activity(#"{"id":"a","completed_at":"2026-10-01T10:00:00Z"}"#)))
        XCTAssertFalse(ActivityDateEditing.showsActivityDate(for: try activity(#"{"id":"a","due_at":"2026-10-01T10:00:00Z"}"#)))
        XCTAssertFalse(ActivityDateEditing.showsActivityDate(for: try activity(#"{"id":"a","completed_at":""}"#)))
        XCTAssertEqual(
            ActivityDateEditing.completedAt(of: try activity(#"{"id":"a","completed_at":"2026-10-01T10:00:00Z"}"#)),
            SparkJourney.parseISO("2026-10-01T10:00:00Z")
        )
        XCTAssertNil(ActivityDateEditing.completedAt(of: try activity(#"{"id":"a"}"#)))
    }

    func testTheActivityDateCannotBeInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(ActivityDateEditing.validationError(for: now.addingTimeInterval(-3600), now: now))
        XCTAssertNil(ActivityDateEditing.validationError(for: now, now: now))
        XCTAssertEqual(
            ActivityDateEditing.validationError(for: now.addingTimeInterval(3600), now: now),
            "Activity date can't be in the future."
        )
    }

    func testTheActivityDecodesItsAccountName() throws {
        XCTAssertEqual(try activity(#"{"id":"a","account_id":"A","account_name":"Acme"}"#).accountName, "Acme")
    }

    // MARK: - deal picker filter

    func testTheDealPickerFiltersByNameIgnoringCase() {
        let names = ["Alpha Steel", "beta Forge", "Gamma"]
        XCTAssertEqual(ActivityLinkEditing.filter(names, query: "") { $0 }, names)
        XCTAssertEqual(ActivityLinkEditing.filter(names, query: " FORGE ") { $0 }, ["beta Forge"])
        XCTAssertEqual(ActivityLinkEditing.filter(names, query: "zzz") { $0 }, [])
    }
}
