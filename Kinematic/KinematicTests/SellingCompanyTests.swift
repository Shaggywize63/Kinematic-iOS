//
//  SellingCompanyTests.swift
//  KinematicTests
//
//  The selling company rides only on the distribution surface — never on CRM, attendance or forms — and only a
//  valid UUID can ever be stored or sent.
//

import XCTest
@testable import Kinematic

final class SellingCompanyTests: XCTestCase {
    private let a = "11111111-1111-4111-8111-111111111111"

    private func withSuite(_ body: (UserDefaults) -> Void) {
        let name = "SellingCompanyTests-\(UUID().uuidString)"
        guard let d = UserDefaults(suiteName: name) else { return XCTFail("could not make a test UserDefaults") }
        defer { d.removePersistentDomain(forName: name) }
        body(d)
    }

    func testOnlyTheDistributionSurfaceFollowsTheCompany() {
        XCTAssertTrue(SellingCompany.appliesTo(path: "/api/v1/salesman/orders"))
        XCTAssertTrue(SellingCompany.appliesTo(path: "/api/v1/salesman/outlets/abc/catalogue"))
        XCTAssertTrue(SellingCompany.appliesTo(path: "/api/v1/distribution/stock"))
        XCTAssertTrue(SellingCompany.appliesTo(path: "/api/v1/skus"))
        XCTAssertFalse(SellingCompany.appliesTo(path: "/api/v1/crm/leads"))
        XCTAssertFalse(SellingCompany.appliesTo(path: "/api/v1/attendance/check-in"))
        XCTAssertFalse(SellingCompany.appliesTo(path: "/api/v1/forms/templates"))
        XCTAssertFalse(SellingCompany.appliesTo(path: "/api/v1/companies/mine"))
        XCTAssertFalse(SellingCompany.appliesTo(path: "/api/v1/salesmanship"))
    }

    func testStoresAndClearsAValidCompany() {
        withSuite { d in
            XCTAssertNil(SellingCompany.selectedId(in: d))
            SellingCompany.set(a, in: d)
            XCTAssertEqual(SellingCompany.selectedId(in: d), a)
            SellingCompany.set(nil, in: d)
            XCTAssertNil(SellingCompany.selectedId(in: d))
        }
    }

    func testRefusesAnythingThatIsNotAUUID() {
        withSuite { d in
            SellingCompany.set("x),client_id.not.is.null,(y", in: d)
            XCTAssertNil(SellingCompany.selectedId(in: d))
            d.set("Gomant", forKey: SellingCompany.storageKey)
            XCTAssertNil(SellingCompany.selectedId(in: d))
        }
    }

    func testSignOutForgetsTheCompany() {
        XCTAssertTrue(SessionCleanup.userDefaultsKeys.contains(SellingCompany.storageKey))
    }
}
