//
//  DealLineDetailsTests.swift
//  KinematicTests
//
//  Connected-B2B deal lines: make, brand, product reference, quoted / order value and the MAC funnel
//  reference. Covers the lenient wire models (line, product, deal roll-up, make / brand options), the MAC
//  rule, the create / patch request bodies, the totals and header texts, the read-only detail rows and the
//  "confirm the ordered value" step of the Won flow.
//

import XCTest
import Foundation
@testable import Kinematic

final class DealLineDetailsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func deal(_ extra: String = "") throws -> Deal {
        try decode(Deal.self, #"{"id":"D1","name":"Plant A""# + extra + "}")
    }

    private func line(
        _ id: String = "L1", name: String = "Valve", qty: Double = 1, price: Double = 100,
        total: Double? = nil, order: Double? = nil,
        brand: String? = nil, funnel: String? = nil
    ) -> DealLineItem {
        DealLineItem(id: id, productName: name, quantity: qty, unitPrice: price, lineTotal: total,
                     brandName: brand, funnelRef: funnel, orderValue: order)
    }

    // MARK: - Wire models

    func testLineDecodesTheNewFields() throws {
        let l = try decode(DealLineItem.self, """
        {"id":"L1","deal_id":"D1","product_id":"P1","product_name":"Gate valve","sku":"13280",
         "quantity":3,"unit_price":100,"line_total":300,"reference":"13280",
         "make_id":"M1","brand_id":"B1","make_name":"MAC Valves","brand_name":"MAC",
         "funnel_ref":"F-77","order_value":250}
        """)
        XCTAssertEqual(l.reference, "13280")
        XCTAssertEqual(l.makeId, "M1")
        XCTAssertEqual(l.brandId, "B1")
        XCTAssertEqual(l.makeName, "MAC Valves")
        XCTAssertEqual(l.brandName, "MAC")
        XCTAssertEqual(l.funnelRef, "F-77")
        XCTAssertEqual(l.orderValue, 250)
        XCTAssertEqual(l.lineTotal, 300)
    }

