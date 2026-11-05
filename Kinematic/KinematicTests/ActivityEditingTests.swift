//
//  ActivityEditingTests.swift
//  KinematicTests
//
//  Editing an existing activity from any screen (the Activities list and the account detail share one path):
//  which row an edit entry opens, how the saved row lands back in the list, what the edit sheet starts from,
//  and the PATCH bodies (generic and Spark) including the admin / manager-only assignee rule.
//

import XCTest
import Foundation
@testable import Kinematic

final class ActivityEditingTests: XCTestCase {

    private func activity(_ json: String) throws -> Activity {
        try JSONDecoder().decode(Activity.self, from: Data(json.utf8))
    }

    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    private let when = Date(timeIntervalSince1970: 1_800_000_000)

    private func patch(
        type: String = "meeting",
        subject: String = "Visit",
        description: String = "",
        imageUrl: String? = nil,
        customFields: [String: Any] = [:],
        assignment: [String: Any] = [:],
        canChangeAssignee: Bool = false
    ) -> [String: Any]? {
        ActivityEditBody.patch(
            type: type, subject: subject, description: description, imageUrl: imageUrl,
            completedAt: when, customFields: customFields, assignment: assignment,
            canChangeAssignee: canChangeAssignee
        )
    }

    // MARK: - edit-entry routing

