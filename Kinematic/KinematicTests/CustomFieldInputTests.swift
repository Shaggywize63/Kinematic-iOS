//
//  CustomFieldInputTests.swift
//  KinematicTests
//
//  The input rules of the CRM custom fields (`CustomFieldsSection`): the `datetime` field stores the day and time the
//  rep picked as a UTC instant and shows it back on their own clock; a number / currency box keeps digits and one decimal
//  point; which field types get a multi-line box. Mirrors the Android CrmDateTimeTest.
//

import XCTest
@testable import Kinematic

@MainActor
final class CustomFieldInputTests: XCTestCase {

    private let ist: TimeZone = TimeZone(secondsFromGMT: 19_800) ?? TimeZone.current
    private let utc: TimeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current

    /// 2026-10-12 11:00:00 UTC, as seconds since 1970 (checked with an independent calendar).
    private let noon: TimeInterval = 1_791_802_800
    /// 2026-10-12 00:00:00 UTC.
    private let midnight: TimeInterval = 1_791_763_200

    private func parts(_ hour: Int, _ minute: Int, day: Int = 12) -> FormDateTimeParts {
        FormDateTimeParts(date: FormDay(year: 2026, month: 10, day: day), hour: hour, minute: minute)
    }

    private func seconds(_ raw: String?) -> TimeInterval? {
        CrmDateTime.parseDate(raw)?.timeIntervalSince1970
    }

    // MARK: - what is stored

    func testThePickedMomentIsStoredAsUtcWithZeroSeconds() {
        // 4:30 PM in India is 11:00 UTC; the same wall-clock time in UTC is itself.
        XCTAssertEqual(CrmDateTime.store(parts(16, 30), timeZone: ist), "2026-10-12T11:00:00Z")
        XCTAssertEqual(CrmDateTime.store(parts(16, 30), timeZone: utc), "2026-10-12T16:30:00Z")
    }

    func testAMorningInIndiaIsTheEveningBeforeInUtc() {
        XCTAssertEqual(CrmDateTime.store(parts(2, 15), timeZone: ist), "2026-10-11T20:45:00Z")
    }

    func testTheStoredValueReadsBackAsTheSameMoment() {
        let stored = CrmDateTime.store(parts(16, 30), timeZone: ist)
        XCTAssertEqual(seconds(stored), noon)
    }

    // MARK: - what is read

    func testEveryShapeOfAnInstantReadsAsTheSameMoment() {
        XCTAssertEqual(seconds("2026-10-12T11:00:00Z"), noon)
        XCTAssertEqual(seconds("2026-10-12T16:30:00+05:30"), noon)
        XCTAssertEqual(seconds("2026-10-12T11:00:00.000Z"), noon)
        XCTAssertEqual(seconds("2026-10-12T11:00:00+00:00"), noon)
        XCTAssertEqual(seconds("2026-10-12 11:00:00Z"), noon)
        // a timestamp with no zone is UTC, the way the server writes it
        XCTAssertEqual(seconds("2026-10-12T11:00:00"), noon)
        // surrounding blanks are ignored
        XCTAssertEqual(seconds("  2026-10-12T11:00:00Z  "), noon)
    }

    func testABareDateIsMidnightUtc() {
        // what the old date picker stored
        XCTAssertEqual(seconds("2026-10-12"), midnight)
    }

    func testUnreadableValuesAreNil() {
        XCTAssertNil(CrmDateTime.parseDate(nil))
        XCTAssertNil(CrmDateTime.parseDate(""))
        XCTAssertNil(CrmDateTime.parseDate("   "))
        XCTAssertNil(CrmDateTime.parseDate("tomorrow"))
        XCTAssertNil(CrmDateTime.parseDate("12/10/2026"))
        XCTAssertNil(CrmDateTime.parseDate("2026-13-40"))
        XCTAssertNil(CrmDateTime.parseDate("2026-10-12T25:00:00Z"))
    }

    // MARK: - what is shown

    func testTheValueIsShownOnTheViewersClock() {
        XCTAssertEqual(CrmDateTime.display("2026-10-12T11:00:00Z", timeZone: ist), "12 Oct 2026, 4:30 PM")
        XCTAssertEqual(CrmDateTime.display("2026-10-12T11:00:00Z", timeZone: utc), "12 Oct 2026, 11:00 AM")
    }

    func testMidnightAndNoonReadTwelve() {
        XCTAssertEqual(CrmDateTime.display("2026-10-12T00:00:00Z", timeZone: utc), "12 Oct 2026, 12:00 AM")
        XCTAssertEqual(CrmDateTime.display("2026-10-12T12:05:00Z", timeZone: utc), "12 Oct 2026, 12:05 PM")
    }

    func testABareDateShowsAsMidnightUtcOnTheViewersClock() {
        XCTAssertEqual(CrmDateTime.display("2026-10-12", timeZone: ist), "12 Oct 2026, 5:30 AM")
    }

