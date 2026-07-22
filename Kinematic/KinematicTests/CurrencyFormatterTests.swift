//
//  CurrencyFormatterTests.swift
//  KinematicTests
//
//  INR formatting. Full-amount grouping is locale-sensitive so we assert the
//  ₹ prefix + the digits present; the compact form is deterministic so we
//  assert exact strings.
//

import XCTest
@testable import Kinematic

@MainActor
final class CurrencyFormatterTests: XCTestCase {

    private let rupee = "\u{20B9}" // ₹

    // MARK: formatINR

    func testFormatINRNilAndNonFiniteReturnZero() {
        XCTAssertEqual(CurrencyFormatter.formatINR(nil), "\(rupee)0")
        XCTAssertEqual(CurrencyFormatter.formatINR(.infinity), "\(rupee)0")
        XCTAssertEqual(CurrencyFormatter.formatINR(-.infinity), "\(rupee)0")
        XCTAssertEqual(CurrencyFormatter.formatINR(.nan), "\(rupee)0")
    }

    func testFormatINRHasRupeePrefixAndDigits() {
        let s = CurrencyFormatter.formatINR(125000)
        XCTAssertTrue(s.hasPrefix(rupee), "expected ₹ prefix, got \(s)")
        // Strip grouping separators / symbol → the raw digits must survive.
        let digits = s.filter { $0.isNumber }
        XCTAssertEqual(digits, "125000")
    }

    func testFormatINRZeroIsExact() {
        XCTAssertEqual(CurrencyFormatter.formatINR(0), "\(rupee)0")
    }

    // MARK: formatINRCompact (deterministic)

    func testCompactZeroAndNilAndNonFinite() {
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(nil), "\(rupee)0")
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(0), "\(rupee)0")
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(.infinity), "\(rupee)0")
    }

    func testCompactCrore() {
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(10_000_000), "\(rupee)1Cr")
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(25_000_000), "\(rupee)2.5Cr")
    }

    func testCompactLakh() {
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(100_000), "\(rupee)1L")
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(250_000), "\(rupee)2.5L")
    }

    func testCompactThousand() {
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(1_000), "\(rupee)1K")
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(1_500), "\(rupee)1.5K")
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(12_000), "\(rupee)12K")
    }

    func testCompactBelowThousandDelegatesToFull() {
        // Under ₹1,000 the compact form delegates to formatINR, whose grouping
        // is locale-sensitive — so assert the ₹ prefix + digits rather than an
        // exact string (there is no grouping separator below 1,000 anyway).
        let s = CurrencyFormatter.formatINRCompact(500)
        XCTAssertTrue(s.hasPrefix(rupee))
        XCTAssertEqual(s.filter { $0.isNumber }, "500")
    }

    func testCompactTrimsTrailingPointZero() {
        // 5,00,00,000 → 5.0 Cr → trimmed to "5Cr".
        XCTAssertEqual(CurrencyFormatter.formatINRCompact(50_000_000), "\(rupee)5Cr")
    }
}
