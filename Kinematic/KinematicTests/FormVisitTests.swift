//
//  FormVisitTests.swift
//  KinematicTests
//
//  Check-in / check-out on every form (attendance rule `form_checkin_required`): which stored visit belongs to the form
//  being filled, what a submission is stamped with, the "On visit · mm:ss" / "Time on visit" texts, and how open visits
//  are remembered on the phone. With the rule OFF a form is stamped with nothing at all.
//

import XCTest
@testable import Kinematic

@MainActor
final class FormVisitTests: XCTestCase {

    private let t0: Date = Date(timeIntervalSince1970: 1_791_606_600)   // 2026-10-10T04:30:00Z = 10:00 in India
    private let min: TimeInterval = 60
    private let hour: TimeInterval = 3600

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// A route-plan visit at outlet o1 for activity a1, started at `start` seconds after t0.
    private func session(key: String = "a1", outlet: String? = "o1", start: TimeInterval = 0) -> FormVisitSession {
        FormVisitSession(key: key, outletId: outlet, name: "Shop", checkInAt: FormVisit.iso(at(start)), lat: 13.01, lng: 80.21)
    }

    private func stamp(enabled: Bool, _ s: FormVisitSession?, key: String? = "a1", outlet: String? = "o1",
                       lat: Double? = 13.05, lng: Double? = 80.25, now: TimeInterval = 14 * 60) -> FormVisit.Stamp {
        FormVisit.stamp(enabled: enabled, session: s, key: key, outletId: outlet, lat: lat, lng: lng, now: at(now))
    }

    // MARK: - which visit is this form's

    func testAVisitMatchesTheFormOfItsOwnActivityAndOutlet() {
        XCTAssertTrue(FormVisit.sessionMatches(session(), key: "a1", outletId: "o1", now: at(60)))
    }

    func testIdsCompareWithoutRegardToCaseOrStraySpaces() {
        XCTAssertTrue(FormVisit.sessionMatches(session(key: "ABC-1", outlet: "Out-1"), key: " abc-1 ", outletId: "out-1 ", now: t0))
    }

    func testAnotherOutletsVisitOrAnotherActivitysVisitDoesNotMatch() {
        XCTAssertFalse(FormVisit.sessionMatches(session(), key: "a1", outletId: "o2", now: t0))
        XCTAssertFalse(FormVisit.sessionMatches(session(), key: "a2", outletId: "o1", now: t0))
        XCTAssertFalse(FormVisit.sessionMatches(session(), key: "a1", outletId: nil, now: t0))
    }

    func testNoVisitNeverMatches() {
        XCTAssertFalse(FormVisit.sessionMatches(nil, key: "a1", outletId: "o1", now: t0))
    }

    func testABlankOutletEqualsNoOutlet() {
        let adHoc = session(key: FormVisit.adHocKey("t1"), outlet: nil)
        XCTAssertTrue(FormVisit.sessionMatches(adHoc, key: FormVisit.adHocKey("t1"), outletId: nil, now: t0))
        XCTAssertTrue(FormVisit.sessionMatches(adHoc, key: FormVisit.adHocKey("t1"), outletId: "  ", now: t0))
        XCTAssertTrue(FormVisit.sessionMatches(session(outlet: "  "), key: "a1", outletId: nil, now: t0))
    }

    func testAnAdHocFormHasItsOwnVisitPerTemplateAndNeverUsesARoutePlanVisit() {
        XCTAssertEqual(FormVisit.adHocKey("t1"), "adhoc:t1")
        XCTAssertEqual(FormVisit.adHocKey(nil), "adhoc:")
        XCTAssertTrue(FormVisit.isAdHocKey("adhoc:t1"))
        XCTAssertFalse(FormVisit.isAdHocKey("a1"))
        let adHoc = session(key: FormVisit.adHocKey("t1"), outlet: nil)
        XCTAssertFalse(FormVisit.sessionMatches(adHoc, key: FormVisit.adHocKey("t2"), outletId: nil, now: t0))
        // a route-plan visit is never taken by an ad-hoc form
        XCTAssertFalse(FormVisit.sessionMatches(session(), key: FormVisit.adHocKey("t1"), outletId: nil, now: t0))
        // and an ad-hoc visit is never taken by a route-plan form
        XCTAssertFalse(FormVisit.sessionMatches(adHoc, key: "a1", outletId: "o1", now: t0))
    }

