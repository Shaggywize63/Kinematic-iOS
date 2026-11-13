//
//  MyTasksLogicTests.swift
//  KinematicTests
//
//  The pure logic behind the "My Tasks" screen: how a task's due_at + is_overdue
//  place it in one of the four sections (Overdue / Today / Upcoming / No date),
//  the soonest-due-first sort within a section, the "Assigned by …" display rule,
//  and the /crm/my-tasks query-string builder. No network, no SwiftUI — fixed
//  clock + fixtures so the grouping is deterministic.
//

import XCTest
import Foundation
@testable import Kinematic

final class MyTasksLogicTests: XCTestCase {

    // A fixed "now": 2026-06-15T12:00:00Z. Group with a UTC calendar so the
    // day boundaries don't drift with the machine's timezone.
    private let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // MARK: Fixture builder

    private func task(_ json: String) throws -> MyTask {
        try JSONDecoder().decode(MyTask.self, from: Data(json.utf8))
    }

    /// Minimal task: id + optional due_at + is_overdue.
    private func task(id: String, due: String?, overdue: Bool = false,
                      created: String? = nil) throws -> MyTask {
        var obj: [String: Any] = ["id": id, "is_overdue": overdue]
        if let due { obj["due_at"] = due }
        if let created { obj["created_at"] = created }
        let data = try JSONSerialization.data(withJSONObject: obj)
        return try JSONDecoder().decode(MyTask.self, from: data)
    }

    // MARK: - Decoding (lenient, snake_case)

