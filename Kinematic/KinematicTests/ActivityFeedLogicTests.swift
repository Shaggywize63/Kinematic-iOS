//
//  ActivityFeedLogicTests.swift
//  KinematicTests
//
//  What a "Recent activity" card says: the title (customer, else outlet, else form ...), the second line and the time
//  line, plus the feed row's wire shape — the new optional keys (`customer_name`, `form_name`, `title`, `subtitle`) and
//  the older rows that lack them must both decode. Mirrors the Android ActivityFeedLogicTest / FormFeedModelsTest.
//

import XCTest
@testable import Kinematic

@MainActor
final class ActivityFeedLogicTests: XCTestCase {

    private func item(title: String? = nil, customer: String? = nil, outlet: String? = nil, form: String? = nil,
                      subtitle: String? = nil, at: String? = "2026-10-11T11:00:00Z") -> ActivityFeedItem {
        ActivityFeedItem(id: "1", outletName: outlet, isConverted: false, submittedAt: at,
                         customerName: customer, formName: form, title: title, subtitle: subtitle)
    }

    // MARK: - title

    func testTheServersTitleWins() {
        XCTAssertEqual(ActivityFeedLogic.title(item(title: "Ramesh Traders", customer: "Ramesh", outlet: "Shop", form: "Visit")), "Ramesh Traders")
    }

    func testWithoutATitleTheCustomerNameIsNextThenTheOutletThenTheForm() {
        XCTAssertEqual(ActivityFeedLogic.title(item(customer: "Ramesh", outlet: "Shop", form: "Visit")), "Ramesh")
        XCTAssertEqual(ActivityFeedLogic.title(item(outlet: "Shop", form: "Visit")), "Shop")
        XCTAssertEqual(ActivityFeedLogic.title(item(form: "Visit")), "Visit")
        XCTAssertEqual(ActivityFeedLogic.title(item()), "Form Submission")
    }

    func testUnknownStoreIsNotAName() {
        XCTAssertEqual(ActivityFeedLogic.title(item(outlet: "Unknown Store", form: "Visit")), "Visit")
        XCTAssertEqual(ActivityFeedLogic.title(item(outlet: "unknown store")), "Form Submission")
        XCTAssertEqual(ActivityFeedLogic.title(item(outlet: " Unknown Store ")), "Form Submission")
        XCTAssertEqual(ActivityFeedLogic.title(item(customer: "Ramesh", outlet: "Unknown Store")), "Ramesh")
        // a real outlet whose name merely contains it is a name
        XCTAssertEqual(ActivityFeedLogic.title(item(outlet: "Unknown Store Annex")), "Unknown Store Annex")
        // the stand-in from the server's own title is skipped too
        XCTAssertEqual(ActivityFeedLogic.title(item(title: "Unknown Store", customer: "Ramesh")), "Ramesh")
    }

    func testBlankTextCountsAsMissingAndTheRestIsTrimmed() {
        XCTAssertEqual(ActivityFeedLogic.title(item(title: "  ", customer: "", outlet: " Shop ")), "Shop")
        XCTAssertEqual(ActivityFeedLogic.title(item(title: "", customer: " ", outlet: "\t", form: "  ")), "Form Submission")
    }

    // MARK: - subtitle

    func testTheSecondLineIsTheServersSubtitleElseTheFormName() {
        XCTAssertEqual(ActivityFeedLogic.subtitle(item(title: "Ramesh", form: "Visit", subtitle: "Dealer visit")), "Dealer visit")
        XCTAssertEqual(ActivityFeedLogic.subtitle(item(title: "Ramesh", form: "Visit")), "Visit")
        XCTAssertEqual(ActivityFeedLogic.subtitle(item(customer: "Ramesh", outlet: "Shop", form: "Visit")), "Visit")
    }

    func testASecondLineThatOnlyRepeatsTheTitleIsNotShown() {
        // the form name is the title (nothing else names the row)
        XCTAssertNil(ActivityFeedLogic.subtitle(item(form: "Visit")))
        XCTAssertNil(ActivityFeedLogic.subtitle(item(title: "visit", form: "Visit")))
        // a subtitle equal to the title falls back to the form name when that differs
        XCTAssertEqual(ActivityFeedLogic.subtitle(item(title: "Ramesh", form: "Visit", subtitle: "Ramesh")), "Visit")
        XCTAssertNil(ActivityFeedLogic.subtitle(item(title: "Ramesh", subtitle: "ramesh")))
    }

