//
//  OrderShareTests.swift
//  KinematicTests
//
//  The figures on the shareable order image: discount per line, quantity text, IST dates, tax split, totals.
//

import XCTest
@testable import Kinematic

final class OrderShareTests: XCTestCase {

    private func line(name: String? = "Royal Stag 750ml", qty: Int = 2, uom: String = "case", price: Double = 900,
                      mrp: Double = 1000, free: Bool? = nil, total: Double = 1800,
                      cgst: Double = 0, sgst: Double = 0, igst: Double = 0) -> PricedLine {
        PricedLine(sku_id: "sku-1", sku_name: name, sku_code: nil, hsn_code: nil, qty: qty, uom: uom,
                   unit_price: price, mrp: mrp, taxable_value: total, gst_rate: 18, cgst: cgst, sgst: sgst,
                   igst: igst, cess: 0, total: total, is_free_good: free)
    }

    private func order(_ lines: [PricedLine], taxable: Double? = 1800, status: String = "approved") -> DistOrder {
        DistOrder(id: "o1", order_no: "ORD-1", outlet_id: "out-1", outlet_name: " Mapusa Super Bazaar ",
                  distributor_id: "d1", salesman_id: nil, status: status, placed_at: "2026-10-17T10:30:00+00:00",
                  grand_total: 2124, taxable_value: taxable, geofence_passed: nil, geofence_distance_m: nil,
                  order_items: lines, distributor: nil)
    }

    func testDiscountIsMrpMinusRateTimesQty() {
        XCTAssertEqual(OrderShare.lineDiscount(line()), 200, accuracy: 0.001)
    }

    func testNoDiscountAtOrAboveMrpOrOnFreeGoods() {
        XCTAssertEqual(OrderShare.lineDiscount(line(price: 1000)), 0)
        XCTAssertEqual(OrderShare.lineDiscount(line(price: 1200)), 0)
        XCTAssertEqual(OrderShare.lineDiscount(line(price: 0, free: true)), 0)
    }

    func testQuantityKeepsTheServersUnitAndDefaultsWhenBlank() {
        XCTAssertEqual(OrderShare.qtyLabel(12, "case"), "12 case")
        XCTAssertEqual(OrderShare.qtyLabel(3, " "), "3 pcs")
    }

    func testDatesShowInIndianTimeAndFallBackToTheRawText() {
        XCTAssertEqual(OrderShare.placedLabel("2026-10-17T10:30:00+00:00"), "17 Oct 2026, 04:00 PM")
        XCTAssertEqual(OrderShare.placedLabel("2026-10-17T10:30:00.123Z"), "17 Oct 2026, 04:00 PM")
        XCTAssertEqual(OrderShare.placedLabel("yesterday"), "yesterday")
        XCTAssertNil(OrderShare.placedLabel("  "))
    }

    func testModelCarriesTotalsAndTrimsText() {
        let m = OrderShare.build(order: order([line(), line(name: nil, qty: 1, price: 1000, total: 1000)]),
                                 company: " Royal Spirits North ")
        XCTAssertEqual(m.company, "Royal Spirits North")
        XCTAssertEqual(m.outlet, "Mapusa Super Bazaar")
        XCTAssertEqual(m.status, "Approved")
        XCTAssertEqual(m.rows.count, 2)
        XCTAssertEqual(m.rows[1].name, "sku-1")
        XCTAssertEqual(m.totalDiscount, 200, accuracy: 0.001)
        XCTAssertEqual(m.grandTotal, 2124)
        XCTAssertTrue(m.hasDiscount)
    }

    func testTaxSplitIsTheSumOfTheLinesAndZeroLinesAreLeftOut() {
        let m = OrderShare.build(order: order([line(cgst: 81, sgst: 81), line(cgst: 81, sgst: 81)]), company: nil)
        XCTAssertEqual(m.taxLines.map { $0.label }, ["CGST", "SGST"])
        XCTAssertEqual(m.taxLines.first?.amount ?? 0, 162, accuracy: 0.001)
        XCTAssertNil(m.company)
    }

    func testTaxableFallsBackToTheSumOfTheLines() {
        let m = OrderShare.build(order: order([line(total: 1000), line(total: 800)], taxable: nil), company: nil)
        XCTAssertEqual(m.taxable, 1800, accuracy: 0.001)
    }
}
