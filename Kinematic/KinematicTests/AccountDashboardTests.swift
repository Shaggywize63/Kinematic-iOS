//
//  AccountDashboardTests.swift
//  KinematicTests
//
//  Pure-logic cover for the reworked account screens (mirrors web PR #668 + backend #676):
//    • the POST /crm/accounts 409 duplicate decode,
//    • the account-detail value stats + product rollup from the account's deals,
//    • the account-detail Leads card's display name / value.
//

import XCTest
@testable import Kinematic

final class AccountDashboardTests: XCTestCase {

    private func deal(_ json: String) throws -> Deal {
        try JSONDecoder().decode(Deal.self, from: Data(json.utf8))
    }
    private func lead(_ json: String) throws -> Lead {
        try JSONDecoder().decode(Lead.self, from: Data(json.utf8))
    }

    // MARK: - 409 duplicate

    func testParseValidDuplicate() {
        let body = Data(#"{"success":false,"error":"exists","code":"DUPLICATE_ACCOUNT","existing":{"id":"acc-9","name":"Acme Steel"}}"#.utf8)
        let dup = AccountDuplicate.parse(body)
        XCTAssertEqual(dup, AccountDuplicateInfo(id: "acc-9", name: "Acme Steel"))
    }

    func testParseIgnoresWrongCode() {
        let body = Data(#"{"success":false,"code":"VALIDATION","existing":{"id":"x","name":"Y"}}"#.utf8)
        XCTAssertNil(AccountDuplicate.parse(body))
    }

    func testParseIgnoresMissingId() {
        let body = Data(#"{"code":"DUPLICATE_ACCOUNT","existing":{"name":"No id"}}"#.utf8)
        XCTAssertNil(AccountDuplicate.parse(body))
    }

    func testParseIgnoresGenericError() {
        // A plain non-duplicate 4xx body is never read as a duplicate.
        XCTAssertNil(AccountDuplicate.parse(Data(#"{"success":false,"error":"bad request"}"#.utf8)))
        XCTAssertNil(AccountDuplicate.parse(Data("not json".utf8)))
    }

    func testInfoGate() {
        XCTAssertNil(AccountDuplicate.info(code: "OTHER", id: "a", name: "b"))
        XCTAssertNil(AccountDuplicate.info(code: "DUPLICATE_ACCOUNT", id: "   ", name: "b"))
        XCTAssertEqual(AccountDuplicate.info(code: "DUPLICATE_ACCOUNT", id: " a ", name: " b "),
                       AccountDuplicateInfo(id: "a", name: "b"))
    }

    func testDuplicateMessageFallsBackToTypedName() {
        let noName = AccountDuplicateInfo(id: "a", name: "")
        XCTAssertEqual(AccountDuplicate.message(for: noName, fallbackName: "  Tata  "),
                       "An account named \"Tata\" already exists.")
        let withName = AccountDuplicateInfo(id: "a", name: "Acme")
        XCTAssertEqual(AccountDuplicate.message(for: withName, fallbackName: "ignored"),
                       "An account named \"Acme\" already exists.")
    }

    // MARK: - Value stats

    func testValueStatsTotalOpenWon() throws {
        let deals = [
            // open: dealValue = quoted_amount (200)
            try deal(#"{"id":"d1","name":"A","status":"open","amount":50,"quoted_amount":200}"#),
            // won: dealValue = quoted(300) for total; won = order_amount(250)
            try deal(#"{"id":"d2","name":"B","status":"won","amount":120,"quoted_amount":300,"order_amount":250}"#),
            // won with no quote/order: dealValue = amount(80); won = amount(80)
            try deal(#"{"id":"d3","name":"C","status":"won","amount":80}"#),
            // lost: counts toward Total only
            try deal(#"{"id":"d4","name":"D","status":"lost","amount":40}"#),
        ]
        let s = AccountDealRollup.valueStats(deals)
        XCTAssertEqual(s.total, 200 + 300 + 80 + 40, accuracy: 0.001)
        XCTAssertEqual(s.openPipeline, 200, accuracy: 0.001)
        XCTAssertEqual(s.won, 250 + 80, accuracy: 0.001)
    }

    func testValueStatsEmpty() {
        let s = AccountDealRollup.valueStats([])
        XCTAssertEqual(s.total, 0)
        XCTAssertEqual(s.openPipeline, 0)
        XCTAssertEqual(s.won, 0)
    }

    // MARK: - Product rollup

    func testProductRollupFromProductLinesResolvesNames() throws {
        let deals = [
            try deal(#"{"id":"d1","name":"A","custom_fields":{"product_lines":[{"product_id":"p1","estimated_amount":100},{"product_id":"p2","estimated_amount":40}]}}"#),
            try deal(#"{"id":"d2","name":"B","custom_fields":{"product_lines":[{"product_id":"p1","estimated_amount":50}]}}"#),
        ]
        let names = ["p1": "TMT Bars", "p2": "Cement"]
        let rows = AccountDealRollup.products(deals) { names[$0] }
        // p1 summed to 150, p2 to 40; sorted by value desc.
        XCTAssertEqual(rows.map { $0.name }, ["TMT Bars", "Cement"])
        XCTAssertEqual(rows.first?.value, 150, accuracy: 0.001)
        XCTAssertEqual(rows.last?.value, 40, accuracy: 0.001)
    }

    func testProductRollupReadsLineItemsAndOrderValue() throws {
        // The conversion-stamped `line_items` shape with product_name + order_value.
        let deals = [
            try deal(#"{"id":"d1","name":"A","custom_fields":{"line_items":[{"product_name":"Wire Rod","order_value":500,"subtotal":450}]}}"#),
        ]
        let rows = AccountDealRollup.products(deals)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "Wire Rod")
        XCTAssertEqual(rows.first?.value, 500, accuracy: 0.001)  // order_value preferred over subtotal
    }

    func testProductRollupEmptyWhenNoLines() throws {
        let deals = [try deal(#"{"id":"d1","name":"A","custom_fields":{"volume_kg":10}}"#),
                     try deal(#"{"id":"d2","name":"B"}"#)]
        XCTAssertTrue(AccountDealRollup.products(deals).isEmpty)
    }

    func testProductRollupFallsBackToIdWhenUnresolved() throws {
        let deals = [try deal(#"{"id":"d1","name":"A","custom_fields":{"product_lines":[{"product_id":"p9","estimated_amount":10}]}}"#)]
        let rows = AccountDealRollup.products(deals) { _ in nil }
        XCTAssertEqual(rows.first?.name, "p9")
    }

    // MARK: - Leads card

    func testLeadDisplayNamePrefersFullNameThenCompanyThenEmail() throws {
        XCTAssertEqual(AccountLeadDisplay.name(try lead(#"{"id":"l1","first_name":"Ravi","last_name":"K"}"#)), "Ravi K")
        XCTAssertEqual(AccountLeadDisplay.name(try lead(#"{"id":"l2","company":"Acme"}"#)), "Acme")
        XCTAssertEqual(AccountLeadDisplay.name(try lead(#"{"id":"l3","email":"a@b.com"}"#)), "a@b.com")
        XCTAssertEqual(AccountLeadDisplay.name(try lead(#"{"id":"l4"}"#)), "Lead")
    }

    func testLeadValueFromCustomFields() throws {
        XCTAssertEqual(AccountLeadValue.value(try lead(#"{"id":"l1","custom_fields":{"deal_value":1500}}"#)), 1500)
        XCTAssertEqual(AccountLeadValue.value(try lead(#"{"id":"l2","custom_fields":{"budget":"2500"}}"#)), 2500)
        // No recognisable positive value → nil (never fabricated).
        XCTAssertNil(AccountLeadValue.value(try lead(#"{"id":"l3","custom_fields":{"deal_value":0}}"#)))
        XCTAssertNil(AccountLeadValue.value(try lead(#"{"id":"l4"}"#)))
    }
}
