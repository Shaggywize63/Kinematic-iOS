//
//  OdometerTripLogicTests.swift
//  KinematicTests
//
//  The two-step daily odometer trip ("Today's travel"): the rep records the START odometer in the morning and the
//  END odometer in the evening, driven entirely by the policy's opt-in flag. These pin the pure rules behind the
//  card — which step to show, the vehicle to pre-select, the distance between readings, and what each step still
//  needs before it can be saved — and that the wire shapes (GET / start / end / the disabled reply) decode. The
//  SwiftUI card only renders what these decide. Mirrors the Android OdometerTripLogicTest.
//

import XCTest
@testable import Kinematic

final class OdometerTripLogicTests: XCTestCase {

    private let bike = ExpenseVehicleRate(id: "bike", label: "Bike", rate_per_km: 4)
    private let car  = ExpenseVehicleRate(id: "car", label: "Car", rate_per_km: 9)

    private func rules(_ json: String) throws -> ExpensePolicyRules {
        try JSONDecoder().decode(ExpensePolicyRules.self, from: Data(json.utf8))
    }
    private func response(_ json: String) throws -> OdometerTripResponse {
        try JSONDecoder().decode(OdometerTripResponse.self, from: Data(json.utf8))
    }

    // MARK: - the policy gate

    func testTheCardIsOnOnlyWhenThePolicyOptsInAndPaysByVehicle() throws {
        XCTAssertTrue(ExpenseLogic.dailyTripOn(try rules(#"{"odometer_daily_trip":true,"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}]}"#)))
        // Opted in but no vehicles → off (the flow is odometer-by-vehicle).
        XCTAssertFalse(ExpenseLogic.dailyTripOn(try rules(#"{"odometer_daily_trip":true,"vehicle_rates":[]}"#)))
        XCTAssertFalse(ExpenseLogic.dailyTripOn(try rules(#"{"odometer_daily_trip":true}"#)))
        // Has vehicles but not opted in → off (the combined editor stays).
        XCTAssertFalse(ExpenseLogic.dailyTripOn(try rules(#"{"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}]}"#)))
        XCTAssertFalse(ExpenseLogic.dailyTripOn(try rules(#"{"odometer_daily_trip":false,"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}]}"#)))
        XCTAssertFalse(ExpenseLogic.dailyTripOn(nil))
    }

    func testTheFlagDecodesAndIsAbsentOnAnOlderPolicy() throws {
        XCTAssertEqual(try rules(#"{"odometer_daily_trip":true}"#).odometer_daily_trip, true)
        XCTAssertNil(try rules(#"{"mileage_rate":12}"#).odometer_daily_trip)
    }

    // MARK: - status

    func testStatusReadsTheTripElseNone() {
        XCTAssertEqual(OdometerTripLogic.status(nil), .none)
        XCTAssertEqual(OdometerTripLogic.status(OdometerTrip(claim_id: "c", status: "none")), .none)
        XCTAssertEqual(OdometerTripLogic.status(OdometerTrip(claim_id: "c", status: "open")), .open)
        XCTAssertEqual(OdometerTripLogic.status(OdometerTrip(claim_id: "c", status: "closed")), .closed)
        // Anything unexpected is treated as "not started".
        XCTAssertEqual(OdometerTripLogic.status(OdometerTrip(claim_id: "c", status: "weird")), .none)
        XCTAssertEqual(OdometerTripStatus("OPEN"), .open)
    }

    // MARK: - vehicle resolution

    func testTheServersSoleVehicleIsPreSelectedFirst() {
        XCTAssertEqual(OdometerTripLogic.defaultVehicle(soleVehicle: "car", vehicleRates: [bike, car]), "car")
        XCTAssertEqual(OdometerTripLogic.defaultVehicle(soleVehicle: "  ", vehicleRates: [bike]), "bike")
    }

    func testWithExactlyOneVehicleItIsPreSelectedWithSeveralTheRepPicks() {
        XCTAssertEqual(OdometerTripLogic.defaultVehicle(soleVehicle: nil, vehicleRates: [bike]), "bike")
        XCTAssertNil(OdometerTripLogic.defaultVehicle(soleVehicle: nil, vehicleRates: [bike, car]))
        XCTAssertNil(OdometerTripLogic.defaultVehicle(soleVehicle: nil, vehicleRates: []))
        XCTAssertFalse(OdometerTripLogic.vehicleChoiceRequired([bike]))
        XCTAssertTrue(OdometerTripLogic.vehicleChoiceRequired([bike, car]))
        XCTAssertFalse(OdometerTripLogic.vehicleChoiceRequired([]))
    }

    // MARK: - distance

    func testDistanceIsEndMinusStartInOrder() {
        XCTAssertEqual(OdometerTripLogic.distance(start: 12340, end: 12392), 52)
        XCTAssertEqual(OdometerTripLogic.distance(start: 100.5, end: 130.25), 29.75)
        XCTAssertEqual(OdometerTripLogic.distance(start: 0, end: 15), 15)   // a new vehicle can read 0
        XCTAssertNil(OdometerTripLogic.distance(start: nil, end: 10))
        XCTAssertNil(OdometerTripLogic.distance(start: 10, end: nil))
        XCTAssertNil(OdometerTripLogic.distance(start: 5000, end: 4990))    // out of order
    }

    func testReadingAcceptsZeroAndUpRejectsJunk() {
        XCTAssertEqual(OdometerTripLogic.reading(" 12340 "), 12340)
        XCTAssertEqual(OdometerTripLogic.reading("0"), 0)
        XCTAssertNil(OdometerTripLogic.reading(""))
        XCTAssertNil(OdometerTripLogic.reading("abc"))
        XCTAssertNil(OdometerTripLogic.reading("-5"))
    }

    // MARK: - what the start step needs

    func testStartNeedsAReadingAndAVehicleWhenThereAreSeveralAndAPhotoWhenRequired() {
        // Several vehicles, photos required: nothing filled → reading + vehicle + photo missing.
        XCTAssertEqual(OdometerTripLogic.startMissing(readingText: "", vehicle: "", photoURL: "",
                                                      photosRequired: true, vehicleRates: [bike, car]),
                       [.reading, .vehicle, .photo])
        // Reading + vehicle + photo in → ready.
        XCTAssertTrue(OdometerTripLogic.canSaveStart(readingText: "12340", vehicle: "car", photoURL: "https://x/o.jpg",
                                                     photosRequired: true, vehicleRates: [bike, car]))
    }

    func testStartWithASingleVehicleDoesNotDemandAChoice() {
        // One vehicle (pre-selected elsewhere): no vehicle finding even when the field is blank.
        XCTAssertEqual(OdometerTripLogic.startMissing(readingText: "12340", vehicle: "", photoURL: "https://x/o.jpg",
                                                      photosRequired: true, vehicleRates: [bike]),
                       [])
    }

    func testStartPhotoIsOptionalWhenThePolicyDoesNotRequireIt() {
        XCTAssertTrue(OdometerTripLogic.canSaveStart(readingText: "12340", vehicle: "bike", photoURL: "",
                                                     photosRequired: false, vehicleRates: [bike]))
        // Still needs the reading.
        XCTAssertEqual(OdometerTripLogic.startMissing(readingText: "", vehicle: "bike", photoURL: "",
                                                      photosRequired: false, vehicleRates: [bike]),
                       [.reading])
    }

    // MARK: - what the end step needs

    func testEndNeedsAReadingNotBelowTheStartAndAPhotoWhenRequired() {
        XCTAssertEqual(OdometerTripLogic.endMissing(readingText: "", startReading: 12340, photoURL: "", photosRequired: true),
                       [.reading, .photo])
        // Lower than the morning reading is called out.
        XCTAssertEqual(OdometerTripLogic.endMissing(readingText: "12300", startReading: 12340, photoURL: "https://x/e.jpg", photosRequired: true),
                       [.endBelowStart])
        XCTAssertTrue(OdometerTripLogic.canSaveEnd(readingText: "12392", startReading: 12340, photoURL: "https://x/e.jpg", photosRequired: true))
        // Equal readings (a zero-distance day) are allowed.
        XCTAssertTrue(OdometerTripLogic.canSaveEnd(readingText: "12340", startReading: 12340, photoURL: "https://x/e.jpg", photosRequired: true))
    }

    func testEndPhotoIsOptionalWhenThePolicyDoesNotRequireIt() {
        XCTAssertTrue(OdometerTripLogic.canSaveEnd(readingText: "12392", startReading: 12340, photoURL: "", photosRequired: false))
    }

    // MARK: - the review button

    func testReviewButtonInvitesSubmitWhileADraftAndViewsOnceWithAnApprover() {
        XCTAssertEqual(OdometerTripLogic.reviewButtonLabel(claimStatus: "draft"), "Review & submit")
        XCTAssertEqual(OdometerTripLogic.reviewButtonLabel(claimStatus: nil), "Review & submit")
        XCTAssertEqual(OdometerTripLogic.reviewButtonLabel(claimStatus: "rejected"), "Review & submit")
        XCTAssertEqual(OdometerTripLogic.reviewButtonLabel(claimStatus: "submitted"), "View claim")
        XCTAssertEqual(OdometerTripLogic.reviewButtonLabel(claimStatus: "approved"), "View claim")
    }

    // MARK: - dedupe (shared with the editor's picker)

    func testTheVehicleListDropsBlankAndRepeatedIds() {
        let list = [bike, ExpenseVehicleRate(id: "bike", label: "Bike again", rate_per_km: 5),
                    ExpenseVehicleRate(id: "  ", label: "No id", rate_per_km: 6), car]
        XCTAssertEqual(ExpenseLogic.dedupeVehicles(list).map { $0.id }, ["bike", "car"])
        XCTAssertTrue(ExpenseLogic.dedupeVehicles(nil).isEmpty)
    }

    // MARK: - the wire shapes

    func testTheGetReplyWhenNotStartedDecodesWithItsConfig() throws {
        let r = try response(#"""
        {"enabled":true,"date":"2026-10-12","trip":null,
         "vehicle_rates":[{"id":"two_wheeler","label":"Two-wheeler","rate_per_km":4},{"id":"car","label":"Car","rate_per_km":9}],
         "sole_vehicle":null,"photos_required":true,"camera_only":true}
        """#)
        XCTAssertTrue(r.enabled)
        XCTAssertEqual(r.date, "2026-10-12")
        XCTAssertNil(r.trip)
        XCTAssertEqual(OdometerTripLogic.status(r.trip), .none)
        XCTAssertEqual(ExpenseLogic.dedupeVehicles(r.vehicle_rates).map { $0.id }, ["two_wheeler", "car"])
        XCTAssertTrue(r.photos_required)
        XCTAssertTrue(r.camera_only)
        XCTAssertNil(r.claim)
    }

    func testTheDisabledReplyHasOnlyTheThreeFieldsAndNeedsNoConfig() throws {
        // When the flow is not opted in the server sends only { enabled:false, date, trip:null } — the config
        // fields are absent and must default rather than fail the decode.
        let r = try response(#"{"enabled":false,"date":"2026-10-12","trip":null}"#)
        XCTAssertFalse(r.enabled)
        XCTAssertEqual(r.date, "2026-10-12")
        XCTAssertNil(r.trip)
        XCTAssertTrue(r.vehicle_rates.isEmpty)
        XCTAssertNil(r.sole_vehicle)
        XCTAssertTrue(r.photos_required)     // defaulted
        XCTAssertFalse(r.camera_only)        // defaulted
    }

    func testAnOpenTripDecodesWithItsStartAndPhoto() throws {
        let r = try response(#"""
        {"enabled":true,"date":"2026-10-12",
         "trip":{"claim_id":"cl-1","claim_no":"EXP-7","claim_status":"draft","item_id":"it-1","date":"2026-10-12",
                 "vehicle_type":"car","odometer_start":12340,"odometer_end":null,"distance_km":null,"amount":0,
                 "start_photo_url":"https://x/s.jpg","end_photo_url":null,"status":"open","editable":true},
         "vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}],"sole_vehicle":"car","photos_required":true,"camera_only":true}
        """#)
        let t = try XCTUnwrap(r.trip)
        XCTAssertEqual(OdometerTripLogic.status(t), .open)
        XCTAssertEqual(t.odometer_start, 12340)
        XCTAssertNil(t.odometer_end)
        XCTAssertEqual(t.claim_id, "cl-1")
        XCTAssertEqual(t.start_photo_url, "https://x/s.jpg")
        XCTAssertEqual(t.readingsText, "12340 → —")
        XCTAssertEqual(OdometerTripLogic.defaultVehicle(soleVehicle: r.sole_vehicle, vehicleRates: ExpenseLogic.dedupeVehicles(r.vehicle_rates)), "car")
    }

    func testTheEndReplyCarriesTheClosedTripAndTheBuiltClaim() throws {
        let r = try response(#"""
        {"enabled":true,"date":"2026-10-12",
         "trip":{"claim_id":"cl-1","claim_no":"EXP-7","claim_status":"draft","item_id":"it-1","date":"2026-10-12",
                 "vehicle_type":"car","odometer_start":12340,"odometer_end":12392,"distance_km":52,"amount":468,
                 "start_photo_url":"https://x/s.jpg","end_photo_url":"https://x/e.jpg","status":"closed","editable":true},
         "vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}],"sole_vehicle":"car","photos_required":true,"camera_only":true,
         "claim":{"id":"cl-1","claim_no":"EXP-7","status":"draft","currency":"INR","total_amount":468,"distance_km":52}}
        """#)
        let t = try XCTUnwrap(r.trip)
        XCTAssertEqual(OdometerTripLogic.status(t), .closed)
        XCTAssertEqual(t.distance_km, 52)
        XCTAssertEqual(t.amount, 468)
        XCTAssertEqual(t.readingsText, "12340 → 12392")
        XCTAssertEqual(OdometerTripLogic.distance(start: t.odometer_start, end: t.odometer_end), 52)
        let claim = try XCTUnwrap(r.claim)
        XCTAssertEqual(claim.id, "cl-1")
        XCTAssertEqual(claim.total_amount, 468)
    }

    func testTheTripDecodesLenientlyWhenNonOptionalsAreMissing() throws {
        // amount/status/editable absent (e.g. a null amount before the trip closes) must default, never fail.
        let r = try response(#"{"enabled":true,"date":"2026-10-12","trip":{"claim_id":"cl-1","odometer_start":100}}"#)
        let t = try XCTUnwrap(r.trip)
        XCTAssertEqual(t.amount, 0)
        XCTAssertEqual(OdometerTripLogic.status(t), .none)   // no status → "not started"
        XCTAssertTrue(t.editable)
        XCTAssertEqual(t.claim_status, "draft")
    }

    func testTheRequestBodiesSendWhatIsSetAndOmitWhatIsNot() throws {
        let start = OdometerTripStartInput(odometer_start: 12340, vehicle_type: "car", start_photo_url: nil, date: nil)
        let startJSON = String(data: try JSONEncoder().encode(start), encoding: .utf8) ?? ""
        XCTAssertTrue(startJSON.contains("\"odometer_start\":12340"))
        XCTAssertTrue(startJSON.contains("\"vehicle_type\":\"car\""))
        XCTAssertFalse(startJSON.contains("start_photo_url"))   // nil optionals are omitted
        XCTAssertFalse(startJSON.contains("date"))

        let end = OdometerTripEndInput(odometer_end: 12392, end_photo_url: "https://x/e.jpg", date: nil)
        let endJSON = String(data: try JSONEncoder().encode(end), encoding: .utf8) ?? ""
        XCTAssertTrue(endJSON.contains("\"odometer_end\":12392"))
        XCTAssertTrue(endJSON.contains("\"end_photo_url\":\"https://x/e.jpg\""))
        XCTAssertFalse(endJSON.contains("\"date\""))
    }
}
