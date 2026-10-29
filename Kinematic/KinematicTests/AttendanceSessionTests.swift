import XCTest
@testable import Kinematic

/// The multiple-check-in/out-per-day state rules on AttendanceRecord: the latest session's
/// status decides isClockedIn / hasCheckedOut, with the flat checkin/checkout pair as the
/// fallback when there is no session list (legacy / optimistic records).
final class AttendanceSessionTests: XCTestCase {

    private func session(_ seq: Int, _ status: String) -> AttendanceSession {
        AttendanceSession(
            id: "s\(seq)", seq: seq, status: status,
            checkinAt: "2026-10-29T04:00:00Z", checkinLatitude: nil, checkinLongitude: nil, checkinSelfieUrl: nil,
            checkoutAt: status == "closed" ? "2026-10-29T06:00:00Z" : nil,
            checkoutLatitude: nil, checkoutLongitude: nil, checkoutSelfieUrl: nil,
            workingMinutes: status == "closed" ? 120 : nil, transportMode: nil)
    }

    private func record(sessions: [AttendanceSession]?, checkinAt: String?, checkoutAt: String?) -> AttendanceRecord {
        AttendanceRecord(
            id: "a", date: "29--10-2026", status: nil,
            checkinAt: checkinAt, checkoutAt: checkoutAt,
            totalHours: nil, checkinSelfieUrl: nil, checkoutSelfieUrl: nil,
            sessions: sessions)
    }

    // ---- sessions present: the latest (highest seq) wins ----

    func testOpenLatestSessionIsClockedIn() {
        let r = record(sessions: [session(1, "closed"), session(2, "open")], checkinAt: "x", checkoutAt: "y")
        XCTAssertTrue(r.isClockedIn)
        XCTAssertFalse(r.hasCheckedOut)
        XCTAssertTrue(r.isIn)   // isIn now delegates to isClockedIn
    }

    func testClosedLatestSessionIsCheckedOutNotLocked() {
        let r = record(sessions: [session(1, "closed"), session(2, "closed")], checkinAt: "x", checkoutAt: "y")
        XCTAssertFalse(r.isClockedIn)
        XCTAssertTrue(r.hasCheckedOut)
    }

    func testSeqOrderNotArrayOrderDecidesLatest() {
        let r = record(sessions: [session(2, "open"), session(1, "closed")], checkinAt: nil, checkoutAt: nil)
        XCTAssertTrue(r.isClockedIn)
    }

    // ---- no sessions: fall back to the flat pair (legacy) ----

    func testLegacyClockedIn() {
        let r = record(sessions: nil, checkinAt: "x", checkoutAt: nil)
        XCTAssertTrue(r.isClockedIn)
        XCTAssertFalse(r.hasCheckedOut)
    }

    func testLegacyCheckedOut() {
        let r = record(sessions: nil, checkinAt: "x", checkoutAt: "y")
        XCTAssertFalse(r.isClockedIn)
        XCTAssertTrue(r.hasCheckedOut)
    }

    func testLegacyNeverPunched() {
        let r = record(sessions: nil, checkinAt: nil, checkoutAt: nil)
        XCTAssertFalse(r.isClockedIn)
        XCTAssertFalse(r.hasCheckedOut)
    }

    func testLocalTimeFormatsOrDashes() {
        XCTAssertEqual(AttendanceSession.localTime(nil), "--")
        XCTAssertEqual(AttendanceSession.localTime(""), "--")
        XCTAssertEqual(AttendanceSession.localTime("not-a-date"), "--")
        // A real ISO instant parses to some "HH:mm" (device-local) — just assert the shape.
        let t = AttendanceSession.localTime("2026-10-29T04:30:00Z")
        XCTAssertEqual(t.count, 5)
        XCTAssertEqual(t[t.index(t.startIndex, offsetBy: 2)], ":")
    }
}