    func testTheEditEntryOpensTheRowWithThatId() throws {
        let list = [try activity(#"{"id":"a1"}"#), try activity(#"{"id":"a2","subject":"Second"}"#)]
        XCTAssertEqual(ActivityEditRouting.target(id: "a2", in: list)?.subject, "Second")
        XCTAssertEqual(ActivityEditRouting.target(id: "a1", in: list)?.id, "a1")
    }

    func testTheEditEntryOpensTheFreshestCopyAndNothingForAVanishedRow() throws {
        let fresh = try activity(#"{"id":"a1","subject":"Fresh"}"#)
        XCTAssertEqual(ActivityEditRouting.target(id: "a1", in: [fresh])?.subject, "Fresh")
        XCTAssertNil(ActivityEditRouting.target(id: "gone", in: [fresh]))
        XCTAssertNil(ActivityEditRouting.target(id: "a1", in: []))
    }

    func testASavedRowReplacesItselfInPlaceAndKeepsTheOrder() throws {
        let list = [
            try activity(#"{"id":"a1","subject":"One"}"#),
            try activity(#"{"id":"a2","subject":"Two"}"#),
            try activity(#"{"id":"a3","subject":"Three"}"#),
        ]
        let saved = try activity(#"{"id":"a2","subject":"Two (edited)"}"#)
        let out = ActivityEditRouting.replacing(saved, in: list)
        XCTAssertEqual(out.map { $0.id }, ["a1", "a2", "a3"])
        XCTAssertEqual(out.map { $0.subject }, ["One", "Two (edited)", "Three"])
    }

    func testASavedRowThatIsNotInTheListLeavesItUnchanged() throws {
        let list = [try activity(#"{"id":"a1"}"#)]
        let stranger = try activity(#"{"id":"zzz"}"#)
        XCTAssertEqual(ActivityEditRouting.replacing(stranger, in: list).map { $0.id }, ["a1"])
    }

    // MARK: - what the edit sheet starts from

    func testSparkEditStartsFromTheRowsOwnRemarksAndDate() throws {
        let row = try activity(#"{"id":"a1","body":"Discussed pricing","due_at":"2026-12-01T10:00:00Z"}"#)
        XCTAssertEqual(ActivityEditRouting.initialDescription(for: row, spark: true), "Discussed pricing")
        let date = try XCTUnwrap(ActivityEditRouting.initialWhen(for: row, spark: true))
        XCTAssertEqual(date, SparkJourney.parseISO("2026-12-01T10:00:00Z"))
    }

    func testACompletedRowsOwnCompletionDateWinsOverItsDueDate() throws {
        let row = try activity(#"{"id":"a1","due_at":"2026-12-01T10:00:00Z","completed_at":"2026-12-03T09:00:00Z"}"#)
        XCTAssertEqual(ActivityEditRouting.initialWhen(for: row, spark: true), SparkJourney.parseISO("2026-12-03T09:00:00Z"))
    }

    func testOtherTenantsKeepTheOriginalBlankStart() throws {
        let row = try activity(#"{"id":"a1","body":"Discussed pricing","due_at":"2026-12-01T10:00:00Z"}"#)
        XCTAssertEqual(ActivityEditRouting.initialDescription(for: row, spark: false), "")
        XCTAssertNil(ActivityEditRouting.initialWhen(for: row, spark: false))
    }

    func testTheEditSheetOpensOnTheRowsTypeOrMeeting() throws {
        XCTAssertEqual(ActivityEditRouting.initialType(for: try activity(#"{"id":"a1","type":"call"}"#)), "call")
        XCTAssertEqual(ActivityEditRouting.initialType(for: try activity(#"{"id":"a1"}"#)), "meeting")
    }

    // MARK: - generic PATCH body

    func testBlankSubjectIsNotSaved() {
        XCTAssertNil(patch(subject: "   "))
    }

    func testNonTaskIsStampedCompletedAtTheChosenTime() throws {
        let body = try XCTUnwrap(patch(type: "call", subject: " Call Ravi "))
        XCTAssertEqual(body["type"] as? String, "call")
        XCTAssertEqual(body["subject"] as? String, "Call Ravi")
        XCTAssertEqual(body["completed_at"] as? String, iso(when))
        XCTAssertEqual(body["status"] as? String, "completed")
        XCTAssertNil(body["due_at"])
    }

    func testTaskKeepsItsDueDateAndStaysOpen() throws {
        let body = try XCTUnwrap(patch(type: "task"))
        XCTAssertEqual(body["due_at"] as? String, iso(when))
        XCTAssertNil(body["completed_at"])
        XCTAssertNil(body["status"])
    }

    func testBlankRemarksClearTheDescriptionAndTypedOnesAreTrimmed() throws {
        XCTAssertTrue(try XCTUnwrap(patch(description: "  "))["description"] is NSNull)
        XCTAssertEqual(try XCTUnwrap(patch(description: " notes "))["description"] as? String, "notes")
    }

    func testImageAndCustomFieldsAreOnlySentWhenPresent() throws {
        let bare = try XCTUnwrap(patch())
        XCTAssertNil(bare["image_url"])
        XCTAssertNil(bare["custom_fields"])
        let full = try XCTUnwrap(patch(imageUrl: "https://x/y.jpg", customFields: ["visit_kind": "first"]))
        XCTAssertEqual(full["image_url"] as? String, "https://x/y.jpg")
        XCTAssertEqual((full["custom_fields"] as? [String: Any])?["visit_kind"] as? String, "first")
    }

    func testOnlyAdminsAndManagersSendAChangedAssignee() throws {
        let change: [String: Any] = ["assigned_to": "u-2"]
        XCTAssertEqual(try XCTUnwrap(patch(assignment: change, canChangeAssignee: true))["assigned_to"] as? String, "u-2")
        XCTAssertNil(try XCTUnwrap(patch(assignment: change, canChangeAssignee: false))["assigned_to"])
        // An untouched picker sends nothing, whoever is editing.
        XCTAssertNil(try XCTUnwrap(patch(assignment: [:], canChangeAssignee: true))["assigned_to"])
    }

    // MARK: - Spark PATCH

    private func result(subject: String = "Visit", assignees: [String], serial: String = "") -> ActivityComposeResult {
        ActivityComposeResult(
            type: "meeting", subject: subject, description: "", imageUrl: nil, when: when, leadId: nil,
            customFields: [:],
            extras: SparkActivityExtras(assigneeIds: assignees, productIds: [], formSerial: serial)
        )
    }

    func testSparkEditNeverFlipsAnOpenActivityToCompleted() throws {
        let open = try activity(#"{"id":"a1","status":"open","assigned_to":"u-1"}"#)
        let parts = ActivityEditBody.sparkPatch(existing: open, result: result(assignees: ["u-1"]), canChangeAssignees: true)
        XCTAssertEqual(parts.body["due_at"] as? String, iso(when))
        XCTAssertNil(parts.body["completed_at"])
        XCTAssertNil(parts.body["status"])
    }

    func testSomeoneWhoMayNotChangeAssigneesKeepsTheExistingOnes() throws {
        let row = try activity(#"{"id":"a1","assigned_to":"u-1"}"#)
        let blocked = ActivityEditBody.sparkPatch(existing: row, result: result(assignees: ["u-9"]), canChangeAssignees: false)
        XCTAssertEqual(blocked.extras.assigneeIds, ["u-1"])
        XCTAssertEqual(blocked.previous.assigneeIds, ["u-1"])
        let allowed = ActivityEditBody.sparkPatch(existing: row, result: result(assignees: ["u-9"]), canChangeAssignees: true)
        XCTAssertEqual(allowed.extras.assigneeIds, ["u-9"])
    }
}
