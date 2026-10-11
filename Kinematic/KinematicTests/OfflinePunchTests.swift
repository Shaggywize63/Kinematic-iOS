//
//  OfflinePunchTests.swift
//  KinematicTests
//
//  Offline check-in / check-out for a client with `allow_offline_checkin`: the capture time the server is sent, the
//  attendance day (IST), when a punch is queued rather than failed, what a server answer means for a queued row, the
//  order (a check-out never goes before its check-in), the stand-in record Home shows while a punch waits, the notice,
//  and the queued row's fields (an old row still loads, a new one round-trips). Everything is pure.
//

import XCTest
@testable import Kinematic

@MainActor
final class OfflinePunchTests: XCTestCase {

    private let ist = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone(secondsFromGMT: 19_800) ?? TimeZone.current

    private func instant(_ iso: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso))
    }

    // MARK: - time

    func testCapturedAtIsUtcWithAZoneDesignatorAndWholeSeconds() throws {
        XCTAssertEqual(OfflinePunch.formatCapturedAt(try instant("2026-10-12T04:03:11Z")), "2026-10-12T04:03:11Z")
        // fractional seconds are dropped, never rounded up
        let withFraction = try instant("2026-10-12T04:03:11Z").addingTimeInterval(0.987)
        XCTAssertEqual(OfflinePunch.formatCapturedAt(withFraction), "2026-10-12T04:03:11Z")
    }

    func testCapturedAtReadsBackWithOrWithoutFractionalSeconds() throws {
        let at = try instant("2026-10-12T04:03:11Z")
        XCTAssertEqual(OfflinePunch.parseCapturedAt("2026-10-12T04:03:11Z"), at)
        XCTAssertEqual(OfflinePunch.parseCapturedAt("2026-10-12T04:03:11.000Z"), at)
        XCTAssertNil(OfflinePunch.parseCapturedAt("not a time"))
        XCTAssertNil(OfflinePunch.parseCapturedAt(""))
        XCTAssertNil(OfflinePunch.parseCapturedAt(nil))
    }

    func testTheStandInTimeIsInTheShapeTheAppParsesEverywhere() throws {
        let s = OfflinePunch.formatLocalIso(try instant("2026-10-12T04:03:11Z"))
        XCTAssertEqual(s, "2026-10-12T04:03:11.000Z")
        XCTAssertEqual(parseISO(s), try instant("2026-10-12T04:03:11Z"))
    }

    func testTheAttendanceDayIsTheIndiaDayEitherSideOfIstMidnight() throws {
        XCTAssertEqual(OfflinePunch.istDate(try instant("2026-10-11T18:29:59Z")), "2026-10-11")   // 23:59:59 IST
        XCTAssertEqual(OfflinePunch.istDate(try instant("2026-10-11T18:30:00Z")), "2026-10-12")   // 00:00:00 IST
        XCTAssertEqual(OfflinePunch.istDate(try instant("2026-10-12T04:03:11Z")), "2026-10-12")
        XCTAssertEqual(OfflinePunch.istDate(try instant("2026-12-31T20:00:00Z")), "2027-01-01")
    }

    func testTheDateQueryIsSentOnlyForAnotherDay() throws {
        let now = try instant("2026-10-12T05:00:00Z")   // 10:30 IST on the 12th
        XCTAssertNil(OfflinePunch.dateQuery(attendanceDate: "2026-10-12", now: now))
        XCTAssertEqual(OfflinePunch.dateQuery(attendanceDate: "2026-10-11", now: now), "2026-10-11")
        XCTAssertEqual(OfflinePunch.dateQuery(attendanceDate: " 2026-10-11 ", now: now), "2026-10-11")
        XCTAssertNil(OfflinePunch.dateQuery(attendanceDate: nil, now: now))
        XCTAssertNil(OfflinePunch.dateQuery(attendanceDate: "  ", now: now))
    }

    func testAPunchOlderThanTheServersLimitMinusAMarginIsTooOld() throws {
        let sent = try instant("2026-10-13T10:00:00Z")
        let limit: TimeInterval = 36 * 3600 - 5 * 60
        XCTAssertFalse(OfflinePunch.isTooOld(capturedAt: sent.addingTimeInterval(-(limit - 1)), now: sent))
        XCTAssertFalse(OfflinePunch.isTooOld(capturedAt: sent.addingTimeInterval(-limit), now: sent))
        XCTAssertTrue(OfflinePunch.isTooOld(capturedAt: sent.addingTimeInterval(-(limit + 1)), now: sent))
        XCTAssertFalse(OfflinePunch.isTooOld(capturedAt: sent, now: sent))
    }

    func testTheClockIsTwentyFourHourInTheGivenZone() throws {
        let at = try instant("2026-10-12T04:03:11Z")
        XCTAssertEqual(OfflinePunch.clock(at, zone: ist), "09:33")
        XCTAssertEqual(OfflinePunch.clock(at, zone: TimeZone(secondsFromGMT: 0) ?? TimeZone.current), "04:03")
        XCTAssertEqual(OfflinePunch.clock(try instant("2026-10-11T18:30:00Z"), zone: ist), "00:00")
    }

    // MARK: - what the rep is told

    func testTheQueuedMessageNamesTheCaptureTime() throws {
        let at = try instant("2026-10-12T03:42:00Z")   // 09:12 IST
        XCTAssertEqual(OfflinePunch.queuedMessage(kind: .checkIn, capturedAt: at, zone: ist), "Checked in 09:12 — will sync when online")
        XCTAssertEqual(OfflinePunch.queuedMessage(kind: .checkOut, capturedAt: at, zone: ist), "Checked out 09:12 — will sync when online")
    }

    func testTheKindsHaveTheirWordsAndTheKeyPrefixesTheQueueAlwaysUsed() {
        XCTAssertEqual(OfflinePunch.Kind.checkIn.rawValue, "checkin")
        XCTAssertEqual(OfflinePunch.Kind.checkOut.rawValue, "checkout")
        XCTAssertEqual(OfflinePunch.Kind.checkIn.noun, "Check-in")
        XCTAssertEqual(OfflinePunch.Kind.checkOut.noun, "Check-out")
        XCTAssertTrue(OfflinePunch.newKey(.checkIn).hasPrefix("att-ci-"))
        XCTAssertTrue(OfflinePunch.newKey(.checkOut).hasPrefix("att-co-"))
        XCTAssertNotEqual(OfflinePunch.newKey(.checkIn), OfflinePunch.newKey(.checkIn))
    }

    // MARK: - queue or fail?

    func testAPunchIsQueuedOnlyForAnOptedInClientAndAConnectivityFailure() {
        XCTAssertEqual(OfflinePunch.decide(allowOffline: true, retryable: true, hasPhoto: true, selfieRequired: true), .queue)
        XCTAssertEqual(OfflinePunch.decide(allowOffline: true, retryable: true, hasPhoto: false, selfieRequired: false), .queue)
        // not opted in: exactly as before, the real error
        XCTAssertEqual(OfflinePunch.decide(allowOffline: false, retryable: true, hasPhoto: true, selfieRequired: true), .fail)
        // a refusal is shown, never "saved"
        XCTAssertEqual(OfflinePunch.decide(allowOffline: true, retryable: false, hasPhoto: true, selfieRequired: true), .fail)
        // a selfie is demanded and there is none to keep: ask for one
        XCTAssertEqual(OfflinePunch.decide(allowOffline: true, retryable: true, hasPhoto: false, selfieRequired: true), .needSelfie)
    }

    // MARK: - what a server answer means for a queued row

    func testAnAlreadyRecordedConflictIsDoneButTheMiddlewaresOwnRefusalsAreNot() {
        XCTAssertTrue(OfflinePunch.isAlreadyRecorded(httpStatus: 409, message: "Already checked out for this shift"))
        XCTAssertTrue(OfflinePunch.isAlreadyRecorded(httpStatus: 409, message: nil))
        XCTAssertFalse(OfflinePunch.isAlreadyRecorded(httpStatus: 409, message: "Idempotency-Key reused with a different request body"))
        XCTAssertFalse(OfflinePunch.isAlreadyRecorded(httpStatus: 409, message: "Idempotency-Key belongs to a different user"))
        XCTAssertFalse(OfflinePunch.isAlreadyRecorded(httpStatus: 409, message: "Idempotency-Key too long"))
        XCTAssertFalse(OfflinePunch.isAlreadyRecorded(httpStatus: 400, message: "Already checked out"))
        XCTAssertFalse(OfflinePunch.isAlreadyRecorded(httpStatus: nil, message: "Already checked out"))
    }

    func testTheVerdictForAFailedSend() {
        // finished: the server has it
        XCTAssertEqual(OfflinePunch.verdict(failure: .rejected, httpStatus: 409, message: "Already checked out for this shift", attempt: 0), .done)
        // wait: an outage, throttling, a busy server, a sign-in that needs refreshing
        XCTAssertEqual(OfflinePunch.verdict(failure: .transient, httpStatus: nil, message: "offline", attempt: 0), .hold)
        XCTAssertEqual(OfflinePunch.verdict(failure: .transient, httpStatus: 503, message: "busy", attempt: 5), .hold)
        XCTAssertEqual(OfflinePunch.verdict(failure: .authRequired, httpStatus: 401, message: "expired", attempt: 0), .hold)
        // final no
        XCTAssertEqual(OfflinePunch.verdict(failure: .rejected, httpStatus: 400, message: "You are outside the allowed area", attempt: 0), .reject)
        XCTAssertEqual(OfflinePunch.verdict(failure: .rejected, httpStatus: 403, message: "no", attempt: 0), .reject)
        XCTAssertEqual(OfflinePunch.verdict(failure: .rejected, httpStatus: 200, message: "success false", attempt: 0), .reject)
        XCTAssertEqual(OfflinePunch.verdict(failure: .locationRequired, httpStatus: 400, message: "Turn on location", attempt: 0), .reject)
        // the idempotency middleware's refusal of a changed body is final too
        XCTAssertEqual(OfflinePunch.verdict(failure: .rejected, httpStatus: 409,
                                            message: "Idempotency-Key reused with a different request body", attempt: 0), .reject)
    }

    func testAReplyWithNoStatusAndNoOutageIsRetriedAFewTimesThenRefused() {
        XCTAssertEqual(OfflinePunch.verdict(failure: .rejected, httpStatus: nil, message: "unreadable", attempt: 0), .hold)
        XCTAssertEqual(OfflinePunch.verdict(failure: .rejected, httpStatus: 0, message: "unreadable", attempt: 2), .hold)
        XCTAssertEqual(OfflinePunch.verdict(failure: .rejected, httpStatus: nil, message: "unreadable", attempt: OfflinePunch.maxUnknownAttempts), .reject)
    }

    // MARK: - ordering

    func testACheckOutNeverGoesBeforeItsCheckIn() {
        XCTAssertEqual(OfflinePunch.gate(kind: .checkIn, precedingCheckin: nil), .send)
        XCTAssertEqual(OfflinePunch.gate(kind: .checkIn, precedingCheckin: .pending), .send)
        XCTAssertEqual(OfflinePunch.gate(kind: .checkOut, precedingCheckin: nil), .send)
        XCTAssertEqual(OfflinePunch.gate(kind: .checkOut, precedingCheckin: .synced), .send)
        XCTAssertEqual(OfflinePunch.gate(kind: .checkOut, precedingCheckin: .pending), .waitForCheckin)
        XCTAssertEqual(OfflinePunch.gate(kind: .checkOut, precedingCheckin: .rejected), .rejectNoCheckin)
    }

    // MARK: - the stand-in record

    private func record(_ checkin: String?, checkout: String? = nil, date: String = "2026-10-12", id: String = "srv-1") -> AttendanceRecord {
        AttendanceRecord(id: id, date: date, status: checkout != nil ? "checked_out" : "checked_in",
                         checkinAt: checkin, checkoutAt: checkout, totalHours: nil,
                         checkinSelfieUrl: nil, checkoutSelfieUrl: nil)
    }

    private func punch(_ kind: OfflinePunch.Kind, _ iso: String, queued: TimeInterval, rejected: Bool = false,
                       error: String? = nil, mode: String? = nil, day: String = "2026-10-12") throws -> OfflinePunchState.PendingPunch {
        OfflinePunchState.PendingPunch(id: "p-\(queued)", kind: kind, capturedAt: try instant(iso),
                                       queuedAt: Date(timeIntervalSince1970: queued), attendanceDate: day,
                                       rejected: rejected, error: error, transportMode: mode)
    }

    func testWithNothingQueuedTodayIsExactlyWhatTheServerSaid() throws {
        let base = record("2026-10-12T03:42:00Z")
        XCTAssertEqual(OfflinePunchState.effectiveToday(base: base, punches: [])?.id, "srv-1")
        XCTAssertNil(OfflinePunchState.effectiveToday(base: nil, punches: []))
        // a refused punch changes nothing either
        let refused = try punch(.checkIn, "2026-10-12T03:42:00Z", queued: 1, rejected: true, error: "no")
        XCTAssertNil(OfflinePunchState.effectiveToday(base: nil, punches: [refused]))
    }

    func testAQueuedCheckInShowsTheRepAsCheckedInAtTheCaptureTime() throws {
        let p = try punch(.checkIn, "2026-10-12T03:42:00Z", queued: 1, mode: "car")
        let rec = try XCTUnwrap(OfflinePunchState.effectiveToday(base: nil, punches: [p]))
        XCTAssertTrue(OfflinePunchState.isStandIn(rec))
        XCTAssertEqual(rec.status, "checked_in")
        XCTAssertEqual(rec.date, "2026-10-12")
        XCTAssertEqual(parseISO(rec.checkinAt), try instant("2026-10-12T03:42:00Z"))
        XCTAssertNil(rec.checkoutAt)
        XCTAssertTrue(rec.isIn)
        XCTAssertEqual(rec.transportMode, "car")
    }

    func testTheServersRecordWinsOverAQueuedCheckInOfTheSameDay() throws {
        let base = record("2026-10-12T03:40:00Z")
        let p = try punch(.checkIn, "2026-10-12T03:42:00Z", queued: 1)
        let rec = try XCTUnwrap(OfflinePunchState.effectiveToday(base: base, punches: [p]))
        XCTAssertFalse(OfflinePunchState.isStandIn(rec))
        XCTAssertEqual(rec.checkinAt, "2026-10-12T03:40:00Z")
    }

    func testAQueuedCheckOutReadsAsCheckedOutUnlessTheServerAlreadyHasOne() throws {
        let base = record("2026-10-12T03:40:00Z")
        let out = try punch(.checkOut, "2026-10-12T12:30:00Z", queued: 2)
        let rec = try XCTUnwrap(OfflinePunchState.effectiveToday(base: base, punches: [out]))
        XCTAssertEqual(rec.status, "checked_out")
        XCTAssertEqual(parseISO(rec.checkoutAt), try instant("2026-10-12T12:30:00Z"))
        XCTAssertFalse(rec.isIn)

        let done = record("2026-10-12T03:40:00Z", checkout: "2026-10-12T12:00:00Z")
        let kept = try XCTUnwrap(OfflinePunchState.effectiveToday(base: done, punches: [out]))
        XCTAssertEqual(kept.checkoutAt, "2026-10-12T12:00:00Z")
    }

    func testACheckInAndACheckOutBothQueuedReadAsAFinishedShift() throws {
        let inn = try punch(.checkIn, "2026-10-12T03:40:00Z", queued: 1)
        let out = try punch(.checkOut, "2026-10-12T12:30:00Z", queued: 2)
        let rec = try XCTUnwrap(OfflinePunchState.effectiveToday(base: nil, punches: [out, inn]))
        XCTAssertEqual(rec.status, "checked_out")
        XCTAssertEqual(parseISO(rec.checkinAt), try instant("2026-10-12T03:40:00Z"))
        XCTAssertEqual(parseISO(rec.checkoutAt), try instant("2026-10-12T12:30:00Z"))
    }

    func testTheShiftDayIsTheDayOfTheOpenRecordElseTheDayOfTheCapture() throws {
        let overnight = record("2026-10-11T16:00:00Z", date: "2026-10-11")
        let capture = try instant("2026-10-12T03:00:00Z")
        XCTAssertEqual(OfflinePunchState.shiftDate(today: overnight, capturedAt: capture), "2026-10-11")
        XCTAssertEqual(OfflinePunchState.shiftDate(today: record("2026-10-12T03:40:00Z", date: "12--10--2026"), capturedAt: capture), "2026-10-12")
        XCTAssertEqual(OfflinePunchState.shiftDate(today: nil, capturedAt: capture), "2026-10-12")
        XCTAssertEqual(OfflinePunchState.shiftDate(today: record(nil, date: "2026-10-09"), capturedAt: capture), "2026-10-12")
    }

    // MARK: - the notice

    func testAWaitingPunchIsAnnouncedAndARefusedOneComesFirst() throws {
        XCTAssertNil(OfflinePunchState.notice(punches: [], zone: ist))
        let waiting = try punch(.checkIn, "2026-10-12T03:42:00Z", queued: 1)
        XCTAssertEqual(OfflinePunchState.notice(punches: [waiting], zone: ist),
                       OfflinePunchState.Notice(text: "Checked in 09:12 — will sync when online", isError: false))

        let refused = try punch(.checkOut, "2026-10-12T12:30:00Z", queued: 2, rejected: true, error: "You are outside the allowed area")
        let n = try XCTUnwrap(OfflinePunchState.notice(punches: [waiting, refused], zone: ist))
        XCTAssertTrue(n.isError)
        XCTAssertEqual(n.text, "Check-out 18:00 was not accepted: You are outside the allowed area")

        let noReason = try punch(.checkIn, "2026-10-12T03:42:00Z", queued: 3, rejected: true, error: "  ")
        XCTAssertEqual(OfflinePunchState.notice(punches: [noReason], zone: ist)?.text, "Check-in 09:12 was not accepted")
    }

    func testTheLatestWaitingPunchIsTheOneNamed() throws {
        let a = try punch(.checkIn, "2026-10-12T03:42:00Z", queued: 1)
        let b = try punch(.checkOut, "2026-10-12T12:30:00Z", queued: 5)
        XCTAssertEqual(OfflinePunchState.notice(punches: [a, b], zone: ist)?.text, "Checked out 18:00 — will sync when online")
    }

    // MARK: - dates

    func testAnApiDateReadsAsAnIsoDay() {
        XCTAssertEqual(OfflinePunchState.isoDateOf("2026-10-12"), "2026-10-12")
        XCTAssertEqual(OfflinePunchState.isoDateOf("2026-10-12T00:00:00Z"), "2026-10-12")
        XCTAssertEqual(OfflinePunchState.isoDateOf("12--10--2026"), "2026-10-12")
        XCTAssertEqual(OfflinePunchState.isoDateOf("  2026-10-12 "), "2026-10-12")
        XCTAssertEqual(OfflinePunchState.isoDateOf("tomorrow"), "tomorrow")
        XCTAssertEqual(OfflinePunchState.isoDateOf(nil), "")
        XCTAssertTrue(OfflinePunchState.isIsoDay("2026-10-12"))
        XCTAssertFalse(OfflinePunchState.isIsoDay("2026-1-12"))
        XCTAssertFalse(OfflinePunchState.isIsoDay("12--10--2026"))
    }

    func testOnlyTheRecordOfTheCurrentIndiaDayIsToday() throws {
        let now = try instant("2026-10-12T05:00:00Z")
        XCTAssertTrue(OfflinePunchState.isForToday(record("x", date: "2026-10-12"), now: now))
        XCTAssertTrue(OfflinePunchState.isForToday(record("x", date: "12--10--2026"), now: now))
        XCTAssertFalse(OfflinePunchState.isForToday(record("x", date: "2026-10-11"), now: now))
        XCTAssertFalse(OfflinePunchState.isForToday(nil, now: now))
    }

    // MARK: - the queued row

    private func row(_ kind: String = "checkin") -> PendingAttendance {
        PendingAttendance(id: UUID(), idempotencyKey: "att-ci-1", userKey: "u:1", kind: kind, lat: 18.5, lng: 73.8,
                          selfieUrl: nil, battery: 80, createdAt: Date(timeIntervalSince1970: 1_791_777_791),
                          attempt: 0, lastError: nil, isSynced: false)
    }

    func testARowQueuedBeforeTheNewFieldsStillLoadsAndIsNotOfflineCapable() throws {
        let json = """
        {"id":"7B2F1C0E-0000-4000-8000-000000000001","idempotencyKey":"att-ci-1","userKey":"abc","kind":"checkin",
         "lat":18.5,"lng":73.8,"selfieUrl":null,"battery":80,"createdAt":780000000,"attempt":2,"lastError":"x","isSynced":false}
        """
        let r = try JSONDecoder().decode(PendingAttendance.self, from: Data(json.utf8))
        XCTAssertNil(r.capturedAt)
        XCTAssertNil(r.attendanceDate)
        XCTAssertNil(r.photoFile)
        XCTAssertNil(r.selfieRequired)
        XCTAssertNil(r.transportMode)
        XCTAssertNil(r.dismissed)
    }

    func testTheCaptureAndTheTravelModeSurviveASaveAndLoad() throws {
        var r = row()
        r.capturedAt = try instant("2026-10-12T03:42:00Z")
        r.attendanceDate = "2026-10-12"
        r.photoFile = "att-ci-1.jpg"
        r.selfieRequired = true
        r.transportMode = "two_wheeler"
        r.dismissed = false
        let back = try JSONDecoder().decode(PendingAttendance.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.capturedAt, r.capturedAt)
        XCTAssertEqual(back.attendanceDate, "2026-10-12")
        XCTAssertEqual(back.photoFile, "att-ci-1.jpg")
        XCTAssertEqual(back.selfieRequired, true)
        XCTAssertEqual(back.transportMode, "two_wheeler")
        XCTAssertEqual(back.dismissed, false)
    }

    // MARK: - the request

    func testAClientThatConfiguredNothingSendsExactlyTheBodyItAlwaysDid() throws {
        let payload = AttendancePunch.requestPayload(
            isCheckIn: true, lat: 18.5, lng: 73.8, selfieUrl: "https://x/s.jpg", battery: 80,
            faceScore: nil, faceVerified: nil, faceModelId: nil, isMock: false, locationAccuracyM: 12.5,
            transportMode: nil, capturedAt: nil)
        XCTAssertEqual(Set(payload.keys),
                       ["latitude", "longitude", "selfie_url", "battery_percentage", "is_mock", "location_accuracy_m"])
        XCTAssertNil(AttendancePunch.queryItems(dateQuery: nil))
        XCTAssertNil(AttendancePunch.queryItems(dateQuery: ""))
    }

    func testTheOptInFieldsAppearOnlyWhenSet() throws {
        let withMode = AttendancePunch.requestPayload(
            isCheckIn: true, lat: 1, lng: 2, selfieUrl: nil, battery: nil, faceScore: nil, faceVerified: nil, faceModelId: nil,
            isMock: nil, locationAccuracyM: nil, transportMode: "two_wheeler", capturedAt: "2026-10-12T03:42:00Z")
        XCTAssertEqual(withMode["transport_mode"] as? String, "two_wheeler")
        XCTAssertEqual(withMode["captured_at"] as? String, "2026-10-12T03:42:00Z")

        // the travel mode rides with a CHECK-IN only
        let checkOut = AttendancePunch.requestPayload(
            isCheckIn: false, lat: 1, lng: 2, selfieUrl: nil, battery: nil, faceScore: nil, faceVerified: nil, faceModelId: nil,
            isMock: nil, locationAccuracyM: nil, transportMode: "two_wheeler", capturedAt: "2026-10-12T17:00:00Z")
        XCTAssertNil(checkOut["transport_mode"])
        XCTAssertEqual(checkOut["captured_at"] as? String, "2026-10-12T17:00:00Z")

        XCTAssertEqual(AttendancePunch.queryItems(dateQuery: "2026-10-11")?.first?.name, "date")
        XCTAssertEqual(AttendancePunch.queryItems(dateQuery: "2026-10-11")?.first?.value, "2026-10-11")
    }

    func testTheBodyIsByteIdenticalOnEveryAttempt() throws {
        func body() -> Data? {
            AttendancePunch.requestBody(AttendancePunch.requestPayload(
                isCheckIn: true, lat: 18.5, lng: 73.8, selfieUrl: "https://x/s.jpg", battery: 80,
                faceScore: 0.91, faceVerified: true, faceModelId: "m1", isMock: false, locationAccuracyM: 12.5,
                transportMode: "car", capturedAt: "2026-10-12T03:42:00Z"))
        }
        let first = try XCTUnwrap(body())
        for _ in 0..<20 { XCTAssertEqual(body(), first) }
        // keys are sorted, so the text is stable too
        let text = try XCTUnwrap(String(data: first, encoding: .utf8))
        let captured = try XCTUnwrap(text.range(of: "\"captured_at\""))
        let latitude = try XCTUnwrap(text.range(of: "\"latitude\""))
        XCTAssertTrue(captured.lowerBound < latitude.lowerBound)
    }
}
