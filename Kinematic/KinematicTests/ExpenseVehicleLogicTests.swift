//
//  ExpenseVehicleLogicTests.swift
//  KinematicTests
//
//  Travel allowance by vehicle: the rep picks a vehicle and enters the odometer before / after (with a
//  photo of each); the server works out the distance and the amount. These pin what the app sends and
//  shows, and that a policy WITHOUT vehicle rates behaves exactly as before. Mirrors the Android
//  ExpenseVehicleLogicTest.
//

import XCTest
@testable import Kinematic

final class ExpenseVehicleLogicTests: XCTestCase {

    private let vehicles = [
        ExpenseVehicleRate(id: "two_wheeler", label: "Two-wheeler", rate_per_km: 4),
        ExpenseVehicleRate(id: "car", label: "Car", rate_per_km: 9),
    ]

    private func trip(vehicle: String = "two_wheeler", start: String = "12340", end: String = "12392") -> ExpenseLineFields {
        var f = ExpenseLineFields()
        f.category = "mileage"
        f.vehicleType = vehicle
        f.odometerStart = start
        f.odometerEnd = end
        return f
    }

    // MARK: distance and amount

    func testDistanceIsAfterMinusBefore() {
        XCTAssertEqual(trip().odometerKm, 52)
        XCTAssertEqual(trip(start: "100.5", end: "130.25").odometerKm, 29.75)
        // A reading of zero is a real reading.
        XCTAssertEqual(trip(start: "0", end: "15").odometerKm, 15)
    }

    func testDistanceIsUnknownUntilBothReadingsAreInOrder() {
        XCTAssertNil(trip(end: "").odometerKm)
        XCTAssertNil(trip(start: "").odometerKm)
        XCTAssertNil(trip(start: "5000", end: "4990").odometerKm)
        XCTAssertNil(trip(start: "abc", end: "10").odometerKm)
        XCTAssertNil(trip(start: "-5", end: "10").odometerKm)
    }

    func testALowerReadingAfterTheTripIsCalledOutAnIncompletePairIsNot() {
        XCTAssertEqual(trip(start: "5000", end: "4990").odometerOrderProblem,
                       "The reading after the trip is lower than the reading before it.")
        XCTAssertNil(trip(end: "").odometerOrderProblem)
        XCTAssertNil(trip().odometerOrderProblem)
    }

    func testTheAmountIsTheDistanceTimesTheChosenVehiclesRate() {
        XCTAssertEqual(trip().effectiveAmount(mileageRate: 12, vehicles: vehicles), 208)
        XCTAssertEqual(trip(vehicle: "car").effectiveAmount(mileageRate: 12, vehicles: vehicles), 468)
        // Nothing to price yet: no vehicle, an unlisted vehicle, or an incomplete pair.
        XCTAssertEqual(trip(vehicle: "").effectiveAmount(mileageRate: 12, vehicles: vehicles), 0)
        XCTAssertEqual(trip(vehicle: "tractor").effectiveAmount(mileageRate: 12, vehicles: vehicles), 0)
        XCTAssertEqual(trip(end: "").effectiveAmount(mileageRate: 12, vehicles: vehicles), 0)
    }

    func testATypedAmountNeverOverridesTheOdometerPricing() {
        var f = trip()
        f.amount = "9999"
        XCTAssertEqual(f.effectiveAmount(mileageRate: 12, vehicles: vehicles), 208)
    }

    func testWithoutVehicleRatesMileageIsPricedExactlyAsBefore() {
        var km = ExpenseLineFields()
        km.category = "mileage"
        km.distanceKm = "40"
        XCTAssertEqual(km.effectiveAmount(mileageRate: 12), 480)
        XCTAssertEqual(km.effectiveAmount(mileageRate: 12, vehicles: nil), 480)
        XCTAssertEqual(km.effectiveAmount(mileageRate: 12, vehicles: []), 480)
        km.amount = "500"
        XCTAssertEqual(km.effectiveAmount(mileageRate: 12), 500)
        // Other categories are unaffected by vehicles.
        var food = ExpenseLineFields()
        food.category = "food"
        food.amount = "250"
        XCTAssertEqual(food.effectiveAmount(mileageRate: 12, vehicles: vehicles), 250)
    }

    // MARK: what can be saved

    func testAByVehicleDraftNeedsOnlySomethingToGoOn() {
        var blank = ExpenseLineFields()
        blank.category = "mileage"
        blank.fromLocation = "Nashik"
        XCTAssertFalse(blank.canSave(byVehicle: true))
        var withVehicle = blank; withVehicle.vehicleType = "car"
        XCTAssertTrue(withVehicle.canSave(byVehicle: true))
        var withReading = blank; withReading.odometerStart = "12340"
        XCTAssertTrue(withReading.canSave(byVehicle: true))
        // The flat flow still wants an amount or a distance.
        XCTAssertFalse(withVehicle.isValid)
        var flat = ExpenseLineFields(); flat.category = "mileage"; flat.distanceKm = "10"
        XCTAssertTrue(flat.isValid)
    }