    func testAVisitLeftBehindForMoreThanADayNoLongerBelongsToTheForm() {
        let s = session()
        XCTAssertTrue(FormVisit.sessionMatches(s, key: "a1", outletId: "o1", now: at(23 * hour)))
        XCTAssertTrue(FormVisit.sessionMatches(s, key: "a1", outletId: "o1", now: at(24 * hour)))
        XCTAssertFalse(FormVisit.sessionMatches(s, key: "a1", outletId: "o1", now: at(24 * hour + 1)))
        XCTAssertFalse(FormVisit.sessionMatches(s, key: "a1", outletId: "o1", now: at(30 * hour)))
    }

    func testAStartTimeALittleAheadOfTheClockIsFineFarAheadIsNot() {
        XCTAssertTrue(FormVisit.sessionMatches(session(start: 4 * min), key: "a1", outletId: "o1", now: t0))
        XCTAssertFalse(FormVisit.sessionMatches(session(start: 6 * min), key: "a1", outletId: "o1", now: t0))
    }

    func testAnUnreadableStartTimeDoesNotMatch() {
        var s = session()
        s.checkInAt = "yesterday"
        XCTAssertFalse(FormVisit.sessionMatches(s, key: "a1", outletId: "o1", now: t0))
        s.checkInAt = ""
        XCTAssertFalse(FormVisit.sessionMatches(s, key: "a1", outletId: "o1", now: t0))
    }

    // MARK: - rule OFF: exactly what has always been sent

    func testWithTheRuleOffNothingIsStampedEvenWithAVisitStored() {
        XCTAssertEqual(stamp(enabled: false, session()), FormVisit.Stamp.empty)
        XCTAssertEqual(stamp(enabled: false, nil), FormVisit.Stamp.empty)
        let s = stamp(enabled: false, session())
        XCTAssertNil(s.checkInAt)
        XCTAssertNil(s.checkOutAt)
        XCTAssertFalse(s.clearSession)
        XCTAssertNil(s.summary)
    }

    func testWithTheRuleOffTheRequestCarriesNoVisitKeysAtAll() throws {
        let request = FormSubmissionRequest(
            templateId: "t", activityId: nil, outletId: nil, outletName: nil, latitude: 1, longitude: 2,
            submittedAt: "2026-10-10T04:30:00Z", isConverted: false, responses: []
        )
        let json = String(data: try JSONEncoder().encode(request), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("check_in_at"))
        XCTAssertFalse(json.contains("check_out_at"))
        XCTAssertFalse(json.contains("check_in_gps"))
        XCTAssertFalse(json.contains("check_out_gps"))
    }

    // MARK: - rule ON: the submit is the check-out

    func testWithTheRuleOnTheFormIsStampedWithTheVisitsCheckInAndACheckOutOfNow() {
        let s = stamp(enabled: true, session(), now: 14 * min)
        XCTAssertEqual(s.checkInAt, FormVisit.iso(t0))
        XCTAssertEqual(s.checkInGps, "13.01,80.21")
        XCTAssertEqual(s.checkOutAt, FormVisit.iso(at(14 * min)))
        XCTAssertEqual(s.checkOutGps, "13.05,80.25")
        XCTAssertTrue(s.clearSession)
        XCTAssertEqual(s.summary?.minutes, 14)
        XCTAssertEqual(s.summary?.checkIn, t0)
        XCTAssertEqual(s.summary?.checkOut, at(14 * min))
    }

