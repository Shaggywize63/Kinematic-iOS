//
//  RecordOwnerChangeTests.swift
//  KinematicTests
//
//  Changing a record's owner / assignee after it exists (accounts, deals, activities): who may do it (the
//  backend's owner-assign roles, never a data-scope "own" user), that an edit sends the owner / assignee ONLY
//  when it really changed, that removing every assignee of a Spark & Ray activity sends `assignee_ids: []`
//  (and nothing else touches assignees), and that a person who may not change them cannot send a change.
//

import XCTest
import Foundation
@testable import Kinematic

@MainActor
final class RecordOwnerChangeTests: XCTestCase {

    // MARK: - who may change an owner

    func testAdminsAndManagersMayChangeAnOwner() {
        for role in ["super_admin", "admin", "main_admin", "sub_admin", "city_manager", "supervisor", "client"] {
            XCTAssertTrue(RecordOwnerRules.canChangeRecordOwner(role: role, dataScope: nil), role)
            XCTAssertTrue(RecordOwnerRules.canChangeRecordOwner(role: role, dataScope: "all"), role)
            XCTAssertTrue(RecordOwnerRules.canChangeRecordOwner(role: role, dataScope: "team"), role)
        }
    }

    func testOtherRolesNeverMayChangeAnOwner() {
        for role in ["executive", "salesman", "manager", "hr", "org_admin", "program_manager", "", "nonsense"] {
            XCTAssertFalse(RecordOwnerRules.canChangeRecordOwner(role: role, dataScope: nil), role)
            XCTAssertFalse(RecordOwnerRules.canChangeRecordOwner(role: role, dataScope: "all"), role)
        }
        XCTAssertFalse(RecordOwnerRules.canChangeRecordOwner(role: nil, dataScope: nil))
        XCTAssertFalse(RecordOwnerRules.canChangeRecordOwner(role: nil, dataScope: "all"))
    }

    func testAnOrgRoleLimitedToOwnRecordsNeverMay() {
        for role in RecordOwnerRules.changeRoles {
            XCTAssertFalse(RecordOwnerRules.canChangeRecordOwner(role: role, dataScope: "own"), role)
            XCTAssertFalse(RecordOwnerRules.canChangeRecordOwner(role: role, dataScope: " OWN "), role)
        }
    }

    func testRoleAndScopeAreCaseAndWhitespaceInsensitive() {
        XCTAssertTrue(RecordOwnerRules.canChangeRecordOwner(role: " Admin ", dataScope: ""))
        XCTAssertTrue(RecordOwnerRules.canChangeRecordOwner(role: "CITY_MANAGER", dataScope: "Team"))
    }

    func testTheRoleSetMatchesTheBackend() {
        XCTAssertEqual(RecordOwnerRules.changeRoles,
                       ["super_admin", "admin", "main_admin", "sub_admin", "city_manager", "supervisor", "client"])
    }

    // MARK: - owner on the PATCH body (accounts, deals)

    func testAnUntouchedOwnerSendsNothing() {
        XCTAssertTrue(RecordOwnerRules.ownerPatch(original: "u1", selected: "u1").isEmpty)
        XCTAssertTrue(RecordOwnerRules.ownerPatch(original: "U1", selected: "u1").isEmpty)
        XCTAssertTrue(RecordOwnerRules.ownerPatch(original: nil, selected: "").isEmpty)
        XCTAssertTrue(RecordOwnerRules.ownerPatch(original: nil, selected: nil).isEmpty)
        XCTAssertTrue(RecordOwnerRules.ownerPatch(original: "u1", selected: "").isEmpty)
        XCTAssertTrue(RecordOwnerRules.ownerPatch(original: "u1", selected: nil).isEmpty)
        XCTAssertFalse(RecordOwnerRules.ownerChanged(original: "u1", selected: "  "))
    }