    func testAnyVehicleOrOdometerEntryCountsAsFilled() {
        XCTAssertFalse(ExpenseLineFields().isFilled)
        var a = ExpenseLineFields(); a.vehicleType = "car"; XCTAssertTrue(a.isFilled)
        var b = ExpenseLineFields(); b.odometerEnd = "10"; XCTAssertTrue(b.isFilled)
        var c = ExpenseLineFields(); c.odoStartPhoto = "https://x/o.jpg"; XCTAssertTrue(c.isFilled)
    }

    // MARK: what is sent

    func testAByVehicleLineSendsTheReadingsNeverADistanceOrAnAmount() {
        var f = trip()
        f.id = "l1"; f.amount = "9999"; f.distanceKm = "70"
        f.odoStartPhoto = "https://x/a.jpg"; f.odoEndPhoto = "https://x/b.jpg"
        let sent = f.toInput(byVehicle: true)
        XCTAssertEqual(sent.vehicle_type, "two_wheeler")
        XCTAssertEqual(sent.odometer_start, 12340)
        XCTAssertEqual(sent.odometer_end, 12392)
        XCTAssertEqual(sent.odometer_start_photo_url, "https://x/a.jpg")
        XCTAssertEqual(sent.odometer_end_photo_url, "https://x/b.jpg")
        XCTAssertNil(sent.amount)
        XCTAssertNil(sent.distance_km)
        XCTAssertEqual(sent.id, "l1")
    }

    func testTheVehicleFlowSendsFromAndToUnlessThePolicyTurnsTheRouteOff() {
        var f = trip()
        f.fromLocation = " Nashik "; f.toLocation = "Pune"
        let withRoute = f.toInput(byVehicle: true)
        XCTAssertEqual(withRoute.from_location, "Nashik")
        XCTAssertEqual(withRoute.to_location, "Pune")
        // Route off: nothing about the route is sent; the readings and photos are untouched.
        f.odoStartPhoto = "https://x/a.jpg"
        let off = f.toInput(byVehicle: true, routeFields: false)
        XCTAssertNil(off.from_location)
        XCTAssertNil(off.to_location)
        XCTAssertEqual(off.vehicle_type, "two_wheeler")
        XCTAssertEqual(off.odometer_start, 12340)
        XCTAssertEqual(off.odometer_end, 12392)
        XCTAssertEqual(off.odometer_start_photo_url, "https://x/a.jpg")
    }

