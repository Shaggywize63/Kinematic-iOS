//
//  SampleInvoicesTests.swift
//  KinematicTests
//
//  Sample invoices on a lead (Spark & Ray): the pure helper that normalises the
//  list, reads it out of `custom_fields`, adds / removes a number, and builds the
//  `custom_fields` PATCH that preserves every other custom-field key.
//

import XCTest
import Foundation
@testable import Kinematic

final class SampleInvoicesTests: XCTestCase {

    private func lead(customFieldsJSON: String? = nil) throws -> Lead {
        var json = #"{"id":"L1""#
        if let cf = customFieldsJSON { json += #","custom_fields":"# + cf }
        json += "}"
        return try JSONDecoder().decode(Lead.self, from: Data(json.utf8))
    }

    // MARK: Normalise

    func testNormalizeTrimsDropsBlanksAndDedupes() {
        let out = SampleInvoices.normalize(["  INV-1 ", "", "   ", "INV-2", "INV-1"])
        XCTAssertEqual(out, ["INV-1", "INV-2"])
    }

    func testNormalizeDedupesCaseInsensitivelyKeepingFirstText() {
        let out = SampleInvoices.normalize(["inv-1", "INV-1", "Inv-1"])
        XCTAssertEqual(out, ["inv-1"])
    }

    func testNormalizePreservesOrder() {
        XCTAssertEqual(SampleInvoices.normalize(["C", "A", "B", "A"]), ["C", "A", "B"])
    }

    func testNormalizeEmpty() {
        XCTAssertEqual(SampleInvoices.normalize([]), [])
        XCTAssertEqual(SampleInvoices.normalize(["", "  "]), [])
    }

    // MARK: Read

    func testReadFromCustomFieldsStringArray() {
        let cf: [String: Any] = ["sample_invoices": ["INV-1", " INV-2 ", "", "INV-1"]]
        XCTAssertEqual(SampleInvoices.read(customFields: cf), ["INV-1", "INV-2"])
    }

    func testReadCoercesNumbersToStrings() {
        let cf: [String: Any] = ["sample_invoices": [1001, 1002.0, "INV-3"]]
        XCTAssertEqual(SampleInvoices.read(customFields: cf), ["1001", "1002", "INV-3"])
    }

    func testReadMissingOrWrongShapeIsEmpty() {
        XCTAssertEqual(SampleInvoices.read(customFields: nil), [])
        XCTAssertEqual(SampleInvoices.read(customFields: [:]), [])
        XCTAssertEqual(SampleInvoices.read(customFields: ["sample_invoices": "not-an-array"]), [])
        XCTAssertEqual(SampleInvoices.read(customFields: ["other": ["X"]]), [])
    }

    func testReadFromLeadDecodedJSON() throws {
        let l = try lead(customFieldsJSON: #"{"sample_invoices":["INV-1","INV-2"],"industry_note":"steel"}"#)
        XCTAssertEqual(SampleInvoices.read(from: l), ["INV-1", "INV-2"])
    }

    func testReadFromLeadWithNoCustomFields() throws {
        XCTAssertEqual(SampleInvoices.read(from: try lead()), [])
    }

    // MARK: Add / remove

    func testAdding() {
        XCTAssertEqual(SampleInvoices.adding("INV-2", to: ["INV-1"]), ["INV-1", "INV-2"])
        XCTAssertEqual(SampleInvoices.adding("  INV-3  ", to: ["INV-1"]), ["INV-1", "INV-3"])
    }

    func testAddingBlankIsNoOp() {
        XCTAssertEqual(SampleInvoices.adding("   ", to: ["INV-1"]), ["INV-1"])
        XCTAssertEqual(SampleInvoices.adding("", to: []), [])
    }

    func testAddingDuplicateIsNoOp() {
        XCTAssertEqual(SampleInvoices.adding("inv-1", to: ["INV-1"]), ["INV-1"])
    }

    func testRemoving() {
        XCTAssertEqual(SampleInvoices.removing("INV-1", from: ["INV-1", "INV-2"]), ["INV-2"])
    }

    func testRemovingIsCaseInsensitiveAndTrimmed() {
        XCTAssertEqual(SampleInvoices.removing("  inv-1 ", from: ["INV-1", "INV-2"]), ["INV-2"])
    }

    func testRemovingUnknownLeavesListUnchanged() {
        XCTAssertEqual(SampleInvoices.removing("INV-9", from: ["INV-1", "INV-2"]), ["INV-1", "INV-2"])
    }

    func testRemovingBlankLeavesNormalisedList() {
        XCTAssertEqual(SampleInvoices.removing("", from: ["INV-1", " INV-1 ", "INV-2"]), ["INV-1", "INV-2"])
    }

    // MARK: Patch (custom_fields)

    func testPatchSetsNormalisedList() {
        let patch = SampleInvoices.patch(customFields: [:], invoices: [" INV-1 ", "INV-1", "INV-2"])
        XCTAssertEqual(patch["sample_invoices"] as? [String], ["INV-1", "INV-2"])
    }

    func testPatchPreservesOtherKeys() {
        let existing: [String: Any] = [
            "sample_invoices": ["OLD"],
            "industry_note": "steel",
            "product_lines": [["product_id": "p1", "quantity": 2]],
        ]
        let patch = SampleInvoices.patch(customFields: existing, invoices: ["INV-1"])
        XCTAssertEqual(patch["sample_invoices"] as? [String], ["INV-1"])
        XCTAssertEqual(patch["industry_note"] as? String, "steel")
        XCTAssertNotNil(patch["product_lines"] as? [[String: Any]])
        XCTAssertEqual((patch["product_lines"] as? [[String: Any]])?.count, 1)
    }

    func testPatchEmptyListClearsToEmptyArray() {
        let patch = SampleInvoices.patch(customFields: ["sample_invoices": ["OLD"]], invoices: [])
        XCTAssertEqual(patch["sample_invoices"] as? [String], [])
    }

    func testPatchSerialisesAsJSON() throws {
        let patch = SampleInvoices.patch(customFields: ["keep": "me"], invoices: ["INV-1", "INV-2"])
        let data = try JSONSerialization.data(withJSONObject: patch)
        let back = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(back?["sample_invoices"] as? [String], ["INV-1", "INV-2"])
        XCTAssertEqual(back?["keep"] as? String, "me")
    }

    // MARK: Update body (whole lead PATCH payload)

    func testUpdateBodyWrapsCustomFieldsAndPreservesKeys() throws {
        let l = try lead(customFieldsJSON: #"{"sample_invoices":["OLD"],"industry_note":"steel"}"#)
        let body = SampleInvoices.updateBody(for: l, invoices: ["INV-1", "INV-2"])
        let cf = body["custom_fields"] as? [String: Any]
        XCTAssertNotNil(cf)
        XCTAssertEqual(cf?["sample_invoices"] as? [String], ["INV-1", "INV-2"])
        XCTAssertEqual(cf?["industry_note"] as? String, "steel")
        // No top-level built-in field leaks into the body — only custom_fields is sent.
        XCTAssertEqual(Array(body.keys), ["custom_fields"])
    }

    // MARK: Add-then-remove round trip against a lead's stored list

    func testRoundTripAddAndRemove() throws {
        let l = try lead(customFieldsJSON: #"{"sample_invoices":["INV-1"]}"#)
        var list = SampleInvoices.read(from: l)
        XCTAssertEqual(list, ["INV-1"])
        list = SampleInvoices.adding("INV-2", to: list)
        list = SampleInvoices.adding("inv-2", to: list)   // duplicate — ignored
        XCTAssertEqual(list, ["INV-1", "INV-2"])
        list = SampleInvoices.removing("INV-1", from: list)
        XCTAssertEqual(list, ["INV-2"])
        let body = SampleInvoices.updateBody(for: l, invoices: list)
        let cf = body["custom_fields"] as? [String: Any]
        XCTAssertEqual(cf?["sample_invoices"] as? [String], ["INV-2"])
    }

    // MARK: Field key is the custom_fields jsonb key (NOT a built-in column)

    func testFieldKey() {
        XCTAssertEqual(SampleInvoices.fieldKey, "sample_invoices")
    }
}