    func testDecodesFullRow() throws {
        let t = try task(#"""
        {"id":"t1","type":"task","subject":"Call Acme","body":"Follow up","status":"open",
         "due_at":"2026-06-16T05:00:00Z","completed_at":null,"activity_date":"2026-06-15",
         "created_at":"2026-06-10T00:00:00Z","lead_id":"l1","lead_name":"Acme Traders",
         "lead_phone":"9431188608","contact_id":"c1","contact_name":"Ravi","account_id":"a1",
         "account_name":"Acme Pvt Ltd","company_id":"co1","company_name":"Acme Group",
         "deal_id":"d1","deal_name":"Acme Deal","owner_id":"u1","owner_name":"Rep One",
         "assigned_to":"u1","assigned_to_name":"Rep One","assigned_by":"u9",
         "assigned_by_name":"Manager Meera","is_overdue":false}
        """#)
        XCTAssertEqual(t.id, "t1")
        XCTAssertEqual(t.subject, "Call Acme")
        XCTAssertEqual(t.dueAt, "2026-06-16T05:00:00Z")
        XCTAssertEqual(t.leadName, "Acme Traders")
        XCTAssertEqual(t.assignedByName, "Manager Meera")
        XCTAssertFalse(t.isOverdue)
    }

    func testDecodesWithEveryNullableFieldMissing() throws {
        // Only id + is_overdue present — everything else nil, nothing throws.
        let t = try task(#"{"id":"t2","is_overdue":true}"#)
        XCTAssertEqual(t.id, "t2")
        XCTAssertTrue(t.isOverdue)
        XCTAssertNil(t.subject)
        XCTAssertNil(t.dueAt)
        XCTAssertNil(t.assignedByName)
    }

    func testMissingIsOverdueDefaultsToFalse() throws {
        let t = try task(#"{"id":"t3"}"#)
        XCTAssertFalse(t.isOverdue)
    }

    // MARK: - Display helpers

    func testDisplayTitlePrefersSubjectThenTypeThenTask() throws {
        XCTAssertEqual(try task(#"{"id":"1","subject":"Email client","is_overdue":false}"#).displayTitle, "Email client")
        XCTAssertEqual(try task(#"{"id":"1","type":"follow_up","is_overdue":false}"#).displayTitle, "Follow Up")
        XCTAssertEqual(try task(#"{"id":"1","is_overdue":false}"#).displayTitle, "Task")
        // Blank subject falls through to type.
        XCTAssertEqual(try task(#"{"id":"1","subject":"   ","type":"call","is_overdue":false}"#).displayTitle, "Call")
    }

    func testLinkedNamePrefersLeadThenAccountThenContactThenDeal() throws {
        XCTAssertEqual(try task(#"{"id":"1","lead_name":"Lead A","account_name":"Acct A","is_overdue":false}"#).linkedName, "Lead A")
        XCTAssertEqual(try task(#"{"id":"1","account_name":"Acct A","contact_name":"Con A","is_overdue":false}"#).linkedName, "Acct A")
        XCTAssertEqual(try task(#"{"id":"1","deal_name":"Deal A","is_overdue":false}"#).linkedName, "Deal A")
        XCTAssertNil(try task(#"{"id":"1","is_overdue":false}"#).linkedName)
    }

    func testEffectiveStatusFallsBackToCompletedAtThenOpen() throws {
        XCTAssertEqual(try task(#"{"id":"1","status":"in_progress","is_overdue":false}"#).effectiveStatus, "in_progress")
        XCTAssertEqual(try task(#"{"id":"1","completed_at":"2026-06-10T00:00:00Z","is_overdue":false}"#).effectiveStatus, "completed")
        XCTAssertEqual(try task(#"{"id":"1","is_overdue":false}"#).effectiveStatus, "open")
    }

    // MARK: - Section assignment

    func testNoDueDateIsNoDate() throws {
        let t = try task(id: "1", due: nil)
        XCTAssertEqual(MyTasksLogic.section(for: t, now: now, calendar: utc), .noDate)
    }

    func testEmptyDueStringIsNoDate() throws {
        let t = try task(#"{"id":"1","due_at":"","is_overdue":false}"#)
        XCTAssertEqual(MyTasksLogic.section(for: t, now: now, calendar: utc), .noDate)
    }

    func testIsOverdueFlagWinsEvenWithAFutureDate() throws {
        // Server says overdue; trust it over the date position.
        let t = try task(id: "1", due: "2026-06-20T05:00:00Z", overdue: true)
        XCTAssertEqual(MyTasksLogic.section(for: t, now: now, calendar: utc), .overdue)
    }

    func testPastDueDateIsOverdueEvenWithoutTheFlag() throws {
        let t = try task(id: "1", due: "2026-06-14T05:00:00Z", overdue: false)
        XCTAssertEqual(MyTasksLogic.section(for: t, now: now, calendar: utc), .overdue)
    }

    func testDueTodayIsToday() throws {
        // Same UTC day as `now`, both earlier and later in the day.
        XCTAssertEqual(MyTasksLogic.section(for: try task(id: "1", due: "2026-06-15T23:30:00Z"), now: now, calendar: utc), .today)
        XCTAssertEqual(MyTasksLogic.section(for: try task(id: "2", due: "2026-06-15T00:30:00Z"), now: now, calendar: utc), .today)
    }

    func testDueTomorrowIsUpcoming() throws {
        let t = try task(id: "1", due: "2026-06-16T00:30:00Z")
        XCTAssertEqual(MyTasksLogic.section(for: t, now: now, calendar: utc), .upcoming)
    }

    func testDueFarFutureIsUpcoming() throws {
        let t = try task(id: "1", due: "2026-12-01T05:00:00Z")
        XCTAssertEqual(MyTasksLogic.section(for: t, now: now, calendar: utc), .upcoming)
    }

    // MARK: - Grouping + ordering

    func testGroupedReturnsSectionsInFixedOrderOmittingEmpty() throws {
        let tasks = [
            try task(id: "future", due: "2026-06-20T05:00:00Z"),
            try task(id: "past", due: "2026-06-10T05:00:00Z"),
            try task(id: "today", due: "2026-06-15T18:00:00Z"),
        ]
        let groups = MyTasksLogic.grouped(tasks, now: now, calendar: utc)
        XCTAssertEqual(groups.map(\.section), [.overdue, .today, .upcoming])
        // No "No date" section since none are dateless.
        XCTAssertFalse(groups.contains { $0.section == .noDate })
    }

    func testDatedSectionsSortSoonestDueFirst() throws {
        let tasks = [
            try task(id: "u_late", due: "2026-06-25T05:00:00Z"),
            try task(id: "u_soon", due: "2026-06-17T05:00:00Z"),
            try task(id: "u_mid", due: "2026-06-20T05:00:00Z"),
        ]
        let upcoming = MyTasksLogic.grouped(tasks, now: now, calendar: utc).first { $0.section == .upcoming }
        XCTAssertEqual(upcoming?.tasks.map(\.id), ["u_soon", "u_mid", "u_late"])
    }

    func testOverdueSortsMostOverdueFirst() throws {
        let tasks = [
            try task(id: "o_recent", due: "2026-06-14T05:00:00Z"),
            try task(id: "o_old", due: "2026-06-01T05:00:00Z"),
        ]
        let overdue = MyTasksLogic.grouped(tasks, now: now, calendar: utc).first { $0.section == .overdue }
        // Ascending by due date → the oldest (most overdue) sits at the top.
        XCTAssertEqual(overdue?.tasks.map(\.id), ["o_old", "o_recent"])
    }

    func testNoDateSectionSortsNewestCreatedFirst() throws {
        let tasks = [
            try task(id: "n_old", due: nil, created: "2026-06-01T00:00:00Z"),
            try task(id: "n_new", due: nil, created: "2026-06-10T00:00:00Z"),
        ]
        let noDate = MyTasksLogic.grouped(tasks, now: now, calendar: utc).first { $0.section == .noDate }
        XCTAssertEqual(noDate?.tasks.map(\.id), ["n_new", "n_old"])
    }

    func testGroupedEmptyInputIsEmpty() {
        XCTAssertTrue(MyTasksLogic.grouped([], now: now, calendar: utc).isEmpty)
    }

    func testEqualDueDatesBreakTieOnIdForStableOrder() throws {
        let tasks = [
            try task(id: "b", due: "2026-06-20T05:00:00Z"),
            try task(id: "a", due: "2026-06-20T05:00:00Z"),
        ]
        let upcoming = MyTasksLogic.grouped(tasks, now: now, calendar: utc).first { $0.section == .upcoming }
        XCTAssertEqual(upcoming?.tasks.map(\.id), ["a", "b"])
    }

    // MARK: - "Assigned by …" display rule

    func testAssignedByShownWhenNamePresent() throws {
        let t = try task(#"{"id":"1","assigned_by_name":"Manager Meera","is_overdue":false}"#)
        XCTAssertEqual(MyTasksLogic.assignedByDisplay(t), "Assigned by Manager Meera")
    }

    func testAssignedByNilWhenNameMissingOrBlank() throws {
        XCTAssertNil(MyTasksLogic.assignedByDisplay(try task(#"{"id":"1","is_overdue":false}"#)))
        XCTAssertNil(MyTasksLogic.assignedByDisplay(try task(#"{"id":"1","assigned_by_name":"   ","is_overdue":false}"#)))
    }

    // MARK: - Query params

    func testQueryParamsEmptyByDefault() {
        XCTAssertTrue(MyTasksLogic.queryParams().isEmpty)
    }

    func testQueryParamsDropsAllAndEmptyStatus() {
        XCTAssertNil(MyTasksLogic.queryParams(status: "all")["status"])
        XCTAssertNil(MyTasksLogic.queryParams(status: "All")["status"])
        XCTAssertNil(MyTasksLogic.queryParams(status: "  ")["status"])
        XCTAssertEqual(MyTasksLogic.queryParams(status: "open")["status"], "open")
        XCTAssertEqual(MyTasksLogic.queryParams(status: "in_progress")["status"], "in_progress")
    }

    func testQueryParamsOverdueOnlyWhenTrue() {
        XCTAssertNil(MyTasksLogic.queryParams(overdue: false)["overdue"])
        XCTAssertEqual(MyTasksLogic.queryParams(overdue: true)["overdue"], "true")
    }

    func testQueryParamsFromToAndPaging() {
        let q = MyTasksLogic.queryParams(status: "open", overdue: true,
                                         from: "2026-06-01", to: "2026-06-30",
                                         page: 2, limit: 50)
        XCTAssertEqual(q["status"], "open")
        XCTAssertEqual(q["overdue"], "true")
        XCTAssertEqual(q["from"], "2026-06-01")
        XCTAssertEqual(q["to"], "2026-06-30")
        XCTAssertEqual(q["page"], "2")
        XCTAssertEqual(q["limit"], "50")
    }

    func testQueryParamsDropsBlankFromTo() {
        let q = MyTasksLogic.queryParams(from: "   ", to: "")
        XCTAssertNil(q["from"])
        XCTAssertNil(q["to"])
    }

    // MARK: - Status filter mapping

    func testStatusFilterApiValues() {
        XCTAssertNil(MyTasksStatusFilter.all.apiValue)
        XCTAssertEqual(MyTasksStatusFilter.open.apiValue, "open")
        XCTAssertEqual(MyTasksStatusFilter.inProgress.apiValue, "in_progress")
        XCTAssertEqual(MyTasksStatusFilter.completed.apiValue, "completed")
    }

    func testStatusFilterTitles() {
        XCTAssertEqual(MyTasksStatusFilter.allCases.map(\.title), ["All", "Open", "In progress", "Completed"])
    }
}
