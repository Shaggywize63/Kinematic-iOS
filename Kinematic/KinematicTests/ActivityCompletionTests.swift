//
//  ActivityCompletionTests.swift
//  KinematicTests
//
//  The rules behind the "Mark complete" / "Reopen" action on CRM activity cards: the exact PATCH body
//  (a reopen must send an explicit JSON null for `completed_at`, which the synthesized Codable encoder
//  would drop), which rows offer which action, and merging the server's PATCH response into the list
//  without losing the lead / contact / deal names the response doesn't carry.
//

import XCTest
import Foundation
@testable import Kinematic

@MainActor
final class ActivityCompletionTests: XCTestCase {

    /// 2026-10-08T04:12:00Z
    private let fixedNow = Date(timeIntervalSince1970: 1_791_432_720)

    private func activity(_ json: String) throws -> Activity {
        try JSONDecoder().decode(Activity.self, from: Data(json.utf8))
    }

    private func action(_ json: String) throws -> ActivityCompletion.Action? {
        let a = try activity(json)
        return ActivityCompletion.action(for: a)
    }

    // MARK: - request body

    func testCompleteBodyIsCompletedStatusPlusTimestamp() {
        let body = ActivityCompletion.body(completed: true, now: fixedNow)
        XCTAssertEqual(body.count, 2)
        XCTAssertEqual(body["status"] as? String, "completed")
        XCTAssertEqual(body["completed_at"] as? String, "2026-10-08T04:12:00.000Z")
        XCTAssertFalse(body["completed_at"] is NSNull)
    }

    func testReopenBodyIsOpenStatusPlusExplicitNull() {
        let body = ActivityCompletion.body(completed: false, now: fixedNow)
        XCTAssertEqual(body.count, 2)
        XCTAssertEqual(body["status"] as? String, "open")
        // The key must be present (not omitted) and be NSNull so it serialises as JSON null.
        XCTAssertTrue(body.keys.contains("completed_at"))
        XCTAssertTrue(body["completed_at"] is NSNull)
    }

    func testReopenIgnoresTheClock() {
        let a = ActivityCompletion.body(completed: false, now: fixedNow)
        let b = ActivityCompletion.body(completed: false, now: Date())
        XCTAssertEqual(a["status"] as? String, b["status"] as? String)
        XCTAssertTrue(a["completed_at"] is NSNull)
        XCTAssertTrue(b["completed_at"] is NSNull)
    }