    func testNoSubtitleAndNoFormNameMeansNoSecondLine() {
        XCTAssertNil(ActivityFeedLogic.subtitle(item()))
        XCTAssertNil(ActivityFeedLogic.subtitle(item(outlet: "Shop")))
        XCTAssertNil(ActivityFeedLogic.subtitle(item(outlet: "Shop", form: " ", subtitle: "  ")))
        XCTAssertNil(ActivityFeedLogic.subtitle(item(outlet: "Shop", subtitle: "Unknown Store")))
    }

    // MARK: - time line

    private let ist = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone.current
    private let utc = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
    private let us = Locale(identifier: "en_US_POSIX")

    private func instant(_ iso: String) -> Date {
        ActivityFeedLogic.parseDate(iso) ?? Date(timeIntervalSince1970: 0)
    }

    private func line(_ at: String?, now: String, zone: TimeZone? = nil) -> String {
        ActivityFeedLogic.timeLine(at, now: instant(now), timeZone: zone ?? ist, locale: us)
    }

    func testSomethingFromTodayShowsJustTheTime() {
        // 11:00 UTC = 16:30 IST
        XCTAssertEqual(line("2026-10-11T11:00:00Z", now: "2026-10-11T13:00:00Z"), "04:30 PM")
        XCTAssertEqual(line("2026-10-11T03:30:00Z", now: "2026-10-11T13:00:00Z"), "09:00 AM")
        XCTAssertEqual(line("2026-10-11T11:00:00.123456+00:00", now: "2026-10-11T13:00:00Z"), "04:30 PM")
        XCTAssertEqual(line("2026-10-11T16:30:00+05:30", now: "2026-10-11T13:00:00Z"), "04:30 PM")
        XCTAssertEqual(line("2026-10-11T11:00:00+00", now: "2026-10-11T13:00:00Z"), "04:30 PM")
        XCTAssertEqual(line("2026-10-11T11:00:00", now: "2026-10-11T13:00:00Z"), "04:30 PM")   // no zone = UTC
    }

    func testSomethingOlderShowsTheDayWithTheTime() {
        XCTAssertEqual(line("2026-10-11T11:00:00Z", now: "2026-10-12T05:00:00Z"), "11 Oct, 04:30 PM")
        XCTAssertEqual(line("2026-09-03T04:30:00Z", now: "2026-10-12T05:00:00Z"), "3 Sep, 10:00 AM")
        // another year also names the year
        XCTAssertEqual(line("2025-10-11T11:00:00Z", now: "2026-10-12T05:00:00Z"), "11 Oct 2025, 04:30 PM")
    }

    func testTodayIsTheViewersDayNotUtcs() {
        // 20:00 UTC on the 11th is 01:30 on the 12th in India
        XCTAssertEqual(line("2026-10-11T20:00:00Z", now: "2026-10-12T05:00:00Z"), "01:30 AM")   // both the 12th in IST
        XCTAssertEqual(line("2026-10-11T20:00:00Z", now: "2026-10-12T05:00:00Z", zone: utc), "11 Oct, 08:00 PM")
        // around local midnight (India's midnight is 18:30 UTC)
        XCTAssertEqual(line("2026-10-11T18:29:00Z", now: "2026-10-11T18:29:30Z"), "11:59 PM")
        XCTAssertEqual(line("2026-10-11T18:29:00Z", now: "2026-10-11T18:31:00Z"), "11 Oct, 11:59 PM")
        XCTAssertEqual(line("2026-10-11T18:29:00Z", now: "2026-10-11T18:31:00Z", zone: utc), "06:29 PM")
    }

    func testAMissingOrUnreadableTimestampIsShownAsDashes() {
        XCTAssertEqual(line(nil, now: "2026-10-11T13:00:00Z"), "--")
        XCTAssertEqual(line("", now: "2026-10-11T13:00:00Z"), "--")
        XCTAssertEqual(line("yesterday", now: "2026-10-11T13:00:00Z"), "--")
        XCTAssertEqual(line("2026-13-45T99:99:99Z", now: "2026-10-11T13:00:00Z"), "--")
    }

