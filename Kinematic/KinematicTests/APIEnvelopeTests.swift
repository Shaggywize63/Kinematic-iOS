//
//  APIEnvelopeTests.swift
//  KinematicTests
//
//  The API envelope must tolerate `error` as EITHER a plain string OR a
//  `{ code, message }` object (the KINI 429 / RBAC path) without throwing.
//

import XCTest
@testable import Kinematic

@MainActor
final class APIEnvelopeTests: XCTestCase {

    private struct Payload: Codable, Equatable {
        let name: String
        let qty: Int
    }

    private func decode(_ json: String) throws -> APIEnvelope<Payload> {
        try JSONDecoder().decode(APIEnvelope<Payload>.self, from: Data(json.utf8))
    }

    func testDecodesSuccessWithDataAndPagination() throws {
        let env = try decode("""
        {"success": true,
         "data": {"name": "Widget", "qty": 3},
         "pagination": {"total": 10, "page": 1, "limit": 20, "totalPages": 1}}
        """)
        XCTAssertEqual(env.success, true)
        XCTAssertEqual(env.data, Payload(name: "Widget", qty: 3))
        XCTAssertNil(env.error)
        XCTAssertEqual(env.pagination?.total, 10)
        XCTAssertEqual(env.pagination?.totalPages, 1)
    }

    func testDecodesErrorAsPlainString() throws {
        let env = try decode(#"{"success": false, "error": "boom"}"#)
        XCTAssertEqual(env.success, false)
        XCTAssertNil(env.data)
        XCTAssertEqual(env.error, "boom")
    }

    func testDecodesErrorAsObjectAndNormalisesToMessage() throws {
        let env = try decode("""
        {"success": false, "error": {"code": "KINI_429", "message": "Quota exceeded"}}
        """)
        XCTAssertEqual(env.success, false)
        XCTAssertEqual(env.error, "Quota exceeded")
    }

    func testDecodesBareDataWithoutSuccessFlag() throws {
        // Older routes returned `{ data }` with no explicit success flag.
        let env = try decode(#"{"data": {"name": "x", "qty": 1}}"#)
        XCTAssertNil(env.success)
        XCTAssertEqual(env.data?.name, "x")
        XCTAssertNil(env.error)
    }

    func testDecodesMessageAndNoError() throws {
        let env = try decode(#"{"success": true, "data": {"name": "x", "qty": 1}, "message": "ok"}"#)
        XCTAssertEqual(env.message, "ok")
        XCTAssertNil(env.error)
    }

    func testEncodeThenDecodeRoundTrip() throws {
        let env = try decode(#"{"success": true, "data": {"name": "z", "qty": 9}, "error": "e"}"#)
        let data = try JSONEncoder().encode(env)
        let again = try JSONDecoder().decode(APIEnvelope<Payload>.self, from: data)
        XCTAssertEqual(again.success, true)
        XCTAssertEqual(again.data, Payload(name: "z", qty: 9))
        XCTAssertEqual(again.error, "e")
    }
}