    func testNoValueShowsNothingAndUnreadableTextShowsAsIs() {
        XCTAssertEqual(CrmDateTime.display(nil, timeZone: ist), "")
        XCTAssertEqual(CrmDateTime.display("", timeZone: ist), "")
        XCTAssertEqual(CrmDateTime.display("   ", timeZone: ist), "")
        XCTAssertEqual(CrmDateTime.display("next week", timeZone: ist), "next week")
    }

    // MARK: - opening the pickers

    func testThePickersOpenOnTheViewersClock() {
        XCTAssertEqual(CrmDateTime.localParts("2026-10-12T11:00:00Z", timeZone: ist), parts(16, 30))
        XCTAssertEqual(CrmDateTime.localParts("2026-10-12T11:00:00Z", timeZone: utc), parts(11, 0))
        // across midnight
        XCTAssertEqual(CrmDateTime.localParts("2026-10-11T20:45:00Z", timeZone: ist), parts(2, 15))
        XCTAssertNil(CrmDateTime.localParts(nil, timeZone: ist))
        XCTAssertNil(CrmDateTime.localParts("not a date", timeZone: ist))
    }

    func testStoringThenOpeningRoundTripsInEveryZone() throws {
        let newYork: TimeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let auckland: TimeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let zones: [TimeZone] = [ist, utc, newYork, auckland]
        for zone in zones {
            let picked = parts(16, 30)
            let stored = CrmDateTime.store(picked, timeZone: zone)
            XCTAssertNotNil(stored, zone.identifier)
            XCTAssertEqual(CrmDateTime.localParts(stored, timeZone: zone), picked, zone.identifier)
            XCTAssertEqual(CrmDateTime.display(stored, timeZone: zone), "12 Oct 2026, 4:30 PM", zone.identifier)
        }
    }

    func testAnEarlyMorningRoundTripsAcrossTheDateLine() throws {
        let auckland = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let picked = parts(0, 5)
        let stored = CrmDateTime.store(picked, timeZone: auckland)
        XCTAssertEqual(CrmDateTime.localParts(stored, timeZone: auckland), picked)
    }

    // MARK: - number and currency boxes

    func testANumberBoxKeepsDigitsAndOneDecimalPoint() {
        XCTAssertEqual(CustomFieldInput.numeric("123"), "123")
        XCTAssertEqual(CustomFieldInput.numeric("12.5"), "12.5")
        XCTAssertEqual(CustomFieldInput.numeric(".5"), ".5")
        XCTAssertEqual(CustomFieldInput.numeric(""), "")
    }

    func testOnlyTheFirstDecimalPointSurvives() {
        XCTAssertEqual(CustomFieldInput.numeric("12.5.3"), "12.53")
        XCTAssertEqual(CustomFieldInput.numeric("1..2"), "1.2")
    }

    func testLettersSeparatorsAndSignsAreDropped() {
        XCTAssertEqual(CustomFieldInput.numeric("abc"), "")
        XCTAssertEqual(CustomFieldInput.numeric("1,234.50"), "1234.50")
        XCTAssertEqual(CustomFieldInput.numeric("-5"), "5")
        XCTAssertEqual(CustomFieldInput.numeric("+91 98765"), "9198765")
        XCTAssertEqual(CustomFieldInput.numeric("1e5"), "15")
    }

    func testOnlyAsciiDigitsAreKept() {
        // Arabic-Indic and full-width digits are digits to a person but not to the server
        XCTAssertEqual(CustomFieldInput.numeric("\u{0663}\u{0664}"), "")
        XCTAssertEqual(CustomFieldInput.numeric("\u{FF11}\u{FF12}"), "")
        XCTAssertEqual(CustomFieldInput.numeric("\u{00BD}"), "")
    }

    // MARK: - which field types get which box

    func testLongAnswersGetAMultiLineBox() {
        XCTAssertTrue(CustomFieldInput.isLongText("longtext"))
        XCTAssertTrue(CustomFieldInput.isLongText("long_text"))
        XCTAssertTrue(CustomFieldInput.isLongText("textarea"))
        XCTAssertTrue(CustomFieldInput.isLongText(" TextArea "))
        XCTAssertFalse(CustomFieldInput.isLongText("text"))
        XCTAssertFalse(CustomFieldInput.isLongText("string"))
        XCTAssertFalse(CustomFieldInput.isLongText(""))
    }

    func testNumberAndCurrencyGetTheNumericBox() {
        XCTAssertTrue(CustomFieldInput.isNumeric("number"))
        XCTAssertTrue(CustomFieldInput.isNumeric("currency"))
        XCTAssertTrue(CustomFieldInput.isNumeric(" Number "))
        XCTAssertFalse(CustomFieldInput.isNumeric("text"))
        XCTAssertFalse(CustomFieldInput.isNumeric("phone"))
        XCTAssertFalse(CustomFieldInput.isNumeric("decimal"))
        XCTAssertFalse(CustomFieldInput.isNumeric(""))
    }
}
