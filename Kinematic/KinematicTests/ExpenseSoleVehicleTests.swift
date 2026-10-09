//
//  ExpenseSoleVehicleTests.swift
//  KinematicTests
//
//  The Vehicle picker of the expense claim editor offers ONLY the vehicles of the policy that governs the
//  signed-in person (GET /expenses/policy is resolved per user), and when that policy lists EXACTLY ONE vehicle
//  a mileage line starts with it — also when the policy arrives after the editor opened — without ever replacing
//  a vehicle the line already has. With two or more vehicles there is no default. Pairs with
//  ExpenseVehicleLogicTests (the odometer pricing and what is sent).
//

import XCTest
@testable import Kinematic

final class ExpenseSoleVehicleTests: XCTestCase {

    private let bike = ExpenseVehicleRate(id: "bike", label: "Bike", rate_per_km: 4)
    private let car = ExpenseVehicleRate(id: "car", label: "Car", rate_per_km: 9)

    private func rules(_ json: String) throws -> ExpensePolicyRules {
        try JSONDecoder().decode(ExpensePolicyRules.self, from: Data(json.utf8))
    }

    private func mileage(vehicle: String = "") -> ExpenseLineFields {
        var f = ExpenseLineFields(category: "mileage", itemDate: "2026-10-05")
        f.vehicleType = vehicle
        return f
    }

    // MARK: - which vehicles the picker lists

