//
//  OutletPickerLogicTests.swift
//  KinematicTests
//
//  What the outlet picker shows for a row, how a typed query narrows the rows while the server's answer is still on
//  its way, and what "Book Order" opens for the outlet picked.
//

import XCTest
@testable import Kinematic

@MainActor
final class OutletPickerLogicTests: XCTestCase {

    private func outlet(id: String = "o-1", name: String? = "Sri Balaji", code: String? = nil, city: String? = nil,
                        distributorId: String? = nil, distributorName: String? = nil, balance: Double? = nil) -> SalesmanOutlet {
        SalesmanOutlet(id: id, name: name, code: code, city: city, distributorId: distributorId,
                       distributorName: distributorName, outstandingBalance: balance)
    }

    // MARK: - A row

    func testTheSubtitleJoinsTheCodeAndTheCityWhicheverExist() {
        XCTAssertEqual(OutletPickerLogic.subtitle(outlet(code: "SB01", city: "Hyderabad")), "SB01 · Hyderabad")
        XCTAssertEqual(OutletPickerLogic.subtitle(outlet(code: "SB01")), "SB01")
        XCTAssertEqual(OutletPickerLogic.subtitle(outlet(city: "Hyderabad")), "Hyderabad")
        XCTAssertEqual(OutletPickerLogic.subtitle(outlet()), "")
        XCTAssertEqual(OutletPickerLogic.subtitle(outlet(code: "  ", city: "")), "")
    }

    func testTheDetailLineAddsTheDistributor() {
        XCTAssertEqual(OutletPickerLogic.detailLine(outlet(code: "SB01", city: "Hyderabad", distributorName: "Gomant North")),
                       "SB01 · Hyderabad · Gomant North")
        XCTAssertEqual(OutletPickerLogic.detailLine(outlet(distributorName: "Gomant North")), "Gomant North")
        XCTAssertEqual(OutletPickerLogic.detailLine(outlet()), "")
    }

    func testTheNameFallsBackToTheCodeThenTheId() {
        XCTAssertEqual(OutletPickerLogic.displayName(outlet(name: "Sri Balaji", code: "SB01")), "Sri Balaji")
        XCTAssertEqual(OutletPickerLogic.displayName(outlet(name: " ", code: "SB01")), "SB01")
        XCTAssertEqual(OutletPickerLogic.displayName(outlet(id: "o-7", name: nil, code: nil)), "o-7")
    }

    func testOnlyAnOutletThatOwesMoneyGetsADueLabel() {
        XCTAssertEqual(OutletPickerLogic.dueLabel(outlet(balance: 12500)), "₹12,500 due")
        XCTAssertEqual(OutletPickerLogic.dueLabel(outlet(balance: 125000)), "₹1,25,000 due")
        XCTAssertNil(OutletPickerLogic.dueLabel(outlet(balance: 0)))
        XCTAssertNil(OutletPickerLogic.dueLabel(outlet(balance: -50)))
        XCTAssertNil(OutletPickerLogic.dueLabel(outlet(balance: 0.4)))
        XCTAssertNil(OutletPickerLogic.dueLabel(outlet(balance: nil)))
    }

    // MARK: - What Book Order opens

    func testTheOrderTargetCarriesTheOutletAndItsDistributor() {
        let target = OutletPickerLogic.orderTarget(for: outlet(id: "o-1", name: "Sri Balaji", distributorId: "d-1"))
        XCTAssertEqual(target, OutletPickerLogic.OrderTarget(outletId: "o-1", outletName: "Sri Balaji", distributorId: "d-1"))
    }

    func testNoDistributorOrNameMeansThosePartsAreLeftOff() {
        XCTAssertEqual(OutletPickerLogic.orderTarget(for: outlet(id: "o-3", name: nil)),
                       OutletPickerLogic.OrderTarget(outletId: "o-3", outletName: nil, distributorId: nil))
        XCTAssertEqual(OutletPickerLogic.orderTarget(for: outlet(id: "o-3", name: "X", distributorId: "")),
                       OutletPickerLogic.OrderTarget(outletId: "o-3", outletName: "X", distributorId: nil))
        // Without a name the code stands in for it.
        XCTAssertEqual(OutletPickerLogic.orderTarget(for: outlet(id: "o-4", name: " ", code: "SB04")).outletName, "SB04")
    }

