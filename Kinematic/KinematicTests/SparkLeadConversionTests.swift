//
//  SparkLeadConversionTests.swift
//  KinematicTests
//
//  Spark & Ray lead -> deal conversion through the normal deal form: the `convert_lead` flag in the request
//  body (only when converting and a lead id is present), the "Company — Contact" deal-name prefill, the note
//  and title, and that a plain "New deal" from a lead never carries the flag.
//

import XCTest
import Foundation
@testable import Kinematic

final class SparkLeadConversionTests: XCTestCase {

    private func lead(_ json: String) throws -> Lead {
        try JSONDecoder().decode(Lead.self, from: Data(json.utf8))
    }

    // MARK: - convert flag in the request body

    func testConvertingSendsConvertLeadTrueWithTheNormalDealBody() {
        var body: [String: Any] = ["name": "Acme \u{2014} Ravi", "amount": 0, "status": "open"]
        SparkDealBody.apply(to: &body, accountId: nil, leadId: "lead-1", quotationNo: "", lines: [])
        SparkLeadConversion.applyConversion(to: &body, convert: true, leadId: "lead-1")
        XCTAssertEqual(body["convert_lead"] as? Bool, true)
        XCTAssertEqual(body["lead_id"] as? String, "lead-1")
        // The rest of the deal body is untouched.
        XCTAssertEqual(body["name"] as? String, "Acme \u{2014} Ravi")
        XCTAssertEqual(body["status"] as? String, "open")
    }

    func testPlainNewDealFromALeadNeverCarriesTheFlag() {
        var body: [String: Any] = ["name": "Deal"]
        SparkDealBody.apply(to: &body, accountId: nil, leadId: "lead-1", quotationNo: "", lines: [])
        SparkLeadConversion.applyConversion(to: &body, convert: false, leadId: "lead-1")
        XCTAssertNil(body["convert_lead"])
        XCTAssertEqual(body["lead_id"] as? String, "lead-1")
    }

    func testTheFlagNeedsALeadId() {
        var body: [String: Any] = [:]
        SparkLeadConversion.applyConversion(to: &body, convert: true, leadId: nil)
        SparkLeadConversion.applyConversion(to: &body, convert: true, leadId: "  ")
        XCTAssertNil(body["convert_lead"])
    }

    func testBodyKeyMatchesTheBackendContract() {
        XCTAssertEqual(SparkLeadConversion.bodyKey, "convert_lead")
    }

    func testAnAlreadyConvertedLeadIsNotConvertedAgain() {
        XCTAssertTrue(SparkLeadConversion.shouldConvert(requested: true, leadAlreadyConverted: false))
        XCTAssertFalse(SparkLeadConversion.shouldConvert(requested: true, leadAlreadyConverted: true))
        XCTAssertFalse(SparkLeadConversion.shouldConvert(requested: false, leadAlreadyConverted: false))
        XCTAssertFalse(SparkLeadConversion.shouldConvert(requested: false, leadAlreadyConverted: true))
    }

    func testKnownContactStillRidesAlongWithTheConversionBody() {
        var body: [String: Any] = [:]
        SparkDealBody.apply(to: &body, accountId: "acc-1", leadId: "lead-1", primaryContactId: "c-1", quotationNo: "", lines: [])
        SparkLeadConversion.applyConversion(to: &body, convert: false, leadId: "lead-1")
        XCTAssertEqual(body["account_id"] as? String, "acc-1")
        XCTAssertEqual(body["primary_contact_id"] as? String, "c-1")
        XCTAssertNil(body["convert_lead"])
    }

    // MARK: - deal-name prefill

    func testDealNameIsCompanyDashContact() {
        XCTAssertEqual(
            SparkLeadConversion.defaultDealName(company: "Acme Steel", contactName: "Ravi Kumar"),
            "Acme Steel \u{2014} Ravi Kumar"
        )
    }

    func testDealNameFallsBackToWhicheverPartExists() {
        XCTAssertEqual(SparkLeadConversion.defaultDealName(company: "Acme Steel", contactName: nil), "Acme Steel")
        XCTAssertEqual(SparkLeadConversion.defaultDealName(company: "  ", contactName: "Ravi Kumar"), "Ravi Kumar")
        XCTAssertEqual(SparkLeadConversion.defaultDealName(company: nil, contactName: nil, fallback: "Unnamed Lead"), "Unnamed Lead")
        XCTAssertEqual(SparkLeadConversion.defaultDealName(company: nil, contactName: nil), "")
    }

    func testDealNameDoesNotRepeatTheSameText() {
        XCTAssertEqual(SparkLeadConversion.defaultDealName(company: "Ravi Kumar", contactName: "ravi kumar"), "Ravi Kumar")
    }

    func testDealNameTrimsWhitespace() {
        XCTAssertEqual(
            SparkLeadConversion.defaultDealName(company: "  Acme ", contactName: " Ravi\n"),
            "Acme \u{2014} Ravi"
        )
    }

    func testContactNameJoinsFirstAndLast() {
        XCTAssertEqual(SparkLeadConversion.contactName(firstName: "Ravi", lastName: "Kumar"), "Ravi Kumar")
        XCTAssertEqual(SparkLeadConversion.contactName(firstName: "Ravi", lastName: nil), "Ravi")
        XCTAssertEqual(SparkLeadConversion.contactName(firstName: nil, lastName: " Kumar "), "Kumar")
        XCTAssertNil(SparkLeadConversion.contactName(firstName: " ", lastName: nil))
    }

    func testDealNameForALead() throws {
        let full = try lead(#"{"id":"l1","first_name":"Ravi","last_name":"Kumar","company":"Acme Steel"}"#)
        XCTAssertEqual(SparkLeadConversion.defaultDealName(for: full), "Acme Steel \u{2014} Ravi Kumar")

        let noCompany = try lead(#"{"id":"l2","first_name":"Ravi","last_name":"Kumar"}"#)
        XCTAssertEqual(SparkLeadConversion.defaultDealName(for: noCompany), "Ravi Kumar")

        let emailOnly = try lead(#"{"id":"l3","email":"ravi@acme.com"}"#)
        XCTAssertEqual(SparkLeadConversion.defaultDealName(for: emailOnly), "ravi@acme.com")
    }

    // MARK: - note + title

    func testConversionNameAndNote() {
        XCTAssertEqual(
            SparkLeadConversion.note(leadName: "Ravi Kumar"),
            "Converting Ravi Kumar \u{2014} this creates or links the customer account."
        )
        XCTAssertEqual(
            SparkLeadConversion.note(leadName: nil),
            "Converting this lead \u{2014} this creates or links the customer account."
        )
    }

    func testFormTitle() {
        XCTAssertEqual(SparkLeadConversion.formTitle(converting: true), "Convert to Deal")
        XCTAssertEqual(SparkLeadConversion.formTitle(converting: false), "New Deal")
    }
}
