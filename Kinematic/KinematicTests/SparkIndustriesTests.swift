//
//  SparkIndustriesTests.swift
//  KinematicTests
//
//  The fixed Industry dropdown on the Spark & Ray lead create / edit forms: the exact option list, and
//  that a legacy / free-text value is carried along (once) rather than lost.
//

import XCTest
@testable import Kinematic

final class SparkIndustriesTests: XCTestCase {

    func testOptionsAreTheSevenInOrder() {
        XCTAssertEqual(SparkIndustries.options, [
            "Manufacturing",
            "Automotive",
            "Pharma & Healthcare",
            "Food & Beverage",
            "Construction & Infrastructure",
            "Power & Energy",
            "Other",
        ])
        XCTAssertEqual(SparkIndustries.options.count, 7)
    }

    func testLegacyValueIsAppendedOnce() {
        let out = SparkIndustries.pickerOptions(including: "Textiles")
        XCTAssertEqual(out, SparkIndustries.options + ["Textiles"])
        XCTAssertEqual(out.filter { $0 == "Textiles" }.count, 1)
    }

    func testBlankCurrentAddsNothing() {
        XCTAssertEqual(SparkIndustries.pickerOptions(including: ""), SparkIndustries.options)
        XCTAssertEqual(SparkIndustries.pickerOptions(including: "   "), SparkIndustries.options)
        XCTAssertEqual(SparkIndustries.pickerOptions(including: "\n\t"), SparkIndustries.options)
    }

    func testCurrentAlreadyListedIsNotDuplicated() {
        for option in SparkIndustries.options {
            let out = SparkIndustries.pickerOptions(including: option)
            XCTAssertEqual(out, SparkIndustries.options)
            XCTAssertEqual(out.filter { $0 == option }.count, 1)
        }
    }
}
