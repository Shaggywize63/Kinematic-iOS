//
//  LeadsViewModelTests.swift
//  KinematicTests
//
//  Pure, network-free logic on the leads list view-model: active-filter
//  counting, filter reset, pagination `hasMore`, and the CreateOutcome enum.
//  The VM hardcodes `CRMService.shared`, so we only seed `@Published` state
//  and assert the derived getters — no network is exercised.
//

import XCTest
@testable import Kinematic

@MainActor
final class LeadsViewModelTests: XCTestCase {

    func testActiveFilterCountDefaultsToZero() {
        let vm = LeadsViewModel()
        XCTAssertEqual(vm.activeFilterCount, 0)
    }

    func testActiveFilterCountCountsEachNonDefault() {
        let vm = LeadsViewModel()
        vm.lifecycleFilter = "mql"
        vm.convertedFilter = "yes"
        vm.ownerFilter = "user-1"
        vm.sourceFilter = "src-1"
        vm.dateFrom = Date()
        XCTAssertEqual(vm.activeFilterCount, 5)
    }

    func testActiveFilterCountDateBoundsCountOnce() {
        let vm = LeadsViewModel()
        vm.dateTo = Date()
        XCTAssertEqual(vm.activeFilterCount, 1)
        vm.dateFrom = Date()
        XCTAssertEqual(vm.activeFilterCount, 1)
    }

    func testResetFiltersReturnsToDefaults() {
        let vm = LeadsViewModel()
        vm.lifecycleFilter = "sql"
        vm.convertedFilter = "no"
        vm.ownerFilter = "u"
        vm.sourceFilter = "s"
        vm.dateFrom = Date()
        vm.dateTo = Date()

        vm.resetFilters()

        XCTAssertEqual(vm.activeFilterCount, 0)
        XCTAssertEqual(vm.lifecycleFilter, "all")
        XCTAssertEqual(vm.convertedFilter, "all")
        XCTAssertEqual(vm.ownerFilter, "all")
        XCTAssertEqual(vm.sourceFilter, "all")
        XCTAssertNil(vm.dateFrom)
        XCTAssertNil(vm.dateTo)
    }

    func testHasMoreReflectsLoadedVersusTotal() throws {
        let vm = LeadsViewModel()
        vm.total = 5
        vm.leads = [try TestFixtures.lead(id: "a"), try TestFixtures.lead(id: "b")]
        XCTAssertTrue(vm.hasMore)

        vm.total = 2
        XCTAssertFalse(vm.hasMore)

        vm.total = 0
        vm.leads = []
        XCTAssertFalse(vm.hasMore)
    }

    func testCreateOutcomeCarriesErrorMessage() {
        let outcomes: [LeadsViewModel.CreateOutcome] = [.online, .offline, .error("bad")]
        var captured: String?
        for outcome in outcomes {
            if case .error(let msg) = outcome { captured = msg }
        }
        XCTAssertEqual(captured, "bad")
    }
}
