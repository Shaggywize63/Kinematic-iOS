//
//  ExpenseGpsDistanceTests.swift
//  KinematicTests
//
//  Policy rule `gps_distance`: a vehicle line may carry the day's GPS distance instead of odometer readings (the line
//  "Add today's travel to expenses" creates and the claim editor must keep when it opens it). Policies without the rule
//  must read exactly as before. Mirrors the Android ExpenseGpsDistanceTest.
//

import XCTest
@testable import Kinematic

@MainActor
final class ExpenseGpsDistanceTests: XCTestCase {

    private let vehicles: [ExpenseVehicleRate] = [
        ExpenseVehicleRate(id: "two_wheeler", label: "Two-wheeler", rate_per_km: 4),
        ExpenseVehicleRate(id: "car", label: "Car", rate_per_km: 9),
    ]

    private func rules(_ json: String) throws -> ExpensePolicyRules {
        try JSONDecoder().decode(ExpensePolicyRules.self, from: Data(json.utf8))
    }

    private func item(_ json: String) throws -> ExpenseClaimItem {
        try JSONDecoder().decode(ExpenseClaimItem.self, from: Data(json.utf8))
    }

    /// What "Add today's travel" saves, as the editor reads it back: vehicle + distance, no odometer.
    private func gpsLine(km: String = "23.4", vehicle: String = "two_wheeler") -> ExpenseLineFields {
        var f = ExpenseLineFields(category: "mileage", itemDate: "2026-10-10")
        f.id = "i1"
        f.vehicleType = vehicle
        f.distanceKm = km
        return f
    }

    private func odometerLine() -> ExpenseLineFields {
        var f = ExpenseLineFields(category: "mileage", itemDate: "2026-10-10")
        f.vehicleType = "car"
        f.odometerStart = "100"
        f.odometerEnd = "150"
        f.distanceKm = "50"
        return f
    }

    // MARK: - the policy rule