    func testTimestampsParseInTheShapesTheApiUses() {
        XCTAssertEqual(ActivityFeedLogic.parseDate("1970-01-01T00:00:00Z")?.timeIntervalSince1970, 0)
        XCTAssertEqual(ActivityFeedLogic.parseDate("1970-01-01T05:30:00+05:30")?.timeIntervalSince1970, 0)
        XCTAssertEqual(ActivityFeedLogic.parseDate("1970-01-01T05:30:00+0530")?.timeIntervalSince1970, 0)
        XCTAssertEqual(ActivityFeedLogic.parseDate("1969-12-31T16:00:00-08:00")?.timeIntervalSince1970, 0)
        XCTAssertEqual(ActivityFeedLogic.parseDate("1970-01-01 00:00:00.999999+00")?.timeIntervalSince1970, 0)
        XCTAssertEqual(ActivityFeedLogic.parseDate("1970-01-01T00:00Z")?.timeIntervalSince1970, 0)
        XCTAssertNil(ActivityFeedLogic.parseDate("1970-01-01T00:00:00+99:00"))   // not a real offset
        XCTAssertNil(ActivityFeedLogic.parseDate("2026-02-30T10:00:00Z"))         // not a real day
        XCTAssertNil(ActivityFeedLogic.parseDate(nil))
    }

    // MARK: - the feed row's wire shape

    private func feed(_ extra: String) throws -> ActivityFeedItem {
        let json = #"{"id":"s1","outlet_name":"Shop","is_converted":true,"submitted_at":"2026-10-11T11:00:00Z"\#(extra)}"#
        return try JSONDecoder().decode(ActivityFeedItem.self, from: Data(json.utf8))
    }

    func testARowFromTheNewServerCarriesTheCustomerFormTitleAndSubtitle() throws {
        let row = try feed(#","customer_name":"Ramesh Kumar","form_name":"Dealer Visit","title":"Ramesh Kumar","subtitle":"Dealer Visit - Shop","n":1"#)
        XCTAssertEqual(row.customerName, "Ramesh Kumar")
        XCTAssertEqual(row.formName, "Dealer Visit")
        XCTAssertEqual(row.title, "Ramesh Kumar")
        XCTAssertEqual(row.subtitle, "Dealer Visit - Shop")
        XCTAssertTrue(row.isConverted)
        XCTAssertEqual(ActivityFeedLogic.title(row), "Ramesh Kumar")
        XCTAssertEqual(ActivityFeedLogic.subtitle(row), "Dealer Visit - Shop")
    }

    func testARowFromAnOlderServerStillDecodesAndReadsAsItDid() throws {
        let row = try feed("")
        XCTAssertNil(row.customerName)
        XCTAssertNil(row.formName)
        XCTAssertNil(row.title)
        XCTAssertNil(row.subtitle)
        XCTAssertEqual(row.outletName, "Shop")
        XCTAssertEqual(ActivityFeedLogic.title(row), "Shop")
        XCTAssertNil(ActivityFeedLogic.subtitle(row))
    }

    func testNullKeysAndTheUnknownStoreStandInFallBackSensibly() throws {
        let json = #"{"id":"s2","outlet_name":"Unknown Store","is_converted":false,"submitted_at":null,"customer_name":null,"form_name":"Dealer Visit","title":null,"subtitle":null}"#
        let row = try JSONDecoder().decode(ActivityFeedItem.self, from: Data(json.utf8))
        XCTAssertEqual(ActivityFeedLogic.title(row), "Dealer Visit")
        XCTAssertNil(ActivityFeedLogic.subtitle(row))
        XCTAssertEqual(ActivityFeedLogic.timeLine(row.submittedAt, now: Date(timeIntervalSince1970: 0)), "--")
    }

    func testOneOddRowDoesNotFailTheWholeFeed() throws {
        // a missing flag, a numeric id, wrong-typed names: all read leniently; the list still decodes
        let json = #"[{"id":7,"outlet_name":"A"},{"id":"b","is_converted":"true","title":5},{"id":"c","isConverted":true}]"#
        let rows = try JSONDecoder().decode([ActivityFeedItem].self, from: Data(json.utf8))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].id, "7")
        XCTAssertFalse(rows[0].isConverted)
        XCTAssertTrue(rows[1].isConverted)
        XCTAssertEqual(rows[1].title, "5")
        XCTAssertTrue(rows[2].isConverted)   // the older camelCase spelling is still read
    }

    func testTheFeedEnvelopeDecodes() throws {
        let json = #"{"success":true,"data":[{"id":"s1","outlet_name":"Shop","is_converted":false,"submitted_at":"2026-10-11T11:00:00Z","title":"Ramesh"}]}"#
        let res = try JSONDecoder().decode(ApiResponse<[ActivityFeedItem]>.self, from: Data(json.utf8))
        XCTAssertEqual(res.data?.first?.title, "Ramesh")
    }
}