    func testAChangedOwnerIsSent() {
        XCTAssertEqual(RecordOwnerRules.ownerPatch(original: "u1", selected: "u2")["owner_id"] as? String, "u2")
        XCTAssertEqual(RecordOwnerRules.ownerPatch(original: nil, selected: "u2")["owner_id"] as? String, "u2")
        XCTAssertEqual(RecordOwnerRules.ownerPatch(original: "", selected: " u2 ")["owner_id"] as? String, "u2")
        XCTAssertEqual(RecordOwnerRules.ownerPatch(original: "u1", selected: "u2").count, 1)
    }

    func testApplyOwnerOnlyAddsTheKeyWhenChanged() {
        var body: [String: Any] = ["name": "Acme"]
        RecordOwnerRules.applyOwner(original: "u1", selected: "u1", to: &body)
        XCTAssertNil(body["owner_id"])
        XCTAssertEqual(body.count, 1)

        RecordOwnerRules.applyOwner(original: "u1", selected: "u2", to: &body)
        XCTAssertEqual(body["owner_id"] as? String, "u2")
        XCTAssertEqual(body["name"] as? String, "Acme")
    }

    // MARK: - single assignee (activities of clients without multi-assignee)

    func testAssignedToIsSentOnlyWhenADifferentPersonWasPicked() {
        XCTAssertTrue(RecordOwnerRules.assignedToPatch(original: "u1", selected: nil).isEmpty)
        XCTAssertTrue(RecordOwnerRules.assignedToPatch(original: "u1", selected: "u1").isEmpty)
        XCTAssertEqual(RecordOwnerRules.assignedToPatch(original: "u1", selected: "u2")["assigned_to"] as? String, "u2")
        XCTAssertEqual(RecordOwnerRules.assignedToPatch(original: nil, selected: "u2")["assigned_to"] as? String, "u2")
        XCTAssertNil(RecordOwnerRules.assignedToPatch(original: "u1", selected: "u2")["owner_id"])
    }

    func testPickingTheCurrentAssigneeAgainClearsThePendingChange() {
        XCTAssertNil(RecordOwnerRules.selectionAfterPick("u1", original: "u1"))
        XCTAssertNil(RecordOwnerRules.selectionAfterPick("", original: nil))
        XCTAssertNil(RecordOwnerRules.selectionAfterPick("", original: "u1"))
        XCTAssertEqual(RecordOwnerRules.selectionAfterPick("u2", original: "u1"), "u2")
    }

    // MARK: - Spark & Ray: replace / remove assignees on an edit

    func testRemovingEveryAssigneeSendsAnEmptyList() {
        let before = SparkActivityExtras(assigneeIds: ["u1", "u2"])
        var body: [String: Any] = [:]
        SparkActivityExtras(assigneeIds: []).apply(to: &body, previous: before)
        XCTAssertEqual(body["assignee_ids"] as? [String], [])
        XCTAssertNil(body["product_ids"])
        XCTAssertNil(body["form_serial"])
    }

    func testReplacingAssigneesSendsTheNewList() {
        let before = SparkActivityExtras(assigneeIds: ["u1", "u2"])
        var body: [String: Any] = [:]
        SparkActivityExtras(assigneeIds: ["u3"]).apply(to: &body, previous: before)
        XCTAssertEqual(body["assignee_ids"] as? [String], ["u3"])
    }

    func testAnEditThatLeavesAssigneesAloneSendsNone() {
        let before = SparkActivityExtras(assigneeIds: ["u1", "u2"])
        var body: [String: Any] = [:]
        before.apply(to: &body, previous: before)
        XCTAssertNil(body["assignee_ids"])

        // Nobody before, nobody after: still nothing on the wire.
        var none: [String: Any] = [:]
        SparkActivityExtras().apply(to: &none, previous: SparkActivityExtras())
        XCTAssertTrue(none.isEmpty)
    }

    func testCreatingWithNoAssigneesStillSendsNoList() {
        var body: [String: Any] = [:]
        SparkActivityExtras().apply(to: &body)
        XCTAssertNil(body["assignee_ids"])
    }