    func testGpsDistanceIsReadFromThePolicy() throws {
        let p = try JSONDecoder().decode(ExpensePolicy.self, from: Data(
            #"{"name":"EFocus","currency":"INR","mileage_rate":12,"require_receipt_over":500,"rules":{"gps_distance":true,"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}]}}"#.utf8))
        XCTAssertEqual(p.rules?.gps_distance, true)
        XCTAssertTrue(ExpenseLogic.gpsDistanceOn(p.rules))
    }

    func testAPolicyThatDoesNotMentionGpsDistanceIsUnchanged() throws {
        let p = try JSONDecoder().decode(ExpensePolicy.self, from: Data(
            #"{"name":"Std","currency":"INR","mileage_rate":12,"require_receipt_over":500,"rules":{"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}]}}"#.utf8))
        XCTAssertNil(p.rules?.gps_distance)
        XCTAssertFalse(ExpenseLogic.gpsDistanceOn(p.rules))
        XCTAssertFalse(ExpenseLogic.gpsDistanceOn(nil))
        XCTAssertFalse(ExpenseLogic.gpsDistanceOn(try rules("{}")))
    }

    func testGpsDistanceNeedsVehicleRatesAndTheSwitchOn() throws {
        let car = #"[{"id":"car","label":"Car","rate_per_km":9}]"#
        XCTAssertTrue(ExpenseLogic.gpsDistanceOn(try rules(#"{"gps_distance":true,"vehicle_rates":\#(car)}"#)))
        XCTAssertFalse(ExpenseLogic.gpsDistanceOn(try rules(#"{"gps_distance":true}"#)))
        XCTAssertFalse(ExpenseLogic.gpsDistanceOn(try rules(#"{"gps_distance":true,"vehicle_rates":[]}"#)))
        XCTAssertFalse(ExpenseLogic.gpsDistanceOn(try rules(#"{"gps_distance":false,"vehicle_rates":\#(car)}"#)))
        XCTAssertFalse(ExpenseLogic.gpsDistanceOn(try rules(#"{"vehicle_rates":\#(car)}"#)))
    }

    func testTheSwitchSurvivesTheCachedPolicyBeingStoredAndRead() throws {
        let r = try rules(#"{"gps_distance":true,"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}]}"#)
        let back = try JSONDecoder().decode(ExpensePolicyRules.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.gps_distance, true)
        XCTAssertEqual(back, r)
    }

    // MARK: - which lines are GPS lines

    func testAVehicleLineWithADistanceAndNoOdometerDataIsAGpsLineUnderThePolicy() {
        XCTAssertTrue(gpsLine().isGpsDistanceLine(gps: true))
        // not under a policy without the rule
        XCTAssertFalse(gpsLine().isGpsDistanceLine(gps: false))
    }

    func testBlankOdometerFieldsDoNotStopALineBeingAGpsLine() {
        var f = gpsLine()
        f.odometerStart = "  "
        f.odoEndPhoto = " "
        XCTAssertTrue(f.isGpsDistanceLine(gps: true))
    }

    func testALineWithAnyOdometerDataOrNoDistanceIsNotAGpsLine() {
        var a = gpsLine(); a.odometerStart = "100"
        var b = gpsLine(); b.odometerEnd = "120"
        var c = gpsLine(); c.odoStartPhoto = "p1"
        var d = gpsLine(); d.odoEndPhoto = "p2"
        var e = gpsLine(); e.category = "food"
        XCTAssertFalse(a.isGpsDistanceLine(gps: true))
        XCTAssertFalse(b.isGpsDistanceLine(gps: true))
        XCTAssertFalse(c.isGpsDistanceLine(gps: true))
        XCTAssertFalse(d.isGpsDistanceLine(gps: true))
        XCTAssertFalse(e.isGpsDistanceLine(gps: true))
        XCTAssertFalse(gpsLine(km: "").isGpsDistanceLine(gps: true))
        XCTAssertFalse(gpsLine(km: "0").isGpsDistanceLine(gps: true))
    }

    // MARK: - what the editor sends and shows

    func testAGpsLineIsSavedWithItsDistanceAndVehicleAndWithoutOdometerDataOrAmount() {
        let input = gpsLine().toInput(byVehicle: true, routeFields: true, gpsDistance: true)
        XCTAssertEqual(input.distance_km, 23.4)
        XCTAssertEqual(input.vehicle_type, "two_wheeler")
        XCTAssertNil(input.amount)
        XCTAssertNil(input.odometer_start)
        XCTAssertNil(input.odometer_end)
        XCTAssertNil(input.odometer_start_photo_url)
        XCTAssertNil(input.odometer_end_photo_url)
        XCTAssertEqual(input.id, "i1")
        XCTAssertEqual(input.category, "mileage")
    }

    func testWithoutThePolicyRuleTheSameLineIsSentExactlyAsBeforeTheDistanceIsDropped() {
        let input = gpsLine().toInput(byVehicle: true, routeFields: true)
        XCTAssertNil(input.distance_km)
        XCTAssertEqual(input.vehicle_type, "two_wheeler")
        let explicit = gpsLine().toInput(byVehicle: true, routeFields: true, gpsDistance: false)
        XCTAssertEqual(explicit, input)
    }

    func testAPolicyThatPaysByDistanceAloneIsUntouchedByTheNewParameter() {
        // not a vehicle line: the distance goes as it always did
        var f = ExpenseLineFields(category: "mileage", itemDate: "2026-10-10")
        f.distanceKm = "12"
        XCTAssertEqual(f.toInput().distance_km, 12)
        XCTAssertEqual(f.toInput(byVehicle: false, routeFields: true, gpsDistance: true).distance_km, 12)
        XCTAssertEqual(f.toInput(), f.toInput(byVehicle: false, routeFields: true, gpsDistance: false))
    }

    func testALineWithOdometerReadingsIsSentAsAnOdometerLineEvenUnderAGpsPolicy() {
        let input = odometerLine().toInput(byVehicle: true, routeFields: true, gpsDistance: true)
        XCTAssertNil(input.distance_km)               // the server works it out from the readings
        XCTAssertEqual(input.odometer_start, 100)
        XCTAssertEqual(input.odometer_end, 150)
    }

    func testAGpsLinesAmountIsItsDistanceTimesTheVehiclesRate() {
        XCTAssertEqual(gpsLine().effectiveAmount(mileageRate: 12, vehicles: vehicles, gpsDistance: true), 93.6, accuracy: 0.0001)
        XCTAssertEqual(gpsLine(km: "10", vehicle: "car").effectiveAmount(mileageRate: 12, vehicles: vehicles, gpsDistance: true), 90, accuracy: 0.0001)
        // nothing to price without a vehicle or with an unlisted one
        XCTAssertEqual(gpsLine(vehicle: "").effectiveAmount(mileageRate: 12, vehicles: vehicles, gpsDistance: true), 0)
        XCTAssertEqual(gpsLine(vehicle: "tractor").effectiveAmount(mileageRate: 12, vehicles: vehicles, gpsDistance: true), 0)
    }

    func testWithoutThePolicyRuleAVehicleLineWithOnlyADistanceIsStillWorthNothingOnScreen() {
        XCTAssertEqual(gpsLine().effectiveAmount(mileageRate: 12, vehicles: vehicles), 0)
        XCTAssertEqual(gpsLine().effectiveAmount(mileageRate: 12, vehicles: vehicles, gpsDistance: false), 0)
    }

    func testOdometerLinesArePricedFromTheOdometerUnderEitherPolicy() {
        var f = ExpenseLineFields(category: "mileage", itemDate: "2026-10-10")
        f.vehicleType = "two_wheeler"
        f.odometerStart = "12340"
        f.odometerEnd = "12392"
        XCTAssertEqual(f.effectiveAmount(mileageRate: 12, vehicles: vehicles), 208, accuracy: 0.0001)
        XCTAssertEqual(f.effectiveAmount(mileageRate: 12, vehicles: vehicles, gpsDistance: true), 208, accuracy: 0.0001)
    }

    func testAFlatRateLineIsPricedAtThePolicyRateWhateverTheGpsFlag() {
        var f = ExpenseLineFields(category: "mileage", itemDate: "2026-10-10")
        f.distanceKm = "10"
        XCTAssertEqual(f.effectiveAmount(mileageRate: 12), 120, accuracy: 0.0001)
        XCTAssertEqual(f.effectiveAmount(mileageRate: 12, vehicles: nil, gpsDistance: true), 120, accuracy: 0.0001)
    }

    func testAGpsLineIsAValidFilledLineSoItCanBeSaved() {
        XCTAssertTrue(gpsLine().isFilled)
        XCTAssertTrue(gpsLine().canSave(byVehicle: true))
        XCTAssertTrue(gpsLine().isValid)
    }

    // MARK: - what comes back from the server

    func testASavedGpsLineComesBackFromTheServerAsTheSameGpsLine() throws {
        let saved = try item(#"{"id":"i1","category":"mileage","item_date":"2026-10-10","vehicle_type":"two_wheeler","distance_km":23.4,"amount":93.6}"#)
        let f = saved.toFields()
        XCTAssertEqual(f.distanceKm, "23.4")
        XCTAssertEqual(f.vehicleType, "two_wheeler")
        XCTAssertEqual(f.odometerStart, "")
        XCTAssertTrue(f.isGpsDistanceLine(gps: true))
        // and an odometer line the server worked a distance out for does not turn into one
        let odo = try item(#"{"id":"i2","category":"mileage","vehicle_type":"two_wheeler","distance_km":52,"amount":208,"odometer_start":12340,"odometer_end":12392}"#)
        XCTAssertFalse(odo.toFields().isGpsDistanceLine(gps: true))
    }

    func testTheEditorSavesAnUntouchedGpsLineBackAsItCameWithoutAddingAnOdometer() throws {
        let saved = try item(#"{"id":"i1","category":"mileage","item_date":"2026-10-10","vehicle_type":"two_wheeler","distance_km":23.4,"amount":93.6}"#)
        let input = saved.toFields().toInput(byVehicle: true, routeFields: true, gpsDistance: true)
        XCTAssertEqual(input.id, "i1")
        XCTAssertEqual(input.distance_km, 23.4)
        XCTAssertEqual(input.vehicle_type, "two_wheeler")
        XCTAssertNil(input.amount)
        XCTAssertNil(input.odometer_start)
        XCTAssertNil(input.odometer_end)
    }

    func testReadOnlyViewsSayAVehicleLineWithoutAnOdometerIsAGpsDistance() throws {
        let gps = try item(#"{"id":"i","category":"mileage","vehicle_type":"two_wheeler","distance_km":23.4,"amount":93.6}"#)
        XCTAssertEqual(gps.odometerSummary(vehicles: vehicles), "Two-wheeler · GPS distance")
        // a vehicle with neither distance nor odometer is just the vehicle, as before
        let bare = try item(#"{"id":"j","category":"mileage","vehicle_type":"two_wheeler","amount":0}"#)
        XCTAssertEqual(bare.odometerSummary(vehicles: vehicles), "Two-wheeler")
        // an odometer line is unchanged
        let odo = try item(#"{"id":"k","category":"mileage","vehicle_type":"two_wheeler","distance_km":52,"amount":208,"odometer_start":12340,"odometer_end":12392}"#)
        XCTAssertEqual(odo.odometerSummary(vehicles: vehicles), "Two-wheeler · Odometer 12340 → 12392")
        // a flat-rate mileage line with a distance and no vehicle says nothing, as before
        let flat = try item(#"{"id":"l","category":"mileage","distance_km":10,"amount":120}"#)
        XCTAssertNil(flat.odometerSummary(vehicles: vehicles))
    }

    // MARK: - the line the travel prompt creates

    func testTheLineTheTravelPromptCreatesIsAGpsLineOnceTheServerSavesIt() throws {
        let policy: ExpensePolicyRules = try rules(#"{"gps_distance":true,"vehicle_rates":[{"id":"two_wheeler","label":"Two-wheeler","rate_per_km":4}]}"#)
        let body = TravelPrompt.claimBody(policy, date: "2026-10-10", vehicleId: "two_wheeler", km: 23.4)
        let sent = try XCTUnwrap(body.items.first)
        let sentVehicle: String = sent.vehicle_type ?? ""
        let sentKm: Double = sent.distance_km ?? 0
        // what the server stores for that request: the same vehicle and distance, no odometer, a priced amount
        let json = #"{"id":"i1","category":"mileage","item_date":"2026-10-10","vehicle_type":"\#(sentVehicle)","distance_km":\#(sentKm),"amount":93.6}"#
        let saved = try item(json)
        XCTAssertEqual(saved.vehicle_type, "two_wheeler")
        XCTAssertEqual(saved.distance_km, 23.4)
        XCTAssertTrue(saved.toFields().isGpsDistanceLine(gps: ExpenseLogic.gpsDistanceOn(policy)))
    }
}