    func testOnlyAPolicyWithVehicleRatesIsPaidByVehicle() throws {
        func rules(_ json: String) throws -> ExpensePolicyRules { try JSONDecoder().decode(ExpensePolicyRules.self, from: Data(json.utf8)) }
        XCTAssertTrue(ExpenseLogic.paysByVehicle(try rules(#"{"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}]}"#)))
        XCTAssertFalse(ExpenseLogic.paysByVehicle(try rules(#"{"vehicle_rates":[]}"#)))
        XCTAssertFalse(ExpenseLogic.paysByVehicle(try rules(#"{"mileage_rate":12}"#)))
        XCTAssertFalse(ExpenseLogic.paysByVehicle(nil))
    }

    func testACameraPhotoReadByTheServerFillsTheReadingBeforeThePairIsComplete() {
        var f = ExpenseLineFields()
        f.category = "mileage"; f.vehicleType = "two_wheeler"
        XCTAssertEqual(f.applyOdometerScan(ExpenseOdometerScan(reading: 12340, confidence: "high"), start: true), .read)
        XCTAssertNil(f.odometerKm)      // still waiting for the after-trip photo
        XCTAssertEqual(f.applyOdometerScan(ExpenseOdometerScan(reading: 12392, confidence: "medium"), start: false), .read)
        XCTAssertEqual(f.odometerKm, 52)
        XCTAssertEqual(f.effectiveAmount(mileageRate: 12, vehicles: vehicles), 208)
        XCTAssertEqual(f.toInput(byVehicle: true).odometer_end, 12392)
    }

    func testARemovedOdometerPhotoIsClearedWithAnEmptyStringOneNeverAddedIsOmitted() {
        var f = trip()
        f.odoStartPhoto = ""; f.hadOdoStartPhoto = true
        XCTAssertEqual(f.toInput(byVehicle: true).odometer_start_photo_url, "")
        let never = trip().toInput(byVehicle: true)
        XCTAssertNil(never.odometer_start_photo_url)
        XCTAssertNil(never.odometer_end_photo_url)
    }

    func testAnUnfinishedReadingIsLeftOutRatherThanSentAsZero() {
        let sent = trip(end: "").toInput(byVehicle: true)
        XCTAssertEqual(sent.odometer_start, 12340)
        XCTAssertNil(sent.odometer_end)
    }

    func testWithoutVehicleRatesNothingAboutOdometersIsSent() {
        var f = trip(); f.distanceKm = "52"
        let sent = f.toInput()
        XCTAssertNil(sent.vehicle_type)
        XCTAssertNil(sent.odometer_start)
        XCTAssertNil(sent.odometer_end)
        XCTAssertEqual(sent.distance_km, 52)
        // A non-mileage line never carries them either, whatever the policy.
        var food = ExpenseLineFields(); food.category = "food"; food.amount = "250"; food.vehicleType = "car"; food.odometerStart = "1"
        let sentFood = food.toInput(byVehicle: true)
        XCTAssertNil(sentFood.vehicle_type)
        XCTAssertNil(sentFood.odometer_start)
    }

    func testTheWireBodyLeavesOutWhatWasNotSet() throws {
        var food = ExpenseLineFields(); food.category = "food"; food.amount = "250"
        let plain = String(data: try JSONEncoder().encode(food.toInput()), encoding: .utf8) ?? ""
        XCTAssertFalse(plain.contains("odometer"))
        XCTAssertFalse(plain.contains("vehicle_type"))
        let trip = String(data: try JSONEncoder().encode(self.trip().toInput(byVehicle: true)), encoding: .utf8) ?? ""
        XCTAssertTrue(trip.contains("\"vehicle_type\":\"two_wheeler\""))
        XCTAssertTrue(trip.contains("\"odometer_start\":12340"))
    }

    // MARK: what comes back

    func testASavedByVehicleLineRoundTripsIntoTheEditor() throws {
        let json = """
        {"id":"i","category":"mileage","amount":208,"vehicle_type":"two_wheeler","odometer_start":12340,"odometer_end":12392.5,
         "odometer_start_photo_url":"https://x/a.jpg"}
        """
        let item = try JSONDecoder().decode(ExpenseClaimItem.self, from: Data(json.utf8))
        let f = item.toFields()
        XCTAssertEqual(f.vehicleType, "two_wheeler")
        XCTAssertEqual(f.odometerStart, "12340")
        XCTAssertEqual(f.odometerEnd, "12392.5")
        XCTAssertEqual(f.odoStartPhoto, "https://x/a.jpg")
        XCTAssertTrue(f.hadOdoStartPhoto)
        XCTAssertFalse(f.hadOdoEndPhoto)
    }

    func testThePolicysVehicleRatesAndThePhotoSwitchDecode() throws {
        let json = """
        {"currency":"INR","mileage_rate":12,"require_receipt_over":500,
         "rules":{"mileage_rate":12,"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}],"odometer_photos_required":false}}
        """
        let p = try JSONDecoder().decode(ExpensePolicy.self, from: Data(json.utf8))
        XCTAssertEqual(p.rules?.vehicle_rates?.map { $0.id }, ["car"])
        XCTAssertEqual(p.rules?.vehicle_rates?.first?.rate_per_km, 9)
        XCTAssertEqual(p.rules?.odometer_photos_required, false)
        // An older policy payload has neither.
        let old = try JSONDecoder().decode(ExpensePolicy.self, from: Data(#"{"currency":"INR","mileage_rate":12,"require_receipt_over":500,"rules":{"mileage_rate":12}}"#.utf8))
        XCTAssertNil(old.rules?.vehicle_rates)
        XCTAssertNil(old.rules?.odometer_photos_required)
    }

    func testReadOnlyViewsNameTheVehicleAndShowTheReadings() throws {
        let json = #"{"id":"i","category":"mileage","amount":208,"vehicle_type":"two_wheeler","odometer_start":12340,"odometer_end":12392}"#
        let item = try JSONDecoder().decode(ExpenseClaimItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.odometerSummary(vehicles: vehicles), "Two-wheeler · Odometer 12340 → 12392")
        // The policy no longer lists the vehicle: fall back to a readable id.
        XCTAssertEqual(item.odometerSummary(), "Two wheeler · Odometer 12340 → 12392")
        let plain = try JSONDecoder().decode(ExpenseClaimItem.self, from: Data(#"{"id":"j","category":"mileage","amount":0,"distance_km":10}"#.utf8))
        XCTAssertNil(plain.odometerSummary(vehicles: vehicles))
        let food = try JSONDecoder().decode(ExpenseClaimItem.self, from: Data(#"{"id":"k","category":"food","amount":5,"vehicle_type":"car"}"#.utf8))
        XCTAssertNil(food.odometerSummary(vehicles: vehicles))
    }

    func testTheOdometerFindingsHavePlainLanguageNames() {
        XCTAssertEqual(ExpenseLogic.flagLabel("vehicle_missing"), "Pick a vehicle")
        XCTAssertEqual(ExpenseLogic.flagLabel("odometer_missing"), "Odometer reading needed")
        XCTAssertEqual(ExpenseLogic.flagLabel("odometer_invalid"), "Odometer reading wrong")
        XCTAssertEqual(ExpenseLogic.flagLabel("odometer_photo_missing"), "Odometer photo needed")
    }
}
