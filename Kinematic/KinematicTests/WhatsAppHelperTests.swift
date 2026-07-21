//
//  WhatsAppHelperTests.swift
//  KinematicTests
//
//  Phone sanitisation + wa.me deep-link construction. Does not touch
//  `open(...)` (UIApplication side effect).
//

import XCTest
@testable import Kinematic

@MainActor
final class WhatsAppHelperTests: XCTestCase {

    func testSanitizeStripsFormattingAndKeepsDigits() {
        XCTAssertEqual(WhatsAppHelper.sanitize("+91 98765 43210"), "919876543210")
        XCTAssertEqual(WhatsAppHelper.sanitize("(123) 456-78"), "12345678")
        XCTAssertEqual(WhatsAppHelper.sanitize("98.76.54.32.10"), "9876543210")
    }

    func testSanitizeRejectsTooShort() {
        XCTAssertNil(WhatsAppHelper.sanitize("1234567"))   // 7 digits
        XCTAssertNil(WhatsAppHelper.sanitize(""))
    }

    func testSanitizeRejectsNonNumeric() {
        XCTAssertNil(WhatsAppHelper.sanitize("abc1234567"))
        XCTAssertNil(WhatsAppHelper.sanitize("98765x4321"))
    }

    func testSanitizeAcceptsExactlyEightDigits() {
        XCTAssertEqual(WhatsAppHelper.sanitize("12345678"), "12345678")
    }

    func testWaLinkBuildsBareURLWithoutText() {
        let url = WhatsAppHelper.waLink(phone: "+919876543210")
        XCTAssertEqual(url?.absoluteString, "https://wa.me/919876543210")
    }

    func testWaLinkIncludesEncodedText() {
        let url = WhatsAppHelper.waLink(phone: "+919876543210", text: "Hi there")
        XCTAssertEqual(url?.absoluteString, "https://wa.me/919876543210?text=Hi%20there")
    }

    func testWaLinkOmitsBlankText() {
        let url = WhatsAppHelper.waLink(phone: "919876543210", text: "   ")
        XCTAssertEqual(url?.absoluteString, "https://wa.me/919876543210")
    }

    func testWaLinkNilForInvalidPhone() {
        XCTAssertNil(WhatsAppHelper.waLink(phone: "123"))
    }

    func testCanOpen() {
        XCTAssertTrue(WhatsAppHelper.canOpen(phone: "+919876543210"))
        XCTAssertFalse(WhatsAppHelper.canOpen(phone: "123"))
        XCTAssertFalse(WhatsAppHelper.canOpen(phone: nil))
    }
}
