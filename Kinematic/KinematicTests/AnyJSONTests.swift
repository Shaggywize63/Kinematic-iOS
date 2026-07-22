//
//  AnyJSONTests.swift
//  KinematicTests
//
//  Covers the typed-JSON box used by `custom_fields` / planogram payloads:
//  Bool-before-number probing, integral-Double round-trip via `.any`, and
//  nested container decoding.
//

import XCTest
@testable import Kinematic

@MainActor
final class AnyJSONTests: XCTestCase {

    // Wrap fragments in an object so we never rely on top-level-fragment
    // decoding support.
    private func decodeMap(_ json: String) throws -> [String: AnyJSON] {
        try JSONDecoder().decode([String: AnyJSON].self, from: Data(json.utf8))
    }

    func testBoolDecodesAsBoolNotNumber() throws {
        let map = try decodeMap(#"{"flag": true, "off": false}"#)
        XCTAssertEqual(map["flag"], .bool(true))
        XCTAssertEqual(map["off"], .bool(false))
        // Must NOT collapse to a number.
        XCTAssertNotEqual(map["flag"], .number(1))
    }

    func testIntegerAndDoubleAndStringAndNull() throws {
        let map = try decodeMap(#"{"count": 1, "ratio": 2.5, "name": "hi", "nothing": null}"#)
        XCTAssertEqual(map["count"], .number(1))
        XCTAssertEqual(map["ratio"], .number(2.5))
        XCTAssertEqual(map["name"], .string("hi"))
        XCTAssertEqual(map["nothing"], .null)
    }

    func testNestedObjectAndArray() throws {
        let map = try decodeMap(#"{"obj": {"k": 3.5, "b": false}, "arr": [1, "two", null]}"#)
        XCTAssertEqual(map["obj"], .object(["k": .number(3.5), "b": .bool(false)]))
        XCTAssertEqual(map["arr"], .array([.number(1), .string("two"), .null]))
    }

    func testAnyReEmitsIntegralDoubleAsInt() {
        XCTAssertEqual(AnyJSON.number(2.0).any as? Int, 2)
        XCTAssertEqual(AnyJSON.number(-7.0).any as? Int, -7)
        // Non-integral stays a Double.
        XCTAssertEqual(AnyJSON.number(2.5).any as? Double, 2.5)
    }

    func testAnyForScalarsAndContainers() {
        XCTAssertTrue(AnyJSON.null.any is NSNull)
        XCTAssertEqual(AnyJSON.bool(true).any as? Bool, true)
        XCTAssertEqual(AnyJSON.string("x").any as? String, "x")

        let arr = AnyJSON.array([.number(1.0), .string("a")]).any as? [Any]
        XCTAssertEqual(arr?.count, 2)
        XCTAssertEqual(arr?.first as? Int, 1)

        let obj = AnyJSON.object(["n": .number(4.0)]).any as? [String: Any]
        XCTAssertEqual(obj?["n"] as? Int, 4)
    }

    func testEncodeDecodeRoundTripPreservesCases() throws {
        let original: [String: AnyJSON] = [
            "b": .bool(true),
            "i": .number(3),
            "d": .number(1.25),
            "s": .string("hello"),
            "n": .null,
            "a": .array([.number(1), .bool(false)]),
            "o": .object(["x": .string("y")]),
        ]
        let data = try JSONEncoder().encode(original)
        let round = try JSONDecoder().decode([String: AnyJSON].self, from: data)
        XCTAssertEqual(original, round)
    }
}
