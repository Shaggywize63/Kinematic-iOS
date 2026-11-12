//
//  ActivityLogPlanTests.swift
//  KinematicTests
//
//  Logging an activity with an Activity (done) date and / or a Scheduled (due) date: which activities a save
//  creates, what each payload carries, the success text and the date validations.
//

import XCTest
import Foundation
@testable import Kinematic

final class ActivityLogPlanTests: XCTestCase {

    private let done = Date(timeIntervalSince1970: 1_800_000_000)
    private let due = Date(timeIntervalSince1970: 1_800_000_000 + 7 * 86_400)
    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    // MARK: - which activities

    func testOnlyAnActivityDateCreatesOneCompletedActivity() {
        let entries = ActivityLogPlan.entries(activityDate: done, scheduledDate: nil)
        XCTAssertEqual(entries, [ActivityLogEntry(kind: .completed, date: done)])
        XCTAssertFalse(ActivityLogPlan.createsBoth(activityDate: done, scheduledDate: nil))
        XCTAssertNil(ActivityLogPlan.successMessage(activityDate: done, scheduledDate: nil))
    }

    func testOnlyAScheduledDateCreatesOnePlannedActivity() {
        let entries = ActivityLogPlan.entries(activityDate: nil, scheduledDate: due)
        XCTAssertEqual(entries, [ActivityLogEntry(kind: .planned, date: due)])
        XCTAssertNil(ActivityLogPlan.successMessage(activityDate: nil, scheduledDate: due))
    }

    func testNeitherDateCreatesNothingFromThePlan() {
        XCTAssertTrue(ActivityLogPlan.entries(activityDate: nil, scheduledDate: nil).isEmpty)
        XCTAssertNil(ActivityLogPlan.successMessage(activityDate: nil, scheduledDate: nil))
    }

    func testBothDatesCreateTwoActivitiesCompletedFirst() {
        let entries = ActivityLogPlan.entries(activityDate: done, scheduledDate: due)
        XCTAssertEqual(entries, [
            ActivityLogEntry(kind: .completed, date: done),
            ActivityLogEntry(kind: .planned, date: due),
        ])
        XCTAssertTrue(ActivityLogPlan.createsBoth(activityDate: done, scheduledDate: due))
        XCTAssertEqual(
            ActivityLogPlan.successMessage(activityDate: done, scheduledDate: due),
            "Activity logged + follow-up scheduled"
        )
    }

    // MARK: - payloads

    private func shared() -> [String: Any] {
        [
            "type": "call",
            "subject": "Call Ravi",
            "description": "Discussed pricing",
            "lead_id": "L1",
            "image_url": "https://x/y.jpg",
            "custom_fields": ["visit_kind": "first"],
            "assignee_ids": ["u1", "u2"],
            // Stale keys the builder must replace.
            "completed_at": "2020-01-01T00:00:00Z",
            "due_at": "2020-01-02T00:00:00Z",
            "status": "weird",
            "outcome": "Quote sent",
        ]
    }

    func testTheCompletedPayloadHasCompletedAtAndNoDueAt() {
        let body = ActivityLogPlan.body(for: ActivityLogEntry(kind: .completed, date: done), shared: shared())
        XCTAssertEqual(body["status"] as? String, "completed")
        XCTAssertEqual(body["completed_at"] as? String, iso(done))
        XCTAssertNil(body["due_at"])
        // It carries the outcome and the photo.
        XCTAssertEqual(body["outcome"] as? String, "Quote sent")
        XCTAssertEqual(body["image_url"] as? String, "https://x/y.jpg")
    }

    func testThePlannedPayloadHasDueAtAndNoCompletedAtOrOutcome() {
        let body = ActivityLogPlan.body(for: ActivityLogEntry(kind: .planned, date: due), shared: shared())
        XCTAssertEqual(body["status"] as? String, "open")
        XCTAssertEqual(body["due_at"] as? String, iso(due))
        XCTAssertNil(body["completed_at"])
        XCTAssertNil(body["outcome"])
        XCTAssertNil(body["image_url"])
    }

    func testBothPayloadsShareTheCommonFields() {
        for kind in [ActivityLogEntry.Kind.completed, .planned] {
            let body = ActivityLogPlan.body(for: ActivityLogEntry(kind: kind, date: done), shared: shared())
            XCTAssertEqual(body["type"] as? String, "call")
            XCTAssertEqual(body["subject"] as? String, "Call Ravi")
            XCTAssertEqual(body["description"] as? String, "Discussed pricing")
            XCTAssertEqual(body["lead_id"] as? String, "L1")
            XCTAssertEqual((body["custom_fields"] as? [String: Any])?["visit_kind"] as? String, "first")
            XCTAssertEqual(body["assignee_ids"] as? [String], ["u1", "u2"])
        }
    }

    func testTheSparkExtrasKeepAssigneesButTheFollowUpHasNoOutcomeOrSerial() {
        let extras = SparkActivityExtras(
            assigneeIds: ["u1"], productIds: ["p1"], formSerial: "SRPR2627-12", outcome: "Quote sent"
        )
        XCTAssertEqual(ActivityLogPlan.extras(extras, for: .completed), extras)
        let planned = ActivityLogPlan.extras(extras, for: .planned)
        XCTAssertEqual(planned.assigneeIds, ["u1"])
        XCTAssertEqual(planned.productIds, ["p1"])
        XCTAssertEqual(planned.outcome, "")
        XCTAssertEqual(planned.formSerial, "")
        // On the wire the planned activity then has no outcome key at all.
        var body: [String: Any] = [:]
        planned.apply(to: &body)
        XCTAssertNil(body["outcome"])
        XCTAssertEqual(body["assignee_ids"] as? [String], ["u1"])
    }

    // MARK: - validation

    func testTheActivityDateCannotBeInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(ActivityLogPlan.activityDateError(nil, now: now))
        XCTAssertNil(ActivityLogPlan.activityDateError(now.addingTimeInterval(-86_400), now: now))
        XCTAssertNil(ActivityLogPlan.activityDateError(now, now: now))
        XCTAssertEqual(
            ActivityLogPlan.activityDateError(now.addingTimeInterval(3_600), now: now),
            "Activity date can't be in the future."
        )
    }

    func testTheScheduledDateMustBeAhead() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(ActivityLogPlan.scheduledDateError(nil, now: now))
        XCTAssertNil(ActivityLogPlan.scheduledDateError(now.addingTimeInterval(3_600), now: now))
        XCTAssertNotNil(ActivityLogPlan.scheduledDateError(now.addingTimeInterval(-3_600), now: now))
    }

    func testSettingOneDateNeverClearsTheOther() {
        // Both dates survive together: the plan has no rule that drops either.
        let entries = ActivityLogPlan.entries(activityDate: done, scheduledDate: due)
        XCTAssertEqual(entries.map { $0.date }, [done, due])
    }
}