    func testCompleteBodySerialisesToJSONWithTheTimestampString() throws {
        let body = ActivityCompletion.body(completed: true, now: fixedNow)
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(json, #"{"completed_at":"2026-10-08T04:12:00.000Z","status":"completed"}"#)
    }

    func testReopenBodySerialisesToJSONWithAnExplicitNull() throws {
        let body = ActivityCompletion.body(completed: false, now: fixedNow)
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""completed_at":null"#))
        XCTAssertEqual(json, #"{"completed_at":null,"status":"open"}"#)
    }

    func testReopenJSONRoundTripsWithNullNotMissing() throws {
        let body = ActivityCompletion.body(completed: false, now: fixedNow)
        let data = try JSONSerialization.data(withJSONObject: body)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(parsed.keys.contains("completed_at"))
        XCTAssertTrue(parsed["completed_at"] is NSNull)
        XCTAssertEqual(parsed["status"] as? String, "open")
    }

    func testTimestampIsUTCWithFractionalSeconds() {
        XCTAssertEqual(ActivityCompletion.isoTimestamp(fixedNow), "2026-10-08T04:12:00.000Z")
    }

    // MARK: - which action a row offers

    func testOpenActivityOffersMarkComplete() throws {
        XCTAssertEqual(try action(#"{"id":"a1","status":"open"}"#), ActivityCompletion.Action.markComplete)
    }

    func testActivityWithNoStatusAndNoStampOffersMarkComplete() throws {
        XCTAssertEqual(try action(#"{"id":"a1"}"#), ActivityCompletion.Action.markComplete)
    }

    func testInProgressAndPlannedOfferMarkComplete() throws {
        XCTAssertEqual(try action(#"{"id":"a1","status":"in_progress"}"#), ActivityCompletion.Action.markComplete)
        XCTAssertEqual(try action(#"{"id":"a1","status":"planned"}"#), ActivityCompletion.Action.markComplete)
    }

    func testCompletedAndDoneOfferReopen() throws {
        XCTAssertEqual(try action(#"{"id":"a1","status":"completed"}"#), ActivityCompletion.Action.reopen)
        XCTAssertEqual(try action(#"{"id":"a1","status":"done"}"#), ActivityCompletion.Action.reopen)
    }

    func testStatusMatchingIgnoresCaseAndSurroundingSpaces() throws {
        XCTAssertEqual(try action(#"{"id":"a1","status":" Completed "}"#), ActivityCompletion.Action.reopen)
        XCTAssertNil(try action(#"{"id":"a1","status":"CANCELLED"}"#))
    }

    func testCompletedAtStampAloneMeansCompleted() throws {
        // Older rows: no status, just the stamp. Also status "open" with a stamp is treated as completed.
        XCTAssertEqual(try action(#"{"id":"a1","completed_at":"2026-10-08T04:12:00.000Z"}"#), ActivityCompletion.Action.reopen)
        XCTAssertEqual(try action(#"{"id":"a1","status":"open","completed_at":"2026-10-08T04:12:00.000Z"}"#), ActivityCompletion.Action.reopen)
    }

    func testEmptyCompletedAtStampIsNotCompleted() throws {
        XCTAssertEqual(try action(#"{"id":"a1","status":"open","completed_at":""}"#), ActivityCompletion.Action.markComplete)
    }

    func testCancelledOffersNothingEvenWithAStamp() throws {
        XCTAssertNil(try action(#"{"id":"a1","status":"cancelled"}"#))
        XCTAssertNil(try action(#"{"id":"a1","status":"canceled"}"#))
        XCTAssertNil(try action(#"{"id":"a1","status":"cancelled","completed_at":"2026-10-08T04:12:00.000Z"}"#))
    }

    func testStatusOnlyOverloadUsedByMyDay() {
        XCTAssertEqual(ActivityCompletion.action(status: "open", completedAt: nil), ActivityCompletion.Action.markComplete)
        XCTAssertEqual(ActivityCompletion.action(status: nil, completedAt: nil), ActivityCompletion.Action.markComplete)
        XCTAssertEqual(ActivityCompletion.action(status: "done", completedAt: nil), ActivityCompletion.Action.reopen)
        XCTAssertNil(ActivityCompletion.action(status: "cancelled", completedAt: nil))
    }

    func testActionPresentation() {
        XCTAssertEqual(ActivityCompletion.Action.markComplete.title, "Mark complete")
        XCTAssertEqual(ActivityCompletion.Action.reopen.title, "Reopen")
        XCTAssertEqual(ActivityCompletion.Action.markComplete.systemImage, "checkmark.circle")
        XCTAssertTrue(ActivityCompletion.Action.markComplete.targetCompleted)
        XCTAssertFalse(ActivityCompletion.Action.reopen.targetCompleted)
    }

    // MARK: - merging the PATCH response into the list

    private let openRow = #"""
    {"id":"a1","type":"call","subject":"Call Acme","status":"open",
     "due_at":"2026-10-09T05:00:00Z","created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-01T00:00:00Z",
     "owner_name":"Rep One","lead_id":"l1","lead_name":"Acme Traders","lead_phone":"9431188608",
     "contact_name":"Ravi","deal_name":"Deal 1","directory_name":"Radha Traders","directory_phone":"9431188608"}
    """#

    func testCompleteResponseFlipsStateButKeepsTheLinkedNames() throws {
        let row = try activity(openRow)
        // The PATCH response is a bare row: no lead_name / contact_name / deal_name / directory fields.
        let response = try activity(#"{"id":"a1","status":"completed","completed_at":"2026-10-08T04:12:00.000Z","updated_at":"2026-10-08T04:12:00.000Z","owner_name":"Rep One"}"#)

        let merged = row.applyingCompletion(from: response)

        XCTAssertEqual(merged.status, "completed")
        XCTAssertEqual(merged.completedAt, "2026-10-08T04:12:00.000Z")
        XCTAssertEqual(merged.updatedAt, "2026-10-08T04:12:00.000Z")
        XCTAssertEqual(merged.effectiveStatus, "completed")
        XCTAssertEqual(ActivityCompletion.action(for: merged), ActivityCompletion.Action.reopen)
        // Everything the response did not carry survives.
        XCTAssertEqual(merged.leadName, "Acme Traders")
        XCTAssertEqual(merged.leadPhone, "9431188608")
        XCTAssertEqual(merged.contactName, "Ravi")
        XCTAssertEqual(merged.dealName, "Deal 1")
        XCTAssertEqual(merged.directoryName, "Radha Traders")
        XCTAssertEqual(merged.directoryPhone, "9431188608")
        XCTAssertEqual(merged.subject, "Call Acme")
        XCTAssertEqual(merged.dueAt, "2026-10-09T05:00:00Z")
        XCTAssertEqual(merged.createdAt, "2026-10-01T00:00:00Z")
        XCTAssertEqual(merged.leadId, "l1")
    }

    func testReopenResponseClearsTheCompletedStamp() throws {
        let completed = try activity(#"{"id":"a1","status":"completed","completed_at":"2026-10-08T04:12:00.000Z","lead_name":"Acme Traders"}"#)
        let response = try activity(#"{"id":"a1","status":"open","completed_at":null,"updated_at":"2026-10-08T05:00:00.000Z"}"#)

        let merged = completed.applyingCompletion(from: response)

        XCTAssertEqual(merged.status, "open")
        XCTAssertNil(merged.completedAt)
        XCTAssertEqual(merged.updatedAt, "2026-10-08T05:00:00.000Z")
        XCTAssertEqual(ActivityCompletion.action(for: merged), ActivityCompletion.Action.markComplete)
        XCTAssertEqual(merged.leadName, "Acme Traders")
    }

    func testMissingUpdatedAtInTheResponseKeepsTheOldOne() throws {
        let row = try activity(openRow)
        let response = try activity(#"{"id":"a1","status":"completed","completed_at":"2026-10-08T04:12:00.000Z"}"#)
        XCTAssertEqual(row.applyingCompletion(from: response).updatedAt, "2026-10-01T00:00:00Z")
    }

    func testApplyCompletionUpdatesOnlyTheMatchingRow() throws {
        let a = try activity(#"{"id":"a1","status":"open","lead_name":"Acme"}"#)
        let b = try activity(#"{"id":"b2","status":"open","lead_name":"Beta"}"#)
        var list = [a, b]

        list.applyCompletion(try activity(#"{"id":"b2","status":"completed","completed_at":"2026-10-08T04:12:00.000Z"}"#))

        XCTAssertEqual(list[0], a)
        XCTAssertEqual(list[1].status, "completed")
        XCTAssertEqual(list[1].leadName, "Beta")
    }

    func testApplyCompletionForARowThatLeftTheListIsANoOp() throws {
        let a = try activity(#"{"id":"a1","status":"open"}"#)
        var list = [a]

        list.applyCompletion(try activity(#"{"id":"gone","status":"completed","completed_at":"2026-10-08T04:12:00.000Z"}"#))

        XCTAssertEqual(list, [a])
    }
}