    func testSomeoneWhoMayNotChangeAssigneesKeepsTheExistingOnes() {
        let before = SparkActivityExtras(assigneeIds: ["u1", "u2"], productIds: ["p1"], formSerial: "A-1")
        // The form somehow holds no assignees and a new product.
        var edited = before
        edited.assigneeIds = []
        edited.productIds = ["p2"]

        let kept = RecordOwnerRules.extrasForEdit(edited: edited, previous: before, canChangeAssignees: false)
        XCTAssertEqual(kept.assigneeIds, ["u1", "u2"])
        XCTAssertEqual(kept.productIds, ["p2"])
        var body: [String: Any] = [:]
        kept.apply(to: &body, previous: before)
        XCTAssertNil(body["assignee_ids"])
        XCTAssertEqual(body["product_ids"] as? [String], ["p2"])

        // An admin's edit goes through untouched.
        let admin = RecordOwnerRules.extrasForEdit(edited: edited, previous: before, canChangeAssignees: true)
        XCTAssertEqual(admin.assigneeIds, [])
        var adminBody: [String: Any] = [:]
        admin.apply(to: &adminBody, previous: before)
        XCTAssertEqual(adminBody["assignee_ids"] as? [String], [])
    }

    // MARK: - the activity's own assignee fields

    func testActivityDecodesAssignedTo() throws {
        let a = try JSONDecoder().decode(
            Activity.self,
            from: Data(#"{"id":"a1","assigned_to":"u9","assigned_to_name":"Asha"}"#.utf8)
        )
        XCTAssertEqual(a.assignedTo, "u9")
        XCTAssertEqual(a.assignedToName, "Asha")
        let plain = try JSONDecoder().decode(Activity.self, from: Data(#"{"id":"a1"}"#.utf8))
        XCTAssertNil(plain.assignedTo)
        XCTAssertNil(plain.assignedToName)
    }

    func testAnActivityWithOnlyAPrimaryAssigneeShowsThemAsTheAssignee() throws {
        let a = try JSONDecoder().decode(
            Activity.self,
            from: Data(#"{"id":"a1","assigned_to":"u9","assigned_to_name":"Asha"}"#.utf8)
        )
        XCTAssertEqual(a.sparkExtras.assigneeIds, ["u9"])
        XCTAssertEqual(a.sparkNames["u9"], "Asha")

        // Removing them is a real change that clears the activity.
        var body: [String: Any] = [:]
        SparkActivityExtras().apply(to: &body, previous: a.sparkExtras)
        XCTAssertEqual(body["assignee_ids"] as? [String], [])
    }

    func testTheAssigneeListWinsOverAssignedTo() throws {
        let a = try JSONDecoder().decode(
            Activity.self,
            from: Data(#"{"id":"a1","assigned_to":"u9","assignees":[{"id":"u9","name":"Asha"},{"id":"u8","name":"Ravi"}]}"#.utf8)
        )
        XCTAssertEqual(a.sparkExtras.assigneeIds, ["u9", "u8"])
    }

    func testCompletionMergeKeepsTheAssignee() throws {
        let row = try JSONDecoder().decode(
            Activity.self,
            from: Data(#"{"id":"a1","status":"open","assigned_to":"u9","assigned_to_name":"Asha"}"#.utf8)
        )
        let patched = try JSONDecoder().decode(Activity.self, from: Data(#"{"id":"a1","status":"completed"}"#.utf8))
        let merged = row.applyingCompletion(from: patched)
        XCTAssertEqual(merged.assignedTo, "u9")
        XCTAssertEqual(merged.assignedToName, "Asha")
        XCTAssertEqual(merged.status, "completed")
    }

    func testAccountDecodesTheOwnerName() throws {
        let a = try JSONDecoder().decode(
            CRMAccount.self,
            from: Data(#"{"id":"c1","name":"Acme","owner_id":"u1","owner_name":"Asha"}"#.utf8)
        )
        XCTAssertEqual(a.ownerId, "u1")
        XCTAssertEqual(a.ownerName, "Asha")
    }
}