    func testTheStampedRequestCarriesTheFourValues() throws {
        let s = stamp(enabled: true, session(), now: 14 * min)
        let request = FormSubmissionRequest(
            templateId: "t", activityId: "a1", outletId: "o1", outletName: "Shop", latitude: 13.05, longitude: 80.25,
            submittedAt: "2026-10-10T04:44:00Z", isConverted: false, responses: [],
            checkInAt: s.checkInAt, checkOutAt: s.checkOutAt, checkInGps: s.checkInGps, checkOutGps: s.checkOutGps
        )
        let data = try JSONEncoder().encode(request)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["check_in_at"] as? String, "2026-10-10T04:30:00.000Z")
        XCTAssertEqual(obj["check_out_at"] as? String, "2026-10-10T04:44:00.000Z")
        XCTAssertEqual(obj["check_in_gps"] as? String, "13.01,80.21")
        XCTAssertEqual(obj["check_out_gps"] as? String, "13.05,80.25")
    }

    func testWithTheRuleOnAnAdHocFormDoesNotInheritAnotherVisitsCheckIn() {
        // a route-plan visit is stored; the rep fills an ad-hoc form
        let s = stamp(enabled: true, session(), key: FormVisit.adHocKey("t1"), outlet: nil)
        XCTAssertEqual(s, FormVisit.Stamp.empty)
        XCTAssertFalse(s.clearSession)   // the other visit is left alone
    }

    func testWithTheRuleOnAnAdHocFormUsesAndClearsItsOwnVisit() {
        let own = session(key: FormVisit.adHocKey("t1"), outlet: nil)
        let s = stamp(enabled: true, own, key: FormVisit.adHocKey("t1"), outlet: nil)
        XCTAssertEqual(s.checkInAt, FormVisit.iso(t0))
        XCTAssertEqual(s.checkOutAt, FormVisit.iso(at(14 * min)))
        XCTAssertTrue(s.clearSession)
    }

    func testWithTheRuleOnAnotherOutletsOrAStaleVisitIsNotUsedOrCleared() {
        XCTAssertEqual(stamp(enabled: true, session(outlet: "o9")), FormVisit.Stamp.empty)
        XCTAssertEqual(stamp(enabled: true, session(start: -30 * hour)), FormVisit.Stamp.empty)
        XCTAssertEqual(stamp(enabled: true, nil), FormVisit.Stamp.empty)
    }

    func testWithoutAFixTheCheckOutHasATimeButNoGps() {
        let s = stamp(enabled: true, session(), lat: nil, lng: nil)
        XCTAssertEqual(s.checkOutAt, FormVisit.iso(at(14 * min)))
        XCTAssertNil(s.checkOutGps)
        let nan = stamp(enabled: true, session(), lat: .nan, lng: 80.0)
        XCTAssertNil(nan.checkOutGps)
    }

    func testAClockThatWentBackwardsGivesACheckOutBeforeTheCheckInAndNoSummary() {
        let s = stamp(enabled: true, session(start: 0), now: -2 * min)
        XCTAssertEqual(s.checkInAt, FormVisit.iso(t0))
        XCTAssertEqual(s.checkOutAt, FormVisit.iso(at(-2 * min)))
        XCTAssertNil(s.summary)   // the server keeps both and stores no duration
        XCTAssertTrue(s.clearSession)
    }

    // MARK: - what the rep reads

    func testTheRunningChipCountsMmSsAndGoesToHMmSsAfterTheFirstHour() {
        let start = FormVisit.iso(t0)
        XCTAssertEqual(FormVisit.timerLabel(checkInAt: start, now: t0), "On visit · 00:00")
        XCTAssertEqual(FormVisit.timerLabel(checkInAt: start, now: at(4 * min + 7)), "On visit · 04:07")
        XCTAssertEqual(FormVisit.timerLabel(checkInAt: start, now: at(59 * min + 59)), "On visit · 59:59")
        XCTAssertEqual(FormVisit.timerLabel(checkInAt: start, now: at(hour + 2 * min + 3)), "On visit · 1:02:03")
    }

    func testTheRunningChipNeverGoesNegativeAndSurvivesAnUnreadableStart() {
        let start = FormVisit.iso(t0)
        XCTAssertEqual(FormVisit.timerLabel(checkInAt: start, now: at(-5)), "On visit · 00:00")
        XCTAssertEqual(FormVisit.timerLabel(checkInAt: nil, now: t0), "On visit")
        XCTAssertEqual(FormVisit.timerLabel(checkInAt: "soon", now: t0), "On visit")
        XCTAssertNil(FormVisit.elapsed(checkInAt: "soon", now: t0))
        XCTAssertEqual(FormVisit.elapsed(checkInAt: start, now: at(1.5)), 1.5)
    }

    func testALengthOfTimeIsSaidInWords() {
        XCTAssertEqual(FormVisit.durationLabel(0), "under a minute")
        XCTAssertEqual(FormVisit.durationLabel(29.999), "under a minute")
        XCTAssertEqual(FormVisit.durationLabel(30), "1 min")
        XCTAssertEqual(FormVisit.durationLabel(12 * min), "12 min")
        XCTAssertEqual(FormVisit.durationLabel(59 * min), "59 min")
        XCTAssertEqual(FormVisit.durationLabel(60 * min), "1 h")
        XCTAssertEqual(FormVisit.durationLabel(65 * min), "1 h 5 min")
        XCTAssertEqual(FormVisit.durationLabel(135 * min), "2 h 15 min")
        XCTAssertEqual(FormVisit.durationLabel(-5 * min), "under a minute")
    }

    func testTheSuccessStateNamesTheTotalAndTheWindowInTheRepsTimeZone() throws {
        let summary = try XCTUnwrap(stamp(enabled: true, session(), now: 14 * min).summary)
        XCTAssertEqual(FormVisit.totalLabel(summary), "Time on visit: 14 min")
        let ist = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(FormVisit.windowLabel(summary, timeZone: ist), "10:00 → 10:14")
        XCTAssertEqual(FormVisit.windowLabel(summary, timeZone: utc), "04:30 → 04:44")
        XCTAssertEqual(FormVisit.summaryMessage(summary, timeZone: ist), "Time on visit: 14 min\nChecked in and out: 10:00 → 10:14")
    }

    func testTheSummaryRoundsMinutesLikeTheServer() {
        let a = FormVisit.Summary(checkInAt: "a", checkOutAt: "b", checkIn: t0, checkOut: at(89))    // 1.48 min
        let b = FormVisit.Summary(checkInAt: "a", checkOutAt: "b", checkIn: t0, checkOut: at(91))    // 1.52 min
        XCTAssertEqual(a.minutes, 1)
        XCTAssertEqual(b.minutes, 2)
        XCTAssertEqual(a.duration, 89)
    }

    func testGpsAndInstantsHaveOneFormat() {
        XCTAssertEqual(FormVisit.gps(lat: 13.0, lng: 80.5), "13.0,80.5")
        XCTAssertNil(FormVisit.gps(lat: nil, lng: 80.5))
        XCTAssertNil(FormVisit.gps(lat: 13.0, lng: .infinity))
        XCTAssertEqual(FormVisit.parseInstant("2026-10-10T04:30:00.000Z"), t0)
        XCTAssertEqual(FormVisit.parseInstant("2026-10-10T04:30:00Z"), t0)
        XCTAssertNil(FormVisit.parseInstant(nil))
        XCTAssertNil(FormVisit.parseInstant(" "))
        XCTAssertNil(FormVisit.parseInstant("10/10/2026"))
        // the stamp's instants are the ones the existing forms already send
        XCTAssertEqual(FormVisit.iso(t0), "2026-10-10T04:30:00.000Z")
    }

    // MARK: - remembering open visits on the phone

    private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "FormVisitTests." + UUID().uuidString
        guard let d = UserDefaults(suiteName: name) else { return XCTFail("could not make a test UserDefaults") }
        defer { d.removePersistentDomain(forName: name) }
        try body(d)
    }

    func testAStartedVisitIsRememberedForItsOwner() {
        withSuite { d in
            FormVisitStore.save(session(), userId: "u1", now: at(60), in: d)
            XCTAssertEqual(FormVisitStore.session(forKey: "a1", userId: "u1", in: d), session())
            XCTAssertEqual(FormVisitStore.session(forKey: " A1 ", userId: "u1", in: d)?.key, "a1")
            XCTAssertNil(FormVisitStore.session(forKey: "a2", userId: "u1", in: d))
        }
    }

    func testAnotherPersonNeverSeesTheVisit() {
        withSuite { d in
            FormVisitStore.save(session(), userId: "u1", now: at(60), in: d)
            XCTAssertTrue(FormVisitStore.sessions(userId: "u2", in: d).isEmpty)
            XCTAssertTrue(FormVisitStore.sessions(userId: nil, in: d).isEmpty)
            XCTAssertTrue(FormVisitStore.sessions(userId: "  ", in: d).isEmpty)
            // and nothing is stored without a user
            FormVisitStore.save(session(key: "x"), userId: nil, now: at(60), in: d)
            XCTAssertEqual(FormVisitStore.sessions(userId: "u1", in: d).count, 1)
        }
    }

    func testSavingAFormsVisitAgainReplacesItAndKeepsTheOthers() {
        let one = session(key: "a1", start: 0)
        let two = session(key: "a2", start: 10 * min)
        let again = session(key: "a1", start: 20 * min)
        var list = FormVisitStore.merged([], adding: one, now: at(30 * min))
        list = FormVisitStore.merged(list, adding: two, now: at(30 * min))
        XCTAssertEqual(list.map { $0.key }, ["a1", "a2"])
        list = FormVisitStore.merged(list, adding: again, now: at(30 * min))
        XCTAssertEqual(list.map { $0.key }, ["a2", "a1"])
        XCTAssertEqual(list.last?.checkInAt, again.checkInAt)
    }

    func testVisitsTooOldToEverMatchAgainAreDroppedAndTheStoreIsBounded() {
        let stale = session(key: "old", start: 0)
        let fresh = session(key: "new", start: 30 * hour)
        let list = FormVisitStore.merged([stale], adding: fresh, now: at(31 * hour))
        XCTAssertEqual(list.map { $0.key }, ["new"])
        var big: [FormVisitSession] = []
        for i in 0..<30 { big = FormVisitStore.merged(big, adding: session(key: "k\(i)", start: 0), now: at(60)) }
        XCTAssertEqual(big.count, FormVisitStore.maxSessions)
        XCTAssertEqual(big.last?.key, "k29")
        XCTAssertEqual(big.first?.key, "k10")
    }

    func testRemovingAVisitForgetsOnlyThatForm() {
        withSuite { d in
            FormVisitStore.save(session(key: "a1"), userId: "u1", now: at(60), in: d)
            FormVisitStore.save(session(key: "a2"), userId: "u1", now: at(60), in: d)
            FormVisitStore.remove(key: "A1", userId: "u1", in: d)
            XCTAssertNil(FormVisitStore.session(forKey: "a1", userId: "u1", in: d))
            XCTAssertNotNil(FormVisitStore.session(forKey: "a2", userId: "u1", in: d))
            FormVisitStore.remove(key: "a2", userId: "u1", in: d)
            XCTAssertNil(d.object(forKey: FormVisitStore.storageKey))
            // removing what is not there is harmless
            FormVisitStore.remove(key: "zzz", userId: "u1", in: d)
        }
    }
}
