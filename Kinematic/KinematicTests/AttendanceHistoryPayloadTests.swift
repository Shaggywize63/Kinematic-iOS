//
//  AttendanceHistoryPayloadTests.swift
//  KinematicTests
//
//  GET /attendance/history must decode whichever shape the server sends — a flat
//  array, the nested `{ data, pagination }`, or the superset that also carries
//  `items` (what Android reads). The app used to accept only a flat array, so the
//  history screen was empty whenever the server sent an object.
//

import XCTest
@testable import Kinematic

@MainActor
final class AttendanceHistoryPayloadTests: XCTestCase {

    private let rowToday = """
    {"id":"a1","date":"2026-10-06","status":"checked_in","checkin_at":"2026-10-06T01:45:00Z","checkout_at":null,"total_hours":3.5}
    """
    private let rowYesterday = """
    {"id":"a0","date":"2026-10-05","status":"checked_out","checkin_at":"2026-10-05T03:00:00Z","checkout_at":"2026-10-05T12:00:00Z","total_hours":9}
    """

    private func decode(_ json: String) throws -> AttendanceHistoryPayload {
        try JSONDecoder().decode(AttendanceHistoryPayload.self, from: Data(json.utf8))
    }

    func testDecodesAFlatArray() throws {
        let payload = try decode("[\(rowToday),\(rowYesterday)]")
        XCTAssertEqual(payload.records.count, 2)
        XCTAssertEqual(payload.records.first?.date, "2026-10-06")
    }

    func testDecodesTheNestedPaginatedShape() throws {
        let payload = try decode("""
        {"data":[\(rowToday),\(rowYesterday)],
         "pagination":{"page":1,"limit":30,"total":2,"totalPages":1}}
        """)
        XCTAssertEqual(payload.records.map(\.date), ["2026-10-06", "2026-10-05"])
    }

    func testDecodesTheItemsShapeAndPrefersItemsOverData() throws {
        let payload = try decode("""
        {"items":[\(rowToday)],"total":1,"page":1,"limit":30,"totalPages":1,
         "data":[\(rowToday),\(rowYesterday)],
         "pagination":{"page":1,"limit":30,"total":1,"totalPages":1}}
        """)
        XCTAssertEqual(payload.records.count, 1)
        XCTAssertEqual(payload.records.first?.id, "a1")
    }

    func testAnObjectWithNoRecordsIsAnEmptyHistoryNotAnError() throws {
        XCTAssertEqual(try decode(#"{"items":[],"total":0}"#).records.count, 0)
        XCTAssertEqual(try decode(#"{"pagination":{"total":0}}"#).records.count, 0)
        XCTAssertEqual(try decode("[]").records.count, 0)
    }

    func testReadsTheRecordFieldsTheHistoryScreenShows() throws {
        let record = try XCTUnwrap(decode("[\(rowToday)]").records.first)
        XCTAssertEqual(record.checkinAt, "2026-10-06T01:45:00Z")
        XCTAssertNil(record.checkoutAt)
        XCTAssertEqual(record.totalHours, 3.5)
        XCTAssertEqual(record.status, "checked_in")
    }

    /// The real response: the history sits inside the usual `{ success, data }` envelope.
    func testDecodesInsideTheApiResponseEnvelope() throws {
        let json = """
        {"success":true,"data":{"items":[\(rowToday),\(rowYesterday)],"total":2,"page":1,"limit":30,"totalPages":1,
                                "data":[\(rowToday),\(rowYesterday)],"pagination":{"page":1,"limit":30,"total":2,"totalPages":1}}}
        """
        let res = try JSONDecoder().decode(ApiResponse<AttendanceHistoryPayload>.self, from: Data(json.utf8))
        XCTAssertTrue(res.success)
        XCTAssertEqual(res.data?.records.count, 2)
    }
}
