//
//  OdometerCaptureLogicTests.swift
//  KinematicTests
//
//  The pure rules behind RELOCATING the two-step daily odometer trip into the attendance check-in / check-out flow:
//   • when each capture is offered after a punch — START only before a trip exists, END only while one is open
//     (`OdometerTripLogic.offersStart` / `offersEnd`), driving `OdometerCaptureModel`;
//   • that the manual "New claim" editor no longer offers the mileage ("Travel") category on a daily-trip policy, so
//     there is no way left to enter the before/after odometer together (`ExpenseLogic.editor*`), while every other
//     policy's editor is unchanged.
//  Mirrors the Android relocation change.
//

import XCTest
@testable import Kinematic

final class OdometerCaptureLogicTests: XCTestCase {

    private let car = ExpenseVehicleRate(id: "car", label: "Car", rate_per_km: 9)

    private func rules(_ json: String) throws -> ExpensePolicyRules {
        try JSONDecoder().decode(ExpensePolicyRules.self, from: Data(json.utf8))
    }

    // A daily-trip policy (opted in + pays by vehicle). All built-in categories enabled (no `categories` block).
    private func dailyTripRules() throws -> ExpensePolicyRules {
        try rules(#"{"odometer_daily_trip":true,"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}]}"#)
    }
    // A by-vehicle policy that is NOT a daily trip — the manual editor is untouched for it.
    private func plainVehicleRules() throws -> ExpensePolicyRules {
        try rules(#"{"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}]}"#)
    }

    // MARK: - when each capture is offered

    func testStartIsOfferedOnlyBeforeATripExists() {
        XCTAssertTrue(OdometerTripLogic.offersStart(nil))                                        // never started
        XCTAssertTrue(OdometerTripLogic.offersStart(OdometerTrip(claim_id: "c", status: "none")))
        XCTAssertFalse(OdometerTripLogic.offersStart(OdometerTrip(claim_id: "c", status: "open")))   // already started
        XCTAssertFalse(OdometerTripLogic.offersStart(OdometerTrip(claim_id: "c", status: "closed"))) // done
    }

    func testEndIsOfferedOnlyWhileATripIsOpen() {
        XCTAssertTrue(OdometerTripLogic.offersEnd(OdometerTrip(claim_id: "c", status: "open")))
        XCTAssertFalse(OdometerTripLogic.offersEnd(nil))
        XCTAssertFalse(OdometerTripLogic.offersEnd(OdometerTrip(claim_id: "c", status: "none")))
        XCTAssertFalse(OdometerTripLogic.offersEnd(OdometerTrip(claim_id: "c", status: "closed")))
    }

    // MARK: - the manual editor drops the mileage category on a daily-trip policy

    func testDailyTripEditorHidesMileageFromANewLinesChoices() throws {
        let r = try dailyTripRules()
        let choices = ExpenseLogic.editorAllowedCategories(r, current: "food")
        XCTAssertFalse(choices.contains("mileage"), "Travel is recorded at check-in/out — not offered in the editor")
        XCTAssertTrue(choices.contains("food"))
        XCTAssertTrue(choices.contains("lodging"))
    }

    func testDailyTripEditorKeepsMileageForAnExistingMileageLineSoItCanMoveOff() throws {
        let r = try dailyTripRules()
        // An older line already on mileage still renders and can be switched to another category…
        let choices = ExpenseLogic.editorAllowedCategories(r, current: "mileage")
        XCTAssertTrue(choices.contains("mileage"))     // kept because it is the current category
        XCTAssertTrue(choices.contains("food"))
        // …but a fresh non-mileage line can never switch TO mileage.
        XCTAssertFalse(ExpenseLogic.editorAllowedCategories(r, current: "food").contains("mileage"))
    }

    func testDailyTripEditorNeverDefaultsANewClaimToMileage() throws {
        // Normal multi-category daily-trip policy → the usual "food" default (never mileage).
        XCTAssertEqual(ExpenseLogic.editorDefaultCategory(try dailyTripRules()), "food")
        // Even a policy whose ONLY enabled category is mileage must not default (or offer) mileage in the editor.
        let onlyMileage = try rules(#"""
        {"odometer_daily_trip":true,"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}],
         "categories":{"travel":{"enabled":false},"food":{"enabled":false},"lodging":{"enabled":false},
                       "fuel":{"enabled":false},"toll":{"enabled":false},"misc":{"enabled":false}}}
        """#)
        XCTAssertNotEqual(ExpenseLogic.editorDefaultCategory(onlyMileage), "mileage")
    }

    func testDailyTripEditorForcesTheOneRemainingCategoryWhenOnlyMileageAndOneOtherAreEnabled() throws {
        // Enabled: mileage + food only → after dropping mileage, "food" is the single editor category.
        let r = try rules(#"""
        {"odometer_daily_trip":true,"vehicle_rates":[{"id":"car","label":"Car","rate_per_km":9}],
         "categories":{"travel":{"enabled":false},"lodging":{"enabled":false},
                       "fuel":{"enabled":false},"toll":{"enabled":false},"misc":{"enabled":false}}}
        """#)
        XCTAssertEqual(ExpenseLogic.editorSingleCategory(r), "food")
        XCTAssertFalse(ExpenseLogic.editorShowsCategoryPicker(r, current: "food"))
        XCTAssertEqual(ExpenseLogic.editorDefaultCategory(r), "food")
    }

    // MARK: - every other policy's editor is unchanged

    func testTheEditorIsUnchangedForANonDailyTripPolicy() throws {
        let r = try plainVehicleRules()
        for current in ["food", "mileage"] {
            XCTAssertEqual(ExpenseLogic.editorAllowedCategories(r, current: current),
                           ExpenseLogic.allowedCategories(r, current: current))
            XCTAssertEqual(ExpenseLogic.editorShowsCategoryPicker(r, current: current),
                           ExpenseLogic.showsCategoryPicker(r, current: current))
        }
        XCTAssertEqual(ExpenseLogic.editorSingleCategory(r), ExpenseLogic.singleCategory(r))
        XCTAssertEqual(ExpenseLogic.editorDefaultCategory(r), ExpenseLogic.defaultCategory(r))
        // A non-daily-trip by-vehicle policy still offers mileage in the manual editor (the combined editor).
        XCTAssertTrue(ExpenseLogic.editorAllowedCategories(r, current: "food").contains("mileage"))
    }
}