    func testOldLineWithoutTheNewKeysStillDecodes() throws {
        let l = try decode(DealLineItem.self,
            #"{"id":"L1","deal_id":"D1","product_name":"Seal","quantity":2,"unit_price":10}"#)
        XCTAssertEqual(l.productName, "Seal")
        XCTAssertNil(l.reference)
        XCTAssertNil(l.makeId)
        XCTAssertNil(l.brandName)
        XCTAssertNil(l.funnelRef)
        XCTAssertNil(l.orderValue)
    }

    func testLineDecodingIsLenientAboutNumbersAndNulls() throws {
        let l = try decode(DealLineItem.self, """
        {"id":"L1","product_name":"Seal","quantity":"2","unit_price":"10.50","line_total":"21",
         "order_value":"1,200.5","make_id":null,"funnel_ref":null}
        """)
        XCTAssertEqual(l.quantity, 2)
        XCTAssertEqual(l.unitPrice, 10.5)
        XCTAssertEqual(l.lineTotal, 21)
        XCTAssertEqual(l.orderValue, 1200.5)
        XCTAssertNil(l.makeId)
        XCTAssertNil(l.funnelRef)
        let junk = try decode(DealLineItem.self, #"{"id":"L2","order_value":"abc"}"#)
        XCTAssertNil(junk.orderValue)
    }

    func testProductDecodesMakeAndBrand() throws {
        let p = try decode(Product.self,
            #"{"id":"p1","name":"Gate valve","sku":"13280","make_id":"M1","brand_id":"B1","make_name":"MAC Valves","brand_name":"MAC"}"#)
        XCTAssertEqual(p.makeId, "M1")
        XCTAssertEqual(p.brandId, "B1")
        XCTAssertEqual(p.makeName, "MAC Valves")
        XCTAssertEqual(p.brandName, "MAC")
        let plain = try decode(Product.self, #"{"id":"p2","name":"Seal"}"#)
        XCTAssertNil(plain.makeId)
        XCTAssertNil(plain.brandName)
    }

    func testMakeAndBrandOptionsDecode() throws {
        let rows = try decode([LineOption].self, #"[{"id":"1","name":"PHD"},{"id":2,"name":"BEKO","is_active":true}]"#)
        XCTAssertEqual(rows.map { $0.id }, ["1", "2"])
        XCTAssertEqual(rows.map { $0.name }, ["PHD", "BEKO"])
    }

    func testDealDecodesTheLineRollup() throws {
        let d = try deal(#","line_count":3,"quoted_amount":1500.5,"order_amount":1200,"brands":["MAC","PHD"]"#)
        XCTAssertEqual(d.lineCount, 3)
        XCTAssertEqual(d.quotedAmount, 1500.5)
        XCTAssertEqual(d.orderAmount, 1200)
        XCTAssertEqual(d.brands ?? [], ["MAC", "PHD"])
    }

    func testDealWithoutTheRollupDecodesToNil() throws {
        let d = try deal()
        XCTAssertNil(d.lineCount)
        XCTAssertNil(d.quotedAmount)
        XCTAssertNil(d.orderAmount)
        XCTAssertNil(d.brands)
    }

    func testDealRollupIsLenient() throws {
        let strings = try deal(##","line_count":"2","quoted_amount":"900.25","order_amount":null,"brands":"MAC, PHD""##)
        XCTAssertEqual(strings.lineCount, 2)
        XCTAssertEqual(strings.quotedAmount, 900.25)
        XCTAssertNil(strings.orderAmount)
        XCTAssertEqual(strings.brands ?? [], ["MAC", "PHD"])

        // A surprising shape never fails the whole deal.
        let odd = try deal(#","line_count":{"n":1},"quoted_amount":[1],"order_amount":true,"brands":[1,"BEKO",{"a":1}]"#)
        XCTAssertEqual(odd.name, "Plant A")
        XCTAssertNil(odd.lineCount)
        XCTAssertNil(odd.quotedAmount)
        XCTAssertEqual(odd.brands ?? [], ["BEKO"])
    }

    // MARK: - MAC rule

    func testMacBrandIsTrimmedAndCaseInsensitive() {
        XCTAssertTrue(DealLineRules.isMacBrand("MAC"))
        XCTAssertTrue(DealLineRules.isMacBrand("mac"))
        XCTAssertTrue(DealLineRules.isMacBrand("  Mac \n"))
        XCTAssertFalse(DealLineRules.isMacBrand("MAC Valves"))
        XCTAssertFalse(DealLineRules.isMacBrand("PHD"))
        XCTAssertFalse(DealLineRules.isMacBrand(""))
        XCTAssertFalse(DealLineRules.isMacBrand(nil))
    }

    func testMacRequiresAFunnelReferenceAndOthersDoNot() {
        let msg = "MAC funnel reference is required for MAC products"
        XCTAssertEqual(DealLineRules.funnelProblem(brandName: "MAC", funnelRef: ""), msg)
        XCTAssertEqual(DealLineRules.funnelProblem(brandName: " mac ", funnelRef: "   "), msg)
        XCTAssertEqual(DealLineRules.funnelProblem(brandName: "MAC", funnelRef: nil), msg)
        XCTAssertNil(DealLineRules.funnelProblem(brandName: "MAC", funnelRef: " F-1 "))
        XCTAssertNil(DealLineRules.funnelProblem(brandName: "PHD", funnelRef: ""))
        XCTAssertNil(DealLineRules.funnelProblem(brandName: nil, funnelRef: nil))
        XCTAssertEqual(DealLineRules.macFunnelRequiredMessage, msg)
    }

    func testOrderValueRule() {
        XCTAssertNil(DealLineRules.orderValue(from: ""))
        XCTAssertNil(DealLineRules.orderValue(from: "-5"))
        XCTAssertNil(DealLineRules.orderValue(from: "abc"))
        XCTAssertEqual(DealLineRules.orderValue(from: " 1,250.5 "), 1250.5)
        XCTAssertEqual(DealLineRules.orderValue(from: "0"), 0)
        XCTAssertTrue(DealLineRules.orderValueTextIsValid(""))
        XCTAssertTrue(DealLineRules.orderValueTextIsValid("10"))
        XCTAssertFalse(DealLineRules.orderValueTextIsValid("-1"))
        XCTAssertFalse(DealLineRules.orderValueTextIsValid("x"))
    }

    // MARK: - Draft lines (create flow)

    func testPickingAProductPrefillsReferenceMakeAndBrand() throws {
        let p = try decode(Product.self,
            #"{"id":"p1","name":"Gate valve","sku":" 13280 ","price":100,"make_id":"M1","brand_id":"B1","make_name":"MAC Valves","brand_name":"MAC"}"#)
        var l = DealLineDraft()
        l.apply(product: p)
        XCTAssertEqual(l.reference, "13280")
        XCTAssertEqual(l.makeId, "M1")
        XCTAssertEqual(l.makeName, "MAC Valves")
        XCTAssertEqual(l.brandId, "B1")
        XCTAssertEqual(l.brandName, "MAC")

        // Both stay editable, and "None" clears them.
        l.makeId = nil
        l.makeName = nil
        XCTAssertNil(l.makeId)

        // A product without make / brand replaces the previous pick's values.
        let plain = try decode(Product.self, #"{"id":"p2","name":"Seal","price":5}"#)
        l.apply(product: plain)
        XCTAssertEqual(l.reference, "")
        XCTAssertNil(l.brandId)
        XCTAssertNil(l.brandName)
    }

    func testPayloadSendsTheNewKeysOnlyWhenSet() {
        let bare = DealLineDraft(name: "A", quantityText: "1", unitPriceText: "5").payload
        for key in ["make_id", "brand_id", "funnel_ref", "order_value"] {
            XCTAssertNil(bare[key], key)
        }
        let full = DealLineDraft(
            name: "A", quantityText: "2", unitPriceText: "5",
            makeId: "M1", brandId: "B1", brandName: "MAC",
            orderValueText: "8", funnelRef: " F-9 "
        ).payload
        XCTAssertEqual(full["make_id"] as? String, "M1")
        XCTAssertEqual(full["brand_id"] as? String, "B1")
        XCTAssertEqual(full["funnel_ref"] as? String, "F-9")
        XCTAssertEqual(full["order_value"] as? Double, 8)
        let blankish = DealLineDraft(
            name: "A", quantityText: "1", unitPriceText: "5",
            makeId: "", brandId: "", orderValueText: "  ", funnelRef: "  "
        ).payload
        for key in ["make_id", "brand_id", "funnel_ref", "order_value"] {
            XCTAssertNil(blankish[key], key)
        }
    }

    func testDealBodyItemsCarryTheNewKeysAndStillDropBlankRows() {
        var body: [String: Any] = ["name": "Plant A"]
        let lines = [
            DealLineDraft(productId: "p1", name: "Valve", quantityText: "2", unitPriceText: "100",
                          makeId: "M1", brandId: "B1", brandName: "MAC", funnelRef: "F-1"),
            DealLineDraft(),
            // Only a brand picked on an otherwise untouched row: still blank, so dropped.
            DealLineDraft(brandId: "B1", brandName: "MAC"),
        ]
        SparkDealBody.apply(to: &body, accountId: nil, leadId: "lead-1", quotationNo: "", lines: lines)
        let items = body["items"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?["brand_id"] as? String, "B1")
        XCTAssertEqual(items?.first?["funnel_ref"] as? String, "F-1")
        XCTAssertEqual(body["amount"] as? Double, 200)
    }

    func testMacLineWithoutAFunnelReferenceBlocksUntilFixed() {
        var l = DealLineDraft(name: "Valve", quantityText: "1", unitPriceText: "10", brandId: "B1", brandName: "MAC")
        XCTAssertEqual(DealLines.funnelProblem([l]), "Line 1: MAC funnel reference is required for MAC products")
        XCTAssertEqual(DealLines.firstProblem([l]), "Line 1: MAC funnel reference is required for MAC products")
        l.funnelRef = "  "
        XCTAssertNotNil(DealLines.funnelProblem([l]))
        l.funnelRef = "F-1"
        XCTAssertNil(DealLines.funnelProblem([l]))
        XCTAssertNil(DealLines.firstProblem([l]))

        // Other brands: optional.
        let other = DealLineDraft(name: "Valve", quantityText: "1", unitPriceText: "10", brandName: "PHD")
        XCTAssertNil(DealLines.funnelProblem([other]))

        // An untouched blank row with a MAC brand is dropped on save, so it never blocks.
        XCTAssertNil(DealLines.funnelProblem([DealLineDraft(brandName: "MAC")]))

        // The message names the right line.
        XCTAssertEqual(
            DealLines.funnelProblem([other, DealLineDraft(name: "B", unitPriceText: "1", brandName: "mac")]),
            "Line 2: MAC funnel reference is required for MAC products"
        )
    }

    func testBadOrderValueIsReportedByFirstProblem() {
        let l = DealLineDraft(name: "A", quantityText: "1", unitPriceText: "5", orderValueText: "-3")
        XCTAssertEqual(DealLines.firstProblem([l]), "Line 1: Order value must be 0 or more.")
    }

    func testDraftTotalsTextShowsOrderedOnlyWhenSomeLineHasOne() {
        let quotedOnly = [
            DealLineDraft(name: "A", quantityText: "2", unitPriceText: "100"),
            DealLineDraft(name: "B", quantityText: "1", unitPriceText: "50"),
            DealLineDraft(),
        ]
        XCTAssertNil(DealLines.orderedTotal(quotedOnly))
        XCTAssertEqual(DealLines.totalsText(quotedOnly), "Quoted \(CurrencyFormatter.formatINR(250))")

        var withOrder = quotedOnly
        withOrder[0].orderValueText = "150"
        XCTAssertEqual(DealLines.orderedTotal(withOrder), 150)
        XCTAssertEqual(
            DealLines.totalsText(withOrder),
            "Quoted \(CurrencyFormatter.formatINR(250)) \u{00B7} Ordered \(CurrencyFormatter.formatINR(150))"
        )
    }

    // MARK: - Totals

    func testTotalsHelpers() {
        XCTAssertEqual(DealLineTotals.quoted([100.126, 50]), 150.13, accuracy: 0.0001)
        XCTAssertNil(DealLineTotals.ordered([nil, nil]))
        XCTAssertNil(DealLineTotals.ordered([]))
        XCTAssertEqual(DealLineTotals.ordered([nil, 30, 20]), 50)
        XCTAssertEqual(DealLineTotals.ordered([0, nil]), 0)
        XCTAssertEqual(DealLineTotals.quotedText(1250), "Quoted \(CurrencyFormatter.formatINR(1250))")
        XCTAssertNil(DealLineTotals.orderedText(nil))
        XCTAssertEqual(DealLineTotals.orderedText(900), "Ordered \(CurrencyFormatter.formatINR(900))")
        XCTAssertEqual(DealLineTotals.summary(quoted: 10, ordered: nil), "Quoted \(CurrencyFormatter.formatINR(10))")
    }

    func testSavedLineTotals() {
        let items = [
            line("a", qty: 2, price: 100, total: 200, order: 150),
            line("b", qty: 3, price: 10),                 // no line_total: qty x unit price
            line("c", qty: 1, price: 40, total: 40, order: 35),
        ]
        XCTAssertEqual(items[1].quotedValue, 30)
        XCTAssertEqual(DealLineItems.quotedTotal(items), 270)
        XCTAssertEqual(DealLineItems.orderedTotal(items), 185)
        XCTAssertNil(DealLineItems.orderedTotal([line("x")]))
    }

    // MARK: - Detail rows

    func testDetailRowsHideBlankValues() {
        let full = DealLineItem(id: "1", productName: "Valve", sku: "13280", reference: "13280",
                                makeName: "MAC Valves", brandName: "MAC", funnelRef: "F-1")
        XCTAssertEqual(full.detailRows, [
            LineDetailRow(label: "Reference", value: "13280"),
            LineDetailRow(label: "Make", value: "MAC Valves"),
            LineDetailRow(label: "Brand", value: "MAC"),
            LineDetailRow(label: "Funnel ref", value: "F-1"),
        ])
        let sparse = DealLineItem(id: "2", productName: "Seal", sku: " 99 ", makeName: "  ", funnelRef: "")
        XCTAssertEqual(sparse.detailRows, [LineDetailRow(label: "Reference", value: "99")])
        XCTAssertEqual(DealLineItem(id: "3").detailRows, [])
    }

    // MARK: - PATCH body

    func testPatchWithNoChangeIsEmpty() {
        let original = DealLineItem(id: "1", makeId: "M1", brandId: "B1", funnelRef: "F-1", orderValue: 10)
        let body = DealLineBody.patch(original: original, makeId: "M1", brandId: "B1",
                                      funnelRef: " F-1 ", orderValueText: "10")
        XCTAssertTrue(body.isEmpty)
        let none = DealLineBody.patch(original: DealLineItem(id: "2"), makeId: nil, brandId: "",
                                      funnelRef: "  ", orderValueText: "")
        XCTAssertTrue(none.isEmpty)
    }

    func testPatchSendsOnlyWhatChanged() {
        let original = DealLineItem(id: "1", makeId: "M1", brandId: "B1", funnelRef: "F-1")
        let body = DealLineBody.patch(original: original, makeId: "M1", brandId: "B2",
                                      funnelRef: "F-1", orderValueText: "1,250.5")
        XCTAssertEqual(body.count, 2)
        XCTAssertEqual(body["brand_id"] as? String, "B2")
        XCTAssertEqual(body["order_value"] as? Double, 1250.5)
        XCTAssertNil(body["make_id"])
        XCTAssertNil(body["funnel_ref"])
    }

    func testPatchSendsAnExplicitNullWhenClearing() {
        let original = DealLineItem(id: "1", makeId: "M1", brandId: "B1", funnelRef: "F-1", orderValue: 10)
        let body = DealLineBody.patch(original: original, makeId: nil, brandId: nil,
                                      funnelRef: "  ", orderValueText: "")
        XCTAssertEqual(body.count, 4)
        for key in ["make_id", "brand_id", "funnel_ref", "order_value"] {
            XCTAssertTrue(body[key] is NSNull, key)
        }
        // And it serialises as JSON nulls.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testPatchIgnoresAnInvalidOrderValue() {
        let original = DealLineItem(id: "1", orderValue: 10)
        let body = DealLineBody.patch(original: original, makeId: nil, brandId: nil,
                                      funnelRef: "", orderValueText: "-4")
        XCTAssertNil(body["order_value"])
    }

    // MARK: - Won flow: confirm the ordered value

    func testOnlyLinesWithoutAnOrderValueAreConfirmed() {
        let items = [
            line("a", qty: 2, price: 100, total: 200),
            line("b", total: 40, order: 35),
            line("c", qty: 1, price: 50.5),
        ]
        XCTAssertEqual(DealLineOrderConfirm.pending(items).map { $0.id }, ["a", "c"])
        let prefill = DealLineOrderConfirm.prefill(items)
        XCTAssertEqual(prefill["a"], "200")
        XCTAssertEqual(prefill["c"], "50.50")
        XCTAssertNil(prefill["b"])
    }

    func testConfirmPatchesCarryTheEditedValuesAndSkipBlanks() {
        let items = [line("a", total: 200), line("b", total: 40), line("c", total: 10, order: 9)]
        let texts = ["a": "180", "b": "  ", "c": "999"]
        let patches = DealLineOrderConfirm.patches(items: items, texts: texts)
        XCTAssertEqual(patches.map { $0.lineId }, ["a"])
        XCTAssertEqual(patches.first?.body["order_value"] as? Double, 180)
        XCTAssertNil(DealLineOrderConfirm.problem(items: items, texts: texts))
    }

    func testConfirmReportsABadValueButNotABlankOne() {
        let items = [line("a", name: "Gate valve", total: 200), line("b", total: 40)]
        XCTAssertEqual(
            DealLineOrderConfirm.problem(items: items, texts: ["a": "-1", "b": ""]),
            "Gate valve: Order value must be 0 or more."
        )
        XCTAssertNotNil(DealLineOrderConfirm.problem(items: items, texts: ["a": "abc"]))
        XCTAssertNil(DealLineOrderConfirm.problem(items: items, texts: ["a": "", "b": ""]))
        // Nothing to confirm when every line already has an order value.
        let done = [line("a", total: 5, order: 5)]
        XCTAssertTrue(DealLineOrderConfirm.patches(items: done, texts: ["a": "7"]).isEmpty)
        XCTAssertNil(DealLineOrderConfirm.problem(items: done, texts: ["a": "x"]))
    }

    // MARK: - Lead deals card

    func testLeadDealsHeader() throws {
        XCTAssertNil(LeadDealsSummary.headerText([]))
        let a = try deal(#","quoted_amount":1000,"order_amount":800"#)
        let b = try deal(#","quoted_amount":500"#)
        let two = LeadDealsSummary.headerText([a, b])
        XCTAssertEqual(
            two,
            "2 deals \u{00B7} \(CurrencyFormatter.formatINR(1500)) quoted \u{00B7} \(CurrencyFormatter.formatINR(800)) ordered"
        )
        let noOrder = LeadDealsSummary.headerText([b])
        XCTAssertEqual(noOrder, "1 deal \u{00B7} \(CurrencyFormatter.formatINR(500)) quoted")
    }

    func testLeadDealsQuotedFallsBackToTheDealAmount() throws {
        let noLines = try deal(#","amount":750"#)
        XCTAssertEqual(LeadDealsSummary.quoted(noLines), 750)
        XCTAssertEqual(LeadDealsSummary.quotedTotal([noLines]), 750)
        XCTAssertNil(LeadDealsSummary.orderedTotal([noLines]))
        let bare = try deal()
        XCTAssertEqual(LeadDealsSummary.quoted(bare), 0)
    }

    func testBrandChipsAreDedupedAndTrimmed() throws {
        let d = try deal(#","brands":["MAC"," PHD ","mac","","BEKO"]"#)
        XCTAssertEqual(LeadDealsSummary.brandChips(d), ["MAC", "PHD", "BEKO"])
        let bare = try deal()
        XCTAssertEqual(LeadDealsSummary.brandChips(bare), [])
    }

    func testEmptyStateText() {
        XCTAssertEqual(LeadDealsSummary.emptyText, "No deals yet. Add one for each requirement.")
    }
}
