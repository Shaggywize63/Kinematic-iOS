//
//  FormRefDisplayTests.swift
//  KinematicTests
//
//  A filled form entry an expense is linked to is named by its unique reference plus the day it was filled
//  ("SRPR2627-1 · 02 Nov 2026"), with the day read in India time. Never crashes on odd input.
//

import XCTest
@testable import Kinematic

final class FormRefDisplayTests: XCTestCase {

    func testReferenceAndDateWithFractionalSeconds() {
        XCTAssertEqual(FormRefDisplay.title(refNo: "SRPR2627-1", submittedAt: "2026-11-02T10:15:30.123Z"),
                       "SRPR2627-1 · 02 Nov 2026")
    }

    func testReferenceAndDateWithoutFractionalSeconds() {
        XCTAssertEqual(FormRefDisplay.title(refNo: "SRPR2627-12", submittedAt: "2026-11-02T10:15:30Z"),
                       "SRPR2627-12 · 02 Nov 2026")
    }

    func testAUtcTimeThatIsTheNextDayInIndiaShowsTheIndianDay() {
        XCTAssertEqual(FormRefDisplay.title(refNo: "SRPR2627-3", submittedAt: "2026-11-02T20:00:00Z"),
                       "SRPR2627-3 · 03 Nov 2026")
        XCTAssertEqual(FormRefDisplay.title(refNo: "SRPR2627-3", submittedAt: "2026-11-02T20:00:00.000Z"),
                       "SRPR2627-3 · 03 Nov 2026")
    }

    func testAnExplicitOffsetIsHonoured() {
        XCTAssertEqual(FormRefDisplay.title(refNo: "A-1", submittedAt: "2026-11-02T23:30:00+05:30"), "A-1 · 02 Nov 2026")
    }

    func testNilOrBlankReferenceGivesJustTheDate() {
        XCTAssertEqual(FormRefDisplay.title(refNo: nil, submittedAt: "2026-11-02T10:00:00Z"), "02 Nov 2026")
        XCTAssertEqual(FormRefDisplay.title(refNo: "   ", submittedAt: "2026-11-02T10:00:00Z"), "02 Nov 2026")
    }

    func testNilOrBlankDateGivesJustTheReference() {
        XCTAssertEqual(FormRefDisplay.title(refNo: "SRPR2627-1", submittedAt: nil), "SRPR2627-1")
        XCTAssertEqual(FormRefDisplay.title(refNo: "SRPR2627-1", submittedAt: "  "), "SRPR2627-1")
    }

    func testNothingAtAllGivesAnEmptyString() {
        XCTAssertEqual(FormRefDisplay.title(refNo: nil, submittedAt: nil), "")
    }

    func testAnUnparseableDateFallsBackToItsFirstTenCharacters() {
        XCTAssertEqual(FormRefDisplay.title(refNo: "SRPR2627-1", submittedAt: "not-a-date-at-all"), "SRPR2627-1 · not-a-date")
        XCTAssertEqual(FormRefDisplay.title(refNo: "SRPR2627-1", submittedAt: "oops"), "SRPR2627-1 · oops")
        XCTAssertEqual(FormRefDisplay.title(refNo: nil, submittedAt: "garbage"), "garbage")
    }
}
