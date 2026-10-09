//
//  ExpensePolicyRefreshTests.swift
//  KinematicTests
//
//  The Vehicle picker lists the vehicles of the policy the app HOLDS. The Expenses tab's view model lives as long
//  as the app does, so a policy fetched once and never asked for again would keep offering the vehicles of a policy
//  that has since been changed on the server. The policy is therefore asked for again each time the claims are
//  loaded and each time the editor opens; the fresh one replaces the held one, and a failed refresh keeps what
//  was held rather than blanking it. Also: GET /expenses/policy for a one-vehicle policy, with every field the
//  server sends, decodes and yields that one vehicle.
//

import XCTest
@testable import Kinematic

@MainActor
final class ExpensePolicyRefreshTests: XCTestCase {

    private struct Reply: Decodable { let success: Bool; let data: ExpensePolicy }

    /// GET /expenses/policy as the server answers it (`toClientShape`) for a policy with one vehicle, the
    /// presentation switches set, and every category and limit spelled out.
    private let carOnlyReply = #"""
    {"success":true,"data":{
      "id":"p-car","name":"Agrisynx - Car + DA Rs 200","description":null,"currency":"INR",
      "mileage_rate":12,"auto_approve_under":0,"escalate_over":null,"require_receipt_over":500,
      "category_limits":{"misc":200},"is_active":true,
      "rules":{
        "mileage_rate":12,"receipt_required_over":500,"max_claim_amount":null,"submit_within_days":null,
        "auto_approve_under":0,"escalate_over":null,"enforcement":"flag",
        "categories":{
          "mileage":{"enabled":true,"per_day_limit":null,"per_claim_limit":null,"per_month_limit":null,"receipt_required_over":null},
          "travel":{"enabled":false,"per_day_limit":null,"per_claim_limit":null,"per_month_limit":null,"receipt_required_over":null},
          "food":{"enabled":false,"per_day_limit":null,"per_claim_limit":null,"per_month_limit":null,"receipt_required_over":null},
          "lodging":{"enabled":false,"per_day_limit":null,"per_claim_limit":null,"per_month_limit":null,"receipt_required_over":null},
          "fuel":{"enabled":false,"per_day_limit":null,"per_claim_limit":null,"per_month_limit":null,"receipt_required_over":null},
          "toll":{"enabled":false,"per_day_limit":null,"per_claim_limit":null,"per_month_limit":null,"receipt_required_over":null},
          "misc":{"enabled":true,"per_day_limit":200,"per_claim_limit":null,"per_month_limit":null,"receipt_required_over":null}
        },
        "vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}],
        "odometer_photos_required":true,
        "category_labels":{"mileage":"Travel","misc":"Daily allowance"},
        "route_fields":false,"single_line":true,"odometer_camera_only":true
      }
    }}
    """#

    private func policy(vehicles: String, name: String) throws -> ExpensePolicy {
        let json = #"{"currency":"INR","mileage_rate":12,"require_receipt_over":500,"name":"\#(name)","rules":{"vehicle_rates":[\#(vehicles)]}}"#
        return try JSONDecoder().decode(ExpensePolicy.self, from: Data(json.utf8))
    }

    private func threeVehicles() throws -> ExpensePolicy {
        try policy(vehicles: #"{"id":"bike","label":"Bike","rate_per_km":4},{"id":"car","label":"Car","rate_per_km":9},{"id":"auto","label":"Auto","rate_per_km":6}"#,
                   name: "Default policy")
    }

    private func carOnly() throws -> ExpensePolicy {
        try policy(vehicles: #"{"id":"car","label":"Car","rate_per_km":9}"#, name: "Agrisynx - Car + DA Rs 200")
    }

    // MARK: - the server's reply

    func testTheOneVehiclePolicyAsTheServerSendsItDecodesToThatOneVehicle() throws {
        let p = try JSONDecoder().decode(Reply.self, from: Data(carOnlyReply.utf8)).data
        XCTAssertEqual(p.name, "Agrisynx - Car + DA Rs 200")
        let vehicles = ExpenseLogic.policyVehicles(p.rules)
        XCTAssertEqual(vehicles.map { $0.id }, ["car"])
        XCTAssertEqual(vehicles.first?.rate_per_km, 9)
        XCTAssertTrue(ExpenseLogic.paysByVehicle(p.rules))
        XCTAssertEqual(ExpenseLogic.soleVehicleId(vehicles), "car")
        // The presentation switches sent beside the vehicles do not get in the way.
        XCTAssertEqual(p.rules?.category_labels?["mileage"], "Travel")
        XCTAssertEqual(p.rules?.route_fields, false)
        XCTAssertEqual(p.rules?.single_line, true)
        XCTAssertEqual(p.rules?.odometer_camera_only, true)
        XCTAssertEqual(p.rules?.categories?["misc"]?.per_day_limit, 200)
        XCTAssertNil(p.rules?.categories?["mileage"]?.per_day_limit)
    }

    // MARK: - holding the policy

    func testAFreshPolicyReplacesTheHeldOneSoAStalePickerCannotSurvive() throws {
        let held = try threeVehicles()
        XCTAssertEqual(ExpenseLogic.policyVehicles(held.rules).map { $0.id }, ["bike", "car", "auto"])
        XCTAssertNil(ExpenseLogic.soleVehicleId(ExpenseLogic.policyVehicles(held.rules)))

        let after = ExpenseLogic.policyAfterRefresh(current: held, fetched: try carOnly())

        XCTAssertEqual(after?.name, "Agrisynx - Car + DA Rs 200")
        XCTAssertEqual(ExpenseLogic.policyVehicles(after?.rules).map { $0.id }, ["car"])
        XCTAssertEqual(ExpenseLogic.soleVehicleId(ExpenseLogic.policyVehicles(after?.rules)), "car")
    }

    func testAFreshPolicyWithNoVehiclesAlsoReplacesTheHeldOne() throws {
        let flat = try JSONDecoder().decode(ExpensePolicy.self, from: Data(
            #"{"currency":"INR","mileage_rate":12,"require_receipt_over":500,"name":"Flat","rules":{"mileage_rate":12}}"#.utf8))
        let after = ExpenseLogic.policyAfterRefresh(current: try threeVehicles(), fetched: flat)
        XCTAssertEqual(after?.name, "Flat")
        XCTAssertFalse(ExpenseLogic.paysByVehicle(after?.rules))
    }

    func testAFailedRefreshKeepsWhatWasHeldInsteadOfBlankingIt() throws {
        let held = try carOnly()
        let after = ExpenseLogic.policyAfterRefresh(current: held, fetched: nil)
        XCTAssertEqual(after?.name, held.name)
        XCTAssertEqual(ExpenseLogic.policyVehicles(after?.rules).map { $0.id }, ["car"])
    }

    func testTheFirstFetchSetsItAndNothingAtAllStaysNothing() throws {
        XCTAssertEqual(ExpenseLogic.policyAfterRefresh(current: nil, fetched: try carOnly())?.name, "Agrisynx - Car + DA Rs 200")
        XCTAssertNil(ExpenseLogic.policyAfterRefresh(current: nil, fetched: nil))
    }
}
