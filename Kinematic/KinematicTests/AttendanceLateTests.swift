//
//  AttendanceLateTests.swift
//  KinematicTests
//
//  "Late by N min" for clients that track it. The API adds `late` to a record only for a client that configured shift
//  rules; for every other client the key is absent, so nothing late is ever shown.
//

import XCTest
@testable import Kinematic

@MainActor
final class AttendanceLateTests: XCTestCase {

    private func decode(_ json: String) throws -> AttendanceRecord {
        try JSONDecoder().decode(AttendanceRecord.self, from: Data(json.utf8))
    }

    private func record(late: AttendanceLateInfo?, checkin: String? = "2026-10-12T04:30:00Z") -> AttendanceRecord {
        AttendanceRecord(id: "a", date: "2026-10-12", status: "checked_in", checkinAt: checkin, checkoutAt: nil,
                         totalHours: nil, checkinSelfieUrl: nil, checkoutSelfieUrl: nil, late: late)
    }

    // MARK: - the label

    func testALateRecordReadsLateByMinutes() {
        XCTAssertEqual(AttendanceLate.label(AttendanceLateInfo(isLate: true, minutesLate: 45)), "Late by 45 min")
        XCTAssertEqual(AttendanceLate.label(AttendanceLateInfo(isLate: true, minutesLate: 1)), "Late by 1 min")
    }

    func testLateWithNoMinutesReadsJustLate() {
        XCTAssertEqual(AttendanceLate.label(AttendanceLateInfo(isLate: true, minutesLate: nil)), "Late")
        XCTAssertEqual(AttendanceLate.label(AttendanceLateInfo(isLate: true, minutesLate: 0)), "Late")
    }

    func testNothingIsShownForARecordThatIsOnTimeOrHasNoLateBlock() {
        XCTAssertNil(AttendanceLate.label(nil))
        XCTAssertNil(AttendanceLate.label(AttendanceLateInfo(isLate: false, minutesLate: 0)))
        XCTAssertNil(AttendanceLate.label(AttendanceLateInfo(isLate: false, minutesLate: 12)))
    }

    // MARK: - reading it from the API

    func testTheLateBlockIsReadFromTheRecord() throws {
        let r = try decode(#"{"id":"a1","date":"2026-10-12","checkin_at":"2026-10-12T04:30:00Z","late":{"is_late":true,"minutes_late":45}}"#)
        XCTAssertEqual(r.late, AttendanceLateInfo(isLate: true, minutesLate: 45))
        XCTAssertEqual(AttendanceLate.label(r.late), "Late by 45 min")
    }

    func testAClientWithoutShiftRulesHasNoLateKeyAndNothingIsShown() throws {
        let r = try decode(#"{"id":"a1","date":"2026-10-12","checkin_at":"2026-10-12T04:30:00Z"}"#)
        XCTAssertNil(r.late)
        XCTAssertNil(AttendanceLate.label(r.late))
    }

    func testAnOddLateBlockNeverFailsTheRecord() throws {
        let junk = try decode(#"{"id":"a1","date":"2026-10-12","late":"yes"}"#)
        XCTAssertNil(junk.late)
        let partial = try decode(#"{"id":"a1","date":"2026-10-12","late":{"is_late":true}}"#)
        XCTAssertEqual(partial.late, AttendanceLateInfo(isLate: true, minutesLate: nil))
        let minutesOnly = try decode(#"{"id":"a1","date":"2026-10-12","late":{"minutes_late":30.0}}"#)
        XCTAssertEqual(minutesOnly.late?.isLate, false)
        XCTAssertEqual(minutesOnly.late?.minutesLate, 30)
        let notLate = try decode(#"{"id":"a1","date":"2026-10-12","late":{"is_late":false,"minutes_late":0}}"#)
        XCTAssertEqual(notLate.late, AttendanceLateInfo(isLate: false, minutesLate: 0))
    }

    func testTheLateBlockSurvivesTheCachedHomeSaveAndLoad() throws {
        let r = record(late: AttendanceLateInfo(isLate: true, minutesLate: 45))
        let back = try JSONDecoder().decode(AttendanceRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.late, AttendanceLateInfo(isLate: true, minutesLate: 45))
        let plain = record(late: nil)
        let backPlain = try JSONDecoder().decode(AttendanceRecord.self, from: JSONEncoder().encode(plain))
        XCTAssertNil(backPlain.late)
    }

    // MARK: - the tally

    func testTheLateTallyShowsOnlyWhenSomeRecordReportsLateInfo() {
        let onTime = record(late: AttendanceLateInfo(isLate: false, minutesLate: 0))
        let late = record(late: AttendanceLateInfo(isLate: true, minutesLate: 20))
        let plain = record(late: nil)

        // a client with shift rules: even an all-on-time history reports late info
        XCTAssertTrue(AttendanceLate.showsLateInfo(history: [onTime], today: nil))
        XCTAssertTrue(AttendanceLate.showsLateInfo(history: [], today: late))
        // a client without: nothing carries the block
        XCTAssertFalse(AttendanceLate.showsLateInfo(history: [plain, plain], today: nil))
        XCTAssertFalse(AttendanceLate.showsLateInfo(history: [], today: nil))
        XCTAssertFalse(AttendanceLate.showsLateInfo(history: [], today: plain))
    }

    func testOnlyRecordsWithACheckInAndALateFlagAreCounted() {
        let late = record(late: AttendanceLateInfo(isLate: true, minutesLate: 20))
        let late2 = record(late: AttendanceLateInfo(isLate: true, minutesLate: 5))
        let onTime = record(late: AttendanceLateInfo(isLate: false, minutesLate: 0))
        let plain = record(late: nil)
        let noCheckin = record(late: AttendanceLateInfo(isLate: true, minutesLate: 9), checkin: nil)
        XCTAssertEqual(AttendanceLate.lateCount([late, late2, onTime, plain, noCheckin]), 2)
        XCTAssertEqual(AttendanceLate.lateCount([]), 0)
    }
}