    // MARK: - The query

    func testTheQueryIsTrimmedAndBlankMeansNone() {
        XCTAssertEqual(OutletPickerLogic.normalizedQuery("  bal "), "bal")
        XCTAssertNil(OutletPickerLogic.normalizedQuery("   "))
        XCTAssertNil(OutletPickerLogic.normalizedQuery(""))
    }

    func testAnOutletMatchesOnNameCodeCityOrDistributorIgnoringCaseAndAccents() {
        let o = outlet(name: "Sri Balaji Café", code: "SB01", city: "Hyderabad", distributorName: "Gomant North")
        XCTAssertTrue(OutletPickerLogic.matches(o, query: "balaji"))
        XCTAssertTrue(OutletPickerLogic.matches(o, query: "CAFE"))
        XCTAssertTrue(OutletPickerLogic.matches(o, query: "sb0"))
        XCTAssertTrue(OutletPickerLogic.matches(o, query: "hyder"))
        XCTAssertTrue(OutletPickerLogic.matches(o, query: "gomant"))
        XCTAssertFalse(OutletPickerLogic.matches(o, query: "lakshmi"))
        XCTAssertTrue(OutletPickerLogic.matches(o, query: "   "))      // a blank query matches everything
    }

    func testFilteringKeepsTheServersOrder() {
        let rows = [outlet(id: "a", name: "Balaji One"), outlet(id: "b", name: "Lakshmi"), outlet(id: "c", name: "Balaji Two")]
        XCTAssertEqual(OutletPickerLogic.filter(rows, query: "balaji").map { $0.id }, ["a", "c"])
        XCTAssertEqual(OutletPickerLogic.filter(rows, query: "").map { $0.id }, ["a", "b", "c"])
        XCTAssertTrue(OutletPickerLogic.filter(rows, query: "zzz").isEmpty)
    }

    func testTheServersAnswerForTheCurrentQueryIsShownAsSent() {
        // The server matched on text the local filter does not know about (it strips wildcard characters), so the
        // rows for the current query are never narrowed again.
        let rows = [outlet(id: "a", name: "Sri Balaji"), outlet(id: "b", name: "Totally Different")]
        XCTAssertEqual(OutletPickerLogic.displayed(results: rows, resultsQuery: "bal", currentQuery: "bal").map { $0.id }, ["a", "b"])
        XCTAssertEqual(OutletPickerLogic.displayed(results: rows, resultsQuery: "bal", currentQuery: "  bal ").map { $0.id }, ["a", "b"])
        XCTAssertEqual(OutletPickerLogic.displayed(results: rows, resultsQuery: nil, currentQuery: "").map { $0.id }, ["a", "b"])
    }

    func testWhileTheNextAnswerIsOnItsWayThePreviousRowsAreNarrowedLocally() {
        let rows = [outlet(id: "a", name: "Sri Balaji"), outlet(id: "b", name: "Lakshmi")]
        XCTAssertEqual(OutletPickerLogic.displayed(results: rows, resultsQuery: nil, currentQuery: "bal").map { $0.id }, ["a"])
        XCTAssertEqual(OutletPickerLogic.displayed(results: rows, resultsQuery: "b", currentQuery: "bal").map { $0.id }, ["a"])
        // Clearing the box shows everything held again.
        XCTAssertEqual(OutletPickerLogic.displayed(results: rows, resultsQuery: "bal", currentQuery: "").map { $0.id }, ["a", "b"])
    }

    func testTheMessages() {
        XCTAssertEqual(OutletPickerLogic.emptyMessage(forQuery: ""), "No outlets available.")
        XCTAssertEqual(OutletPickerLogic.emptyMessage(forQuery: "  bal "), "No outlets match \"bal\".")
        XCTAssertEqual(OutletPickerLogic.failedMessage("HTTP 500"), "Could not load outlets. HTTP 500")
        XCTAssertEqual(OutletPickerLogic.offlineMessage, "No connection — connect to the internet to search outlets.")
    }
}
