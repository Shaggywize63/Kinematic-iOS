//
//  DayTimelineTests.swift
//  KinematicTests
//
//  The Timeline screen's rules (module `timeline`): the readers for GET /attendance/daily-report and /daily-report/team
//  (envelope or bare payload, numbers sent as strings, one bad row skipped, never throws), the order and numbering of a
//  day's events (mirrors the web `buildTimeline` and the Android screen), the wording, the India day, who sees the team,
//  and the STRICT module gate.
//

import XCTest
@testable import Kinematic

final class DayTimelineTests: XCTestCase {

    private func json(_ s: String) -> AnyJSON? {
        try? JSONDecoder().decode(AnyJSON.self, from: Data(s.utf8))
    }

    private func at(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    private let day = """
    {"success":true,"data":{
      "date":"2026-10-16",
      "user":{"id":"u-1","name":"Ranadip","employee_id":"BK-07","role":"executive"},
      "shift":{"attendance_id":"a-1","checkin_at":"2026-10-16T03:30:00.123456+00:00","checkout_at":"2026-10-16T12:00:00Z","total_hours":"8.5","in_progress":false},
      "transport":{"mode":"own_bike","label":null},
      "travel":{"total_km":"23.456","method":"gps_trail","legs":[
        {"index":0,"km":5.2,"method":"gps_trail","from":{"kind":"checkin","at":"2026-10-16T03:30:00Z","lat":12.9,"lng":77.5},"to":{"kind":"form_checkin","label":"Sunrise School","at":"2026-10-16T04:00:00Z","lat":12.95,"lng":77.6}}
      ]},
      "visits":[
        {"submission_id":"s-1","label":"Sunrise School","arrival_at":"2026-10-16T04:00:00Z","departure_at":"2026-10-16T04:45:00Z","minutes":45,"lat":12.95,"lng":77.6},
        {"submission_id":"s-2","label":"No fix","arrival_at":"2026-10-16T05:00:00Z","departure_at":"2026-10-16T05:10:00Z","minutes":10,"lat":0,"lng":0}
      ],
      "halts":[{"index":0,"start_at":"2026-10-16T06:00:00Z","end_at":"2026-10-16T06:20:00Z","minutes":20,"lat":12.9,"lng":77.5,"points":6}],
      "route":{"points":[],"thinned":false},
      "summary":{"visits":2,"visit_minutes":55,"halts":1,"halt_minutes":20,"total_km":23.46}
    }}
    """

    // MARK: - The day

    func testADayIsReadFromTheEnvelope() throws {
        let r = try XCTUnwrap(DayTimelineParser.dailyReport(from: json(day)))
        XCTAssertEqual(r.date, "2026-10-16")
        XCTAssertEqual(r.name, "Ranadip")
        XCTAssertEqual(r.employeeId, "BK-07")
        XCTAssertEqual(r.attendanceId, "a-1")
        XCTAssertEqual(r.checkout, at("2026-10-16T12:00:00Z"))
        let checkin = try XCTUnwrap(r.checkin)
        XCTAssertEqual(checkin.timeIntervalSince1970, at("2026-10-16T03:30:00Z").timeIntervalSince1970 + 0.123, accuracy: 0.001)
        XCTAssertFalse(r.inProgress)
        XCTAssertEqual(r.legs.count, 1)
        XCTAssertEqual(r.legs[0].to?.label, "Sunrise School")
        XCTAssertEqual(r.visits.count, 2)
        XCTAssertEqual(r.halts.count, 1)
    }

    func testNumbersSentAsStringsAreRead() throws {
        let r = try XCTUnwrap(DayTimelineParser.dailyReport(from: json(day)))
        XCTAssertEqual(r.totalHours, 8.5)
        XCTAssertEqual(r.totalKm, 23.456, accuracy: 1e-9)
    }

    func testATransportLabelWinsElseTheModeIsMadeReadable() throws {
        XCTAssertEqual(DayTimelineParser.dailyReport(from: json(day))?.modeLabel, "Own bike")
        let labelled = day.replacingOccurrences(of: "\"label\":null", with: "\"label\":\"Hero Splendor\"")
        XCTAssertEqual(DayTimelineParser.dailyReport(from: json(labelled))?.modeLabel, "Hero Splendor")
        let none = day.replacingOccurrences(of: "\"mode\":\"own_bike\"", with: "\"mode\":null")
        XCTAssertNil(DayTimelineParser.dailyReport(from: json(none))?.modeLabel)
    }

    func testAZeroZeroLocationIsNoFixNotAPlace() throws {
        let r = try XCTUnwrap(DayTimelineParser.dailyReport(from: json(day)))
        XCTAssertEqual(r.visits[0].lat, 12.95)
        XCTAssertNil(r.visits[1].lat)
        XCTAssertNil(r.visits[1].lng)
    }

    func testTheBarePayloadReadsTheSameAsTheEnvelope() throws {
        guard case .object(let o)? = json(day), let inner = o["data"] else { return XCTFail("fixture") }
        XCTAssertEqual(DayTimelineParser.dailyReport(from: inner)?.name, "Ranadip")
    }

    func testADayWithNoAttendanceIsAReportWithNoShift() throws {
        let r = try XCTUnwrap(DayTimelineParser.dailyReport(from: json("""
        {"success":true,"data":{"date":"2026-10-15","user":{"id":"u-1","name":"Ranadip"},
         "shift":{"attendance_id":null,"checkin_at":null,"checkout_at":null,"total_hours":null,"in_progress":false},
         "transport":{"mode":null,"label":null},"travel":{"total_km":0,"method":"none","legs":[]},
         "visits":[],"halts":[],"route":{"points":[],"thinned":false},
         "summary":{"visits":0,"visit_minutes":0,"halts":0,"halt_minutes":0,"total_km":0}}}
        """)))
        XCTAssertNil(r.attendanceId)
        XCTAssertTrue(r.legs.isEmpty)
        XCTAssertTrue(r.visits.isEmpty)
        XCTAssertTrue(DayTimelineLogic.buildTimeline(r).isEmpty)
    }

    func testAnErrorBodyOrJunkIsNotAReport() {
        XCTAssertNil(DayTimelineParser.dailyReport(from: json(#"{"success":false,"error":"You can only view your own travel report"}"#)))
        XCTAssertNil(DayTimelineParser.dailyReport(from: json("[1,2]")))
        XCTAssertNil(DayTimelineParser.dailyReport(from: json("\"nope\"")))
        XCTAssertNil(DayTimelineParser.dailyReport(from: nil))
    }

    func testAnUnreadableTimeIsNilNeverACrash() throws {
        let r = try XCTUnwrap(DayTimelineParser.dailyReport(from: json(day.replacingOccurrences(of: "2026-10-16T12:00:00Z", with: "yesterday-ish"))))
        XCTAssertNil(r.checkout)
        XCTAssertNotNil(r.checkin)
    }

    func testAMalformedVisitRowIsSkippedTheRestAreKept() throws {
        let r = try XCTUnwrap(DayTimelineParser.dailyReport(from: json("""
        {"data":{"shift":{"attendance_id":"a-1"},"visits":["junk",{"submission_id":"s-1","label":"Shop","arrival_at":"2026-10-16T04:00:00Z","minutes":5}]}}
        """)))
        XCTAssertEqual(r.visits.map { $0.id }, ["s-1"])
    }

    // MARK: - The team

    func testTheTeamListIsReadWithARowWithoutAUserIdSkipped() throws {
        let rows = try XCTUnwrap(DayTimelineParser.teamReport(from: json("""
        {"success":true,"data":{"date":"2026-10-16","rows":[
          {"user_id":"u-1","name":"Ranadip","employee_id":"BK-07","checkin_at":"2026-10-16T03:30:00Z","checkout_at":null,
           "total_hours":null,"mode":"own_bike","label":null,"total_km":"12.5","visits":3,"visit_minutes":90,"halts":2,"halt_minutes":35},
          {"name":"No id"}
        ]}}
        """)))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "Ranadip")
        XCTAssertEqual(rows[0].totalKm, 12.5)
        XCTAssertEqual(rows[0].visits, 3)
        XCTAssertEqual(rows[0].haltMinutes, 35)
        XCTAssertNil(rows[0].checkout)
        XCTAssertEqual(rows[0].modeLabel, "Own bike")
    }

    func testAnEmptyTeamIsAnEmptyListAnUnreadableReplyIsNil() {
        XCTAssertEqual(DayTimelineParser.teamReport(from: json(#"{"success":true,"data":{"date":"2026-10-16","rows":[]}}"#))?.count, 0)
        XCTAssertNil(DayTimelineParser.teamReport(from: json(#"{"success":false,"error":"Forbidden"}"#)))
        XCTAssertNil(DayTimelineParser.teamReport(from: nil))
    }

    func testABareRowsArrayIsAccepted() {
        let rows = DayTimelineParser.teamReport(from: json(#"[{"user_id":"u-1","name":"A"}]"#))
        XCTAssertEqual(rows?.map { $0.userId }, ["u-1"])
    }

    // MARK: - Order and numbering

    private func report(
        attendanceId: String? = "a-1",
        checkin: String? = "2026-10-16T03:30:00Z",
        checkout: String? = "2026-10-16T12:00:00Z",
        legs: [DayLeg] = [], visits: [DayVisit] = [], halts: [DayHalt] = []
    ) -> DayReportData {
        DayReportData(date: "2026-10-16", userId: "u-1", name: "Ranadip", employeeId: nil, attendanceId: attendanceId,
                      checkin: checkin.map(at), checkout: checkout.map(at), totalHours: nil, inProgress: false,
                      modeLabel: nil, totalKm: 0, legs: legs, visits: visits, halts: halts)
    }

    private func visit(_ id: String, _ from: String, _ to: String, _ minutes: Int, label: String? = nil) -> DayVisit {
        DayVisit(id: id, label: label ?? "Shop \(id)", arrival: at(from), departure: at(to), minutes: minutes, lat: 12.9, lng: 77.5)
    }

    private func halt(_ i: Int, _ from: String, _ to: String, _ minutes: Int, points: Int = 5) -> DayHalt {
        DayHalt(index: i, start: at(from), end: at(to), minutes: minutes, points: points, lat: 12.9, lng: 77.5)
    }

    private func leg(_ i: Int, _ km: Double, _ fromKind: String, _ fromAt: String, _ toKind: String, _ toAt: String,
                     toLabel: String? = nil, method: String = "gps_trail") -> DayLeg {
        DayLeg(index: i, km: km, method: method,
               from: DayPoint(kind: fromKind, label: nil, at: at(fromAt)),
               to: DayPoint(kind: toKind, label: toLabel, at: at(toAt)))
    }

    func testADayWithNoAttendanceHasNoEvents() {
        XCTAssertTrue(DayTimelineLogic.buildTimeline(report(attendanceId: nil)).isEmpty)
    }

    func testEventsComeInTheOrderTheyStartCheckInFirstAndCheckOutLast() {
        let events = DayTimelineLogic.buildTimeline(report(
            legs: [
                leg(0, 5.0, "checkin", "2026-10-16T03:30:00Z", "form_checkin", "2026-10-16T04:00:00Z", toLabel: "School A"),
                leg(1, 3.0, "form_checkout", "2026-10-16T04:45:00Z", "checkout", "2026-10-16T12:00:00Z"),
            ],
            visits: [visit("s-1", "2026-10-16T04:00:00Z", "2026-10-16T04:45:00Z", 45)]))
        XCTAssertEqual(events.map { $0.kind }, [.checkin, .travel, .visit, .travel, .checkout])
        XCTAssertEqual(events.map { $0.seq }, [1, 2, 3, 4, 5])
    }

    func testAHaltInTheMiddleOfALongLegSitsAfterThatLegAndBeforeTheNextVisit() {
        let events = DayTimelineLogic.buildTimeline(report(
            checkin: "2026-10-16T03:00:00Z", checkout: nil,
            legs: [leg(0, 20.0, "checkin", "2026-10-16T03:00:00Z", "form_checkin", "2026-10-16T05:00:00Z")],
            visits: [visit("s-1", "2026-10-16T05:00:00Z", "2026-10-16T05:30:00Z", 30)],
            halts: [halt(0, "2026-10-16T04:00:00Z", "2026-10-16T04:20:00Z", 20)]))
        XCTAssertEqual(events.map { $0.kind }, [.checkin, .travel, .halt, .visit])
    }

    func testVisitsAndHaltsShareOneCountInTimeOrderTheRestCarryNone() {
        let events = DayTimelineLogic.buildTimeline(report(
            visits: [visit("s-1", "2026-10-16T04:00:00Z", "2026-10-16T04:30:00Z", 30),
                     visit("s-2", "2026-10-16T07:00:00Z", "2026-10-16T07:30:00Z", 30)],
            halts: [halt(0, "2026-10-16T05:00:00Z", "2026-10-16T05:20:00Z", 20)]))
        let numbered = events.filter { $0.marker != nil }
        XCTAssertEqual(numbered.map { $0.kind }, [.visit, .halt, .visit])
        XCTAssertEqual(numbered.map { $0.marker }, [1, 2, 3])
        XCTAssertEqual(events.filter { $0.marker == nil }.map { $0.kind }, [.checkin, .checkout])
    }

    func testAtTheSameInstantACheckInComesFirstAndACheckOutLast() {
        let t = "2026-10-16T05:00:00Z"
        let events = DayTimelineLogic.buildTimeline(report(checkin: t, checkout: t, visits: [visit("s-1", t, t, 0)]))
        XCTAssertEqual(events.map { $0.kind }, [.checkin, .visit, .checkout])
    }

    func testARowWithNoReadableTimeSinksToTheBottom() {
        let untimed = DayVisit(id: "s-x", label: "Untimed", arrival: nil, departure: nil, minutes: 0, lat: nil, lng: nil)
        let events = DayTimelineLogic.buildTimeline(report(
            visits: [untimed, visit("s-1", "2026-10-16T04:00:00Z", "2026-10-16T04:30:00Z", 30)]))
        XCTAssertEqual(events.last?.kind, .visit)
        XCTAssertEqual(events.last?.detail, "Untimed")
    }

    // MARK: - Wording

    func testATravelLegReadsFromToAndSaysHowItWasMeasured() throws {
        let events = DayTimelineLogic.buildTimeline(report(legs: [
            leg(0, 2.0, "checkin", "2026-10-16T03:30:00Z", "form_checkin", "2026-10-16T04:00:00Z", toLabel: "School A", method: "straight_line"),
        ]))
        let e = try XCTUnwrap(events.first { $0.kind == .travel })
        XCTAssertEqual(e.detail, "Check-in → School A · straight line")
        XCTAssertEqual(e.km, 2.0)
    }

    func testALegThatRunsToNowIsOpenEnded() throws {
        let events = DayTimelineLogic.buildTimeline(report(
            checkout: nil,
            legs: [leg(0, 4.0, "checkin", "2026-10-16T03:30:00Z", "now", "2026-10-16T06:00:00Z")]))
        let e = try XCTUnwrap(events.first { $0.kind == .travel })
        XCTAssertTrue(e.openEnd)
        XCTAssertNil(e.end)
        XCTAssertEqual(DayTimelineLogic.rangeText(e), "9:00 AM – now")
    }

    func testAHaltSaysHowManyGpsPingsItIsMadeOf() throws {
        let events = DayTimelineLogic.buildTimeline(report(halts: [halt(0, "2026-10-16T05:00:00Z", "2026-10-16T05:20:00Z", 20, points: 6)]))
        let e = try XCTUnwrap(events.first { $0.kind == .halt })
        XCTAssertEqual(e.detail, "6 GPS pings")
        XCTAssertEqual(e.minutes, 20)
    }

    // MARK: - Formatting (India time)

    func testClockTimesAreIndiaTime() {
        XCTAssertEqual(DayTimelineLogic.clockText(at("2026-10-16T03:30:00Z")), "9:00 AM")
        XCTAssertEqual(DayTimelineLogic.clockText(at("2026-10-16T18:45:00Z")), "12:15 AM")
        XCTAssertEqual(DayTimelineLogic.clockText(nil), "—")
    }

    func testARangeShowsStartAndEndOrJustTheStart() throws {
        let events = DayTimelineLogic.buildTimeline(report(visits: [visit("s-1", "2026-10-16T04:00:00Z", "2026-10-16T04:45:00Z", 45)]))
        let e = try XCTUnwrap(events.first { $0.kind == .visit })
        XCTAssertEqual(DayTimelineLogic.rangeText(e), "9:30 AM – 10:15 AM")
        let same = DayTimelineEvent(id: e.id, kind: e.kind, seq: e.seq, marker: e.marker, start: e.start, end: e.start, openEnd: false,
                                    minutes: e.minutes, km: e.km, title: e.title, detail: e.detail, lat: e.lat, lng: e.lng)
        XCTAssertEqual(DayTimelineLogic.rangeText(same), "9:30 AM")
    }

    func testDurationsReadInMinutesThenHours() {
        XCTAssertEqual(DayTimelineLogic.durationText(0), "0 min")
        XCTAssertEqual(DayTimelineLogic.durationText(45), "45 min")
        XCTAssertEqual(DayTimelineLogic.durationText(60), "1h")
        XCTAssertEqual(DayTimelineLogic.durationText(65), "1h 05m")
        XCTAssertNil(DayTimelineLogic.durationText(nil))
        XCTAssertNil(DayTimelineLogic.durationText(-1))
    }

    func testKilometresKeepAtMostTwoDecimalsAndNoTrailingZeros() {
        XCTAssertEqual(DayTimelineLogic.kmText(23.456), "23.46 km")
        XCTAssertEqual(DayTimelineLogic.kmText(23.4), "23.4 km")
        XCTAssertEqual(DayTimelineLogic.kmText(5.0), "5 km")
        XCTAssertEqual(DayTimelineLogic.kmText(100.0), "100 km")
        XCTAssertEqual(DayTimelineLogic.kmText(0.0), "0 km")
        XCTAssertEqual(DayTimelineLogic.kmText(nil), "0 km")
    }

    func testHoursReadAsHAndMUnknownAsADash() {
        XCTAssertEqual(DayTimelineLogic.hoursText(7.5), "7h 30m")
        XCTAssertEqual(DayTimelineLogic.hoursText(8.0), "8h 0m")
        XCTAssertEqual(DayTimelineLogic.hoursText(nil), "—")
    }

    // MARK: - Dates

    func testDaysStepAcrossMonthAndYearEnds() {
        XCTAssertEqual(DayTimelineLogic.shiftDay("2026-10-01", by: -1), "2026-09-30")
        XCTAssertEqual(DayTimelineLogic.shiftDay("2026-12-31", by: 1), "2027-01-01")
        XCTAssertEqual(DayTimelineLogic.shiftDay("not-a-date", by: 1), "not-a-date")
    }

    func testTheDayLabelIsReadable() {
        XCTAssertEqual(DayTimelineLogic.dayLabel("2026-10-16"), "Fri, 16 Oct 2026")
        XCTAssertEqual(DayTimelineLogic.dayLabel("junk"), "junk")
    }

    func testTodayIsTheIndiaDayNotTheUtcDay() {
        // 20:00 UTC on the 15th is already 01:30 on the 16th in India.
        XCTAssertEqual(DayTimelineLogic.today(now: at("2026-10-15T20:00:00Z")), "2026-10-16")
        XCTAssertEqual(DayTimelineLogic.today(now: at("2026-10-15T10:00:00Z")), "2026-10-15")
    }

    // MARK: - Who sees the team

    func testManagersGetTheTeamViewFieldExecutivesDoNot() {
        for role in ["supervisor", "city_manager", "city-manager", "admin", "super_admin", "client", "Supervisor", " admin "] {
            XCTAssertTrue(DayTimelineLogic.canViewTeam(role: role), role)
        }
        for role in ["executive", "salesman", "telecaller", ""] {
            XCTAssertFalse(DayTimelineLogic.canViewTeam(role: role), role)
        }
        XCTAssertFalse(DayTimelineLogic.canViewTeam(role: nil))
    }

    // MARK: - The request

    func testTheQueryCarriesOnlyWhatIsSet() {
        XCTAssertEqual(DayTimelineAPI.query(date: nil, userId: nil), "")
        XCTAssertEqual(DayTimelineAPI.query(date: "", userId: ""), "")
        XCTAssertEqual(DayTimelineAPI.query(date: "2026-10-16", userId: nil), "?date=2026-10-16")
        XCTAssertEqual(DayTimelineAPI.query(date: "2026-10-16", userId: "u-1"), "?date=2026-10-16&user_id=u-1")
    }

    func testTheServersOwnWordsAreShownElseAPlainLinePerStatus() {
        XCTAssertEqual(DayTimelineAPI.message(serverMessage: "You can only view your own travel report", status: 403),
                       "You can only view your own travel report")
        XCTAssertEqual(DayTimelineAPI.message(serverMessage: nil, status: 403), "You don't have permission to view this.")
        XCTAssertEqual(DayTimelineAPI.message(serverMessage: "  ", status: 503), "The server had a problem. Try again in a moment.")
        XCTAssertEqual(DayTimelineAPI.message(serverMessage: nil, status: 418), "Request failed (418)")
    }

    // MARK: - The module gate

    private func user(modules: [String]) throws -> User {
        let list = modules.map { "\"\($0)\"" }.joined(separator: ",")
        let json = #"{"id":"u1","name":"Asha","role":"executive","enabled_modules":[\#(list)]}"#
        return try JSONDecoder().decode(User.self, from: Data(json.utf8))
    }

    func testTheTimelineSheetNeedsTheTimelineModule() throws {
        XCTAssertTrue(SecondaryRoute.timeline.isAvailable(for: try user(modules: ["timeline", "attendance"])))
        XCTAssertFalse(SecondaryRoute.timeline.isAvailable(for: try user(modules: ["attendance", "form_builder"])))
    }

    func testALegacySessionWithNoModuleListNeverOpensTheTimeline() throws {
        // `hasModule` reads an empty list as full access; the Timeline is STRICT, like Expenses and Stock & Batches.
        let legacy = try user(modules: [])
        XCTAssertFalse(SecondaryRoute.timeline.isAvailable(for: legacy))
        XCTAssertEqual(SecondaryRoute.timeline.strictModule, "timeline")
        XCTAssertFalse(SecondaryRoute.timeline.isAvailable(for: nil))
    }

    func testAnAdminCanHideOrRenameTheMenuEntry() throws {
        let json = #"{"id":"u1","name":"Asha","role":"executive","enabled_modules":["timeline"],"app_ui_config":{"menu":{"timeline":false},"labels":{"menu":{"timeline":"My Day"}}}}"#
        let u = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        XCTAssertFalse(u.menuVisible("timeline"))
        XCTAssertEqual(u.label("menu", "timeline", default: "Timeline"), "My Day")
        let plain = try user(modules: ["timeline"])
        XCTAssertTrue(plain.menuVisible("timeline"))
        XCTAssertEqual(plain.label("menu", "timeline", default: "Timeline"), "Timeline")
    }
}