    func testThePickerListsOnlyThePoliciesOwnVehiclesInItsOrder() throws {
        let r = try rules(#"{"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9},{"id":"bike","label":"Bike","rate_per_km":4}]}"#)
        XCTAssertEqual(ExpenseLogic.policyVehicles(r).map { $0.id }, ["car", "bike"])
        XCTAssertEqual(ExpenseLogic.policyVehicles(r).map { $0.label }, ["Car", "Bike"])
    }

    func testNoPolicyOrNoVehicleRatesMeansNoVehicles() throws {
        XCTAssertTrue(ExpenseLogic.policyVehicles(nil).isEmpty)
        XCTAssertTrue(ExpenseLogic.policyVehicles(try rules(#"{"mileage_rate":12}"#)).isEmpty)
        XCTAssertTrue(ExpenseLogic.policyVehicles(try rules(#"{"vehicle_rates":[]}"#)).isEmpty)
    }

    func testABlankOrRepeatedIdIsDroppedSoThePickerCanTellVehiclesApart() throws {
        let r = try rules(#"{"vehicle_rates":[{"id":"bike","label":"Bike","rate_per_km":4},{"id":"bike","label":"Bike again","rate_per_km":5},{"id":"  ","label":"No id","rate_per_km":6},{"id":"car","label":"Car","rate_per_km":9}]}"#)
        XCTAssertEqual(ExpenseLogic.policyVehicles(r).map { $0.id }, ["bike", "car"])
        XCTAssertEqual(ExpenseLogic.policyVehicles(r).first?.label, "Bike")
    }

    func testTheSameListFeedsThePickerAndThePricing() throws {
        // The picker, the on-screen total and the default all read this one list.
        let r = try rules(#"{"vehicle_rates":[{"id":"bike","label":"Bike","rate_per_km":4}]}"#)
        var f = mileage(vehicle: "bike")
        f.odometerStart = "100"; f.odometerEnd = "150"
        XCTAssertEqual(f.effectiveAmount(mileageRate: 12, vehicles: ExpenseLogic.policyVehicles(r)), 200)
    }

    // MARK: - when there is a default

    func testOnlyAPolicyWithExactlyOneVehicleHasADefault() {
        XCTAssertEqual(ExpenseLogic.soleVehicleId([bike]), "bike")
        XCTAssertNil(ExpenseLogic.soleVehicleId([bike, car]))
        XCTAssertNil(ExpenseLogic.soleVehicleId([]))
        XCTAssertNil(ExpenseLogic.soleVehicleId(nil))
    }

    func testTheDefaultComesFromTheDecodedPolicy() throws {
        let one = try JSONDecoder().decode(ExpensePolicy.self, from: Data(
            #"{"currency":"INR","mileage_rate":12,"require_receipt_over":500,"rules":{"vehicle_rates":[{"id":"two_wheeler","label":"Two-wheeler","rate_per_km":4}]}}"#.utf8))
        XCTAssertEqual(ExpenseLogic.soleVehicleId(ExpenseLogic.policyVehicles(one.rules)), "two_wheeler")
        let two = try JSONDecoder().decode(ExpensePolicy.self, from: Data(
            #"{"currency":"INR","mileage_rate":12,"require_receipt_over":500,"rules":{"vehicle_rates":[{"id":"bike","label":"Bike","rate_per_km":4},{"id":"car","label":"Car","rate_per_km":9}]}}"#.utf8))
        XCTAssertNil(ExpenseLogic.soleVehicleId(ExpenseLogic.policyVehicles(two.rules)))
        // A policy without vehicle rates (flat mileage) has none either.
        let flat = try JSONDecoder().decode(ExpensePolicy.self, from: Data(
            #"{"currency":"INR","mileage_rate":12,"require_receipt_over":500,"rules":{"mileage_rate":12}}"#.utf8))
        XCTAssertNil(ExpenseLogic.soleVehicleId(ExpenseLogic.policyVehicles(flat.rules)))
    }

    // MARK: - which lines take it

    func testAMileageLineWithNoVehicleTakesTheSoleVehicle() {
        XCTAssertEqual(mileage().withSoleVehicle("bike").vehicleType, "bike")
        // A vehicle that is only blanks counts as none.
        XCTAssertEqual(mileage(vehicle: "  ").withSoleVehicle("bike").vehicleType, "bike")
        XCTAssertTrue(mileage().lacksVehicle)
    }

    func testAVehicleTheLineAlreadyHasIsNeverReplaced() {
        XCTAssertEqual(mileage(vehicle: "car").withSoleVehicle("bike").vehicleType, "car")
        // Not even one the policy no longer lists.
        XCTAssertEqual(mileage(vehicle: "tractor").withSoleVehicle("bike").vehicleType, "tractor")
        XCTAssertFalse(mileage(vehicle: "car").lacksVehicle)
    }

    func testNoDefaultMeansNothingChanges() {
        XCTAssertEqual(mileage().withSoleVehicle(nil), mileage())
        XCTAssertEqual(mileage().withSoleVehicle(""), mileage())
    }

    func testOtherCategoriesAreLeftAlone() {
        for category in ["food", "lodging", "fuel", "toll", "misc", "travel"] {
            var f = ExpenseLineFields(category: category, itemDate: "2026-10-05")
            XCTAssertFalse(f.lacksVehicle, category)
            f = f.withSoleVehicle("bike")
            XCTAssertEqual(f.vehicleType, "", category)
        }
    }

    func testALineAlreadySavedOnTheClaimWithNoVehicleTakesItToo() {
        var saved = mileage()
        saved.id = "item-1"
        saved.odometerStart = "12340"
        XCTAssertEqual(saved.withSoleVehicle("bike").vehicleType, "bike")
        // Nothing else about the line moves.
        XCTAssertEqual(saved.withSoleVehicle("bike").odometerStart, "12340")
        XCTAssertEqual(saved.withSoleVehicle("bike").id, "item-1")
    }

    // MARK: - the policy arrives after the editor opened

    func testALinePreparedBeforeThePolicyArrivedIsFilledOnceItDoes() throws {
        // The editor opened with no policy: nothing to default yet.
        var lines = [mileage(), mileage(vehicle: "car")]
        var sole = ExpenseLogic.soleVehicleId(ExpenseLogic.policyVehicles(nil))
        lines = lines.map { $0.withSoleVehicle(sole) }
        XCTAssertEqual(lines.map { $0.vehicleType }, ["", "car"])
        // The policy lands with exactly one vehicle: the empty line takes it, the chosen one keeps its own.
        sole = ExpenseLogic.soleVehicleId(ExpenseLogic.policyVehicles(try rules(#"{"vehicle_rates":[{"id":"bike","label":"Bike","rate_per_km":4}]}"#)))
        lines = lines.map { $0.withSoleVehicle(sole) }
        XCTAssertEqual(lines.map { $0.vehicleType }, ["bike", "car"])
        // Applying it again changes nothing.
        XCTAssertEqual(lines.map { $0.withSoleVehicle(sole) }, lines)
    }

    func testWithSeveralVehiclesThePersonChoosesAndNothingIsPreSelected() throws {
        let sole = ExpenseLogic.soleVehicleId(ExpenseLogic.policyVehicles(
            try rules(#"{"vehicle_rates":[{"id":"bike","label":"Bike","rate_per_km":4},{"id":"car","label":"Car","rate_per_km":9}]}"#)))
        XCTAssertNil(sole)
        XCTAssertEqual(mileage().withSoleVehicle(sole).vehicleType, "")
    }

    // MARK: - an untouched line stays untouched

    func testALineHoldingOnlyThePreSelectedVehicleIsNotSomethingThePersonEntered() {
        let line = mileage().withSoleVehicle("bike")
        XCTAssertTrue(line.isFilled)                                   // the raw rule counts any vehicle…
        XCTAssertFalse(line.isFilledIgnoring(soleVehicle: "bike"))     // …the editor's rule does not
    }

    func testAnythingElseTypedMakesTheLineFilled() {
        let edits: [(inout ExpenseLineFields) -> Void] = [
            { $0.odometerStart = "12340" },
            { $0.fromLocation = "Nashik" },
            { $0.odoStartPhoto = "https://x/o.jpg" },
            { $0.description = "Client visit" },
        ]
        for edit in edits {
            var f = mileage().withSoleVehicle("bike")
            edit(&f)
            XCTAssertTrue(f.isFilledIgnoring(soleVehicle: "bike"))
        }
    }

    func testAVehicleOtherThanTheDefaultIsAChoiceTheLineCounts() {
        XCTAssertTrue(mileage(vehicle: "car").isFilledIgnoring(soleVehicle: "bike"))
    }

    func testALineAlreadySavedAlwaysCountsWhatItHas() {
        var saved = mileage(vehicle: "bike")
        saved.id = "item-1"
        XCTAssertTrue(saved.isFilledIgnoring(soleVehicle: "bike"))
    }

    func testWithoutADefaultTheRuleIsTheOriginalOne() {
        XCTAssertFalse(ExpenseLineFields().isFilledIgnoring(soleVehicle: nil))
        XCTAssertTrue(mileage(vehicle: "car").isFilledIgnoring(soleVehicle: nil))
        XCTAssertTrue(mileage(vehicle: "car").isFilledIgnoring(soleVehicle: ""))
        var typed = ExpenseLineFields(); typed.amount = "250"
        XCTAssertTrue(typed.isFilledIgnoring(soleVehicle: nil))
    }

    // MARK: - what is sent

    func testThePreSelectedVehicleIsSentOnceTheLineIsFilledIn() {
        var f = mileage().withSoleVehicle("bike")
        f.odometerStart = "12340"; f.odometerEnd = "12392"
        XCTAssertTrue(f.isFilledIgnoring(soleVehicle: "bike"))
        let sent = f.toInput(byVehicle: true)
        XCTAssertEqual(sent.vehicle_type, "bike")
        XCTAssertEqual(sent.odometer_start, 12340)
        XCTAssertEqual(f.effectiveAmount(mileageRate: 12, vehicles: [ExpenseVehicleRate(id: "bike", label: "Bike", rate_per_km: 4)]), 208)
    }
}
