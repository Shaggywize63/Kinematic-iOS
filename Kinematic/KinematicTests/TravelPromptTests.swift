//
//  TravelPromptTests.swift
//  KinematicTests
//
//  "Add today's travel to expenses?": when it is offered (only a policy with `gps_distance` and vehicle rates), what the
//  server's answer means, the amount shown, the draft claim that is created and what "Not now" remembers per day. Also
//  the decoding of `GET /attendance/travel`. Mirrors the Android TravelPromptTest and TravelModelsTest.
//

import XCTest
@testable import Kinematic

@MainActor
final class TravelPromptTests: XCTestCase {

    private let two = ExpenseVehicleRate(id: "two_wheeler", label: "Two wheeler", rate_per_km: 4)
    private let car = ExpenseVehicleRate(id: "car", label: "Car", rate_per_km: 11.5)

    /// A policy's `rules` as the server would send them. `vehicles` nil = no `vehicle_rates` key at all.
    private func rules(gps: Bool? = true, vehicles: [ExpenseVehicleRate]?, labels: [String: String]? = nil) throws -> ExpensePolicyRules {
        var object: [String: Any] = [:]
        if let g = gps { object["gps_distance"] = g }
        if let list = vehicles {
            object["vehicle_rates"] = list.map { v -> [String: Any] in
                ["id": v.id, "label": v.label, "rate_per_km": v.rate_per_km]
            }
        }
        if let l = labels { object["category_labels"] = l }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(ExpensePolicyRules.self, from: data)
    }

    private func standard() throws -> ExpensePolicyRules {
        try rules(vehicles: [two, car])
    }

    // MARK: - when is it offered?

    func testAPolicyWithGpsDistanceAndVehicleRatesOnAClientWithExpensesQualifies() throws {
        XCTAssertTrue(TravelPrompt.eligible(rules: try standard(), expensesEnabled: true, signedIn: true))
    }

    func testNothingIsOfferedWithoutTheSwitchTheVehiclesTheModuleOrAUser() throws {
        XCTAssertFalse(TravelPrompt.eligible(rules: try rules(gps: nil, vehicles: [two, car]), expensesEnabled: true, signedIn: true))
        XCTAssertFalse(TravelPrompt.eligible(rules: try rules(gps: false, vehicles: [two, car]), expensesEnabled: true, signedIn: true))
        XCTAssertFalse(TravelPrompt.eligible(rules: try rules(vehicles: nil), expensesEnabled: true, signedIn: true))
        XCTAssertFalse(TravelPrompt.eligible(rules: try rules(vehicles: []), expensesEnabled: true, signedIn: true))
        let nameless = ExpenseVehicleRate(id: "", label: "Nameless", rate_per_km: 4)
        XCTAssertFalse(TravelPrompt.eligible(rules: try rules(vehicles: [nameless]), expensesEnabled: true, signedIn: true))
        XCTAssertFalse(TravelPrompt.eligible(rules: try standard(), expensesEnabled: false, signedIn: true))
        XCTAssertFalse(TravelPrompt.eligible(rules: try standard(), expensesEnabled: true, signedIn: false))
        // a policy that could not be fetched
        XCTAssertFalse(TravelPrompt.eligible(rules: nil, expensesEnabled: true, signedIn: true))
        // the default policy rules (what most clients have)
        let plain = try JSONDecoder().decode(ExpensePolicyRules.self, from: Data("{}".utf8))
        XCTAssertFalse(TravelPrompt.eligible(rules: plain, expensesEnabled: true, signedIn: true))
    }

    func testTheSheetOffersThePoliciesVehiclesInItsOrderWithoutBlanksOrRepeats() throws {
        let again = ExpenseVehicleRate(id: "car", label: "Car again", rate_per_km: 1)
        let blank = ExpenseVehicleRate(id: "", label: "x", rate_per_km: 1)
        let list = TravelPrompt.vehicles(try rules(vehicles: [car, blank, two, again]))
        XCTAssertEqual(list.map { $0.id }, ["car", "two_wheeler"])
        XCTAssertEqual(list.first?.label, "Car")
        XCTAssertTrue(TravelPrompt.vehicles(nil).isEmpty)
    }

    func testTheVehicleIsChosenForTheRepOnlyWhenThePolicyHasExactlyOne() throws {
        XCTAssertEqual(TravelPrompt.defaultVehicle(try rules(vehicles: [two])), "two_wheeler")
        XCTAssertNil(TravelPrompt.defaultVehicle(try rules(vehicles: [two, car])))
        let twice = ExpenseVehicleRate(id: "two_wheeler", label: "again", rate_per_km: 5)
        XCTAssertEqual(TravelPrompt.defaultVehicle(try rules(vehicles: [two, twice])), "two_wheeler")
        XCTAssertNil(TravelPrompt.defaultVehicle(nil))
    }

    // MARK: - today's mode of transport pre-selects the vehicle

    func testAModeThatIsAVehicleOfThePolicyPreSelectsIt() throws {
        let r = try standard()
        XCTAssertEqual(TravelPrompt.vehicleForMode(r, modeId: "two_wheeler"), "two_wheeler")
        XCTAssertEqual(TravelPrompt.vehicleForMode(r, modeId: "car"), "car")
        XCTAssertEqual(TravelPrompt.initialVehicle(r, modeId: "car"), "car")
        // the policy's own ids, not a fixed list
        let ownBike = ExpenseVehicleRate(id: "own_bike", label: "Own Bike", rate_per_km: 3.5)
        let own = try rules(vehicles: [ownBike, car])
        XCTAssertEqual(TravelPrompt.vehicleForMode(own, modeId: "own_bike"), "own_bike")
        XCTAssertNil(TravelPrompt.vehicleForMode(own, modeId: "two_wheeler"))
    }

    func testPublicTransportOtherAnUnknownVehicleOrNoModeDoNothingSpecial() throws {
        let r = try standard()
        let modes: [String?] = ["public_transport", "other", "auto_rickshaw", "", "  ", nil]
        for mode in modes {
            XCTAssertNil(TravelPrompt.vehicleForMode(r, modeId: mode), mode ?? "nil")
            // with several vehicles the rep still chooses
            XCTAssertNil(TravelPrompt.initialVehicle(r, modeId: mode), mode ?? "nil")
        }
        XCTAssertNil(TravelPrompt.vehicleForMode(nil, modeId: "car"))
        XCTAssertNil(TravelPrompt.vehicleForMode(try rules(vehicles: []), modeId: "car"))
    }

    func testTheStartVehicleIsTheModeElseTheOnlyVehicleElseNoneAndWithoutAModeItIsTheOldDefault() throws {
        // one vehicle: it stays chosen whatever the mode says
        let one = try rules(vehicles: [two])
        XCTAssertEqual(TravelPrompt.initialVehicle(one, modeId: "public_transport"), "two_wheeler")
        XCTAssertEqual(TravelPrompt.initialVehicle(one, modeId: "car"), "two_wheeler")   // not this policy's vehicle: nothing special
        XCTAssertEqual(TravelPrompt.initialVehicle(one, modeId: "two_wheeler"), "two_wheeler")
        // no mode: exactly the pre-existing default, for every policy shape
        let several: ExpensePolicyRules = try standard()
        let empty: ExpensePolicyRules = try rules(vehicles: [])
        let absent: ExpensePolicyRules = try rules(vehicles: nil)
        let shapes: [ExpensePolicyRules?] = [several, one, empty, absent, nil]
        for r in shapes {
            XCTAssertEqual(TravelPrompt.initialVehicle(r, modeId: nil), TravelPrompt.defaultVehicle(r))
        }
    }

    // MARK: - the day

    func testTheDayIsTheIndiaDayEitherSideOfMidnight() {
        // 2026-10-10 18:29:59 UTC = 23:59:59 IST (still the 10th); one second later it is the 11th in India
        let beforeMidnight = Date(timeIntervalSince1970: 1_791_656_999)
        XCTAssertEqual(TravelPrompt.istDate(beforeMidnight), "2026-10-10")
        XCTAssertEqual(TravelPrompt.istDate(beforeMidnight.addingTimeInterval(1)), "2026-10-11")
        XCTAssertEqual(TravelPrompt.istDate(Date(timeIntervalSince1970: 1_791_590_400)), "2026-10-10")
    }

    // MARK: - what was decided, per user and day

    private let user = "11111111-1111-1111-1111-111111111111"
    private let other = "22222222-2222-2222-2222-222222222222"

    func testEachChoiceRoundTripsForTheSameUserAndDay() {
        for m in TravelPrompt.Memory.allCases {
            let raw = TravelPrompt.encodeMemory(userId: user, date: "2026-10-10", memory: m)
            XCTAssertNotNil(raw)
            XCTAssertEqual(TravelPrompt.decodeMemory(raw, userId: user, date: "2026-10-10"), m)
        }
        XCTAssertEqual(TravelPrompt.encodeMemory(userId: user, date: "2026-10-10", memory: .snoozed), "\(user)|2026-10-10|snoozed")
    }

    func testAChoiceBelongsToOneUserAndOneDayOnly() {
        let raw = TravelPrompt.encodeMemory(userId: user, date: "2026-10-10", memory: .snoozed)
        XCTAssertNil(TravelPrompt.decodeMemory(raw, userId: other, date: "2026-10-10"))
        XCTAssertNil(TravelPrompt.decodeMemory(raw, userId: user, date: "2026-10-11"))   // tomorrow the prompt is fresh again
        XCTAssertNil(TravelPrompt.decodeMemory(raw, userId: nil, date: "2026-10-10"))
    }

    func testNothingIsRememberedWithoutAUserAndJunkReadsAsNoChoice() {
        XCTAssertNil(TravelPrompt.encodeMemory(userId: nil, date: "2026-10-10", memory: .added))
        XCTAssertNil(TravelPrompt.encodeMemory(userId: "  ", date: "2026-10-10", memory: .added))
        XCTAssertNil(TravelPrompt.encodeMemory(userId: "a|b", date: "2026-10-10", memory: .added))
        let junk: [String?] = [nil, "", "garbage", "\(user)|2026-10-10", "\(user)|2026-10-10|later", "\(user)|2026-10-10|added|x"]
        for bad in junk {
            XCTAssertNil(TravelPrompt.decodeMemory(bad, userId: user, date: "2026-10-10"), bad ?? "nil")
        }
    }

    func testTheSheetPopsUpOnceOnlyWhenNothingWasDecidedThatDay() {
        XCTAssertTrue(TravelPrompt.autoShow(eligible: true, memory: nil))
        for m in TravelPrompt.Memory.allCases {
            XCTAssertFalse(TravelPrompt.autoShow(eligible: true, memory: m), m.rawValue)
        }
        XCTAssertFalse(TravelPrompt.autoShow(eligible: false, memory: nil))
    }

    func testTheHomeCardStaysAfterNotNowAndGoesOnceAddedOrClosed() {
        XCTAssertTrue(TravelPrompt.showCard(eligible: true, shiftCompleted: true, memory: nil))
        XCTAssertTrue(TravelPrompt.showCard(eligible: true, shiftCompleted: true, memory: .snoozed))
        XCTAssertFalse(TravelPrompt.showCard(eligible: true, shiftCompleted: true, memory: .added))
        XCTAssertFalse(TravelPrompt.showCard(eligible: true, shiftCompleted: true, memory: .dismissed))
    }

    func testTheHomeCardNeedsAFinishedShiftAndAnEligiblePolicy() {
        XCTAssertFalse(TravelPrompt.showCard(eligible: true, shiftCompleted: false, memory: nil))
        XCTAssertFalse(TravelPrompt.showCard(eligible: false, shiftCompleted: true, memory: nil))
    }

    func testTheMemoryLivesInOneKeyThatSignOutRemoves() {
        let suite = "TravelPromptTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("could not create a UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(TravelPromptStore.read(in: defaults))
        TravelPromptStore.write("\(user)|2026-10-10|added", in: defaults)
        XCTAssertEqual(TravelPromptStore.read(in: defaults), "\(user)|2026-10-10|added")
        XCTAssertEqual(defaults.string(forKey: "travel_prompt_memory"), "\(user)|2026-10-10|added")
        TravelPromptStore.write(nil, in: defaults)
        XCTAssertNil(TravelPromptStore.read(in: defaults))
    }

    // MARK: - what the server said

    private func summary(km: Double? = 23.4, attendanceId: String? = "att-1", method: String? = "gps_trail",
                         inProgress: Bool? = false, legs: Int = 3) -> TravelSummary {
        TravelSummary(date: "2026-10-10", attendanceId: attendanceId, inProgress: inProgress, totalKm: km, method: method,
                      legs: (0..<legs).map { TravelLeg(index: $0, km: 1.0) })
    }

    func testADayWithDistanceIsReadyToClaimWithItsLegCount() {
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: summary(), error: nil), .ready(km: 23.4, legs: 3, method: "gps_trail"))
    }

    func testTheDistanceIsRoundedToTwoDecimals() {
        if case let .ready(km, _, _) = TravelPrompt.outcomeOf(summary: summary(km: 12.3456), error: nil) {
            XCTAssertEqual(km, 12.35, accuracy: 0.0001)
        } else {
            XCTFail("expected a ready outcome")
        }
        XCTAssertEqual(TravelPrompt.roundKm(0.004), 0.0, accuracy: 0.0001)
        XCTAssertEqual(TravelPrompt.roundKm(2.0), 2.0, accuracy: 0.0001)
    }

    func testNoAttendanceMethodNoneZeroOrMissingDistanceIsHonestlyNothingToClaim() {
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: summary(km: 0.0), error: nil), .noTravel)
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: summary(km: 0.004), error: nil), .noTravel)
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: summary(km: nil), error: nil), .noTravel)
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: summary(km: 0.0, attendanceId: nil, method: "none", legs: 0), error: nil), .noTravel)
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: summary(km: 5.0, attendanceId: ""), error: nil), .noTravel)
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: summary(km: 5.0, method: "none"), error: nil), .noTravel)
    }

    func testAnOpenShiftTheCheckOutIsStillQueuedIsNotFinal() {
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: summary(inProgress: true), error: nil), .notSynced)
    }

    func testAFailedCallIsAFailureMessageNeverAZeroClaim() {
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: nil, error: "offline"), .unavailable("offline"))
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: nil, error: nil), .unavailable("Couldn't load today's travel."))
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: nil, error: "  "), .unavailable("Couldn't load today's travel."))
    }

    func testAConnectionProblemSaysSoAndAnythingElseShowsTheServersReason() {
        let offline = TravelPrompt.failureMessage(URLError(.notConnectedToInternet))
        XCTAssertTrue(offline.contains("Check your connection"), offline)
        let reason = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "No GPS travel recorded for 2026-10-10"])
        XCTAssertEqual(TravelPrompt.failureMessage(reason), "No GPS travel recorded for 2026-10-10")
    }

    func testTheLegCountAndTheEstimateNoteReadWell() {
        XCTAssertEqual(TravelPrompt.legsText(1), "1 leg")
        XCTAssertEqual(TravelPrompt.legsText(0), "0 legs")
        XCTAssertEqual(TravelPrompt.legsText(3), "3 legs")
        XCTAssertEqual(TravelPrompt.kmText(23.4), "23.4 km")
        XCTAssertEqual(TravelPrompt.kmText(20.0), "20 km")
        XCTAssertNil(TravelPrompt.methodNote("gps_trail"))
        XCTAssertNil(TravelPrompt.methodNote(nil))
        XCTAssertNotNil(TravelPrompt.methodNote("straight_line"))
        XCTAssertNotNil(TravelPrompt.methodNote("mixed"))
    }

    func testAnAlreadyClaimedAnswerFromTheServerIsRecognised() {
        XCTAssertTrue(TravelPrompt.isAlreadyClaimed("Travel for 2026-10-10 is already claimed on EXP-12"))
        XCTAssertTrue(TravelPrompt.isAlreadyClaimed("ALREADY CLAIMED"))
        XCTAssertFalse(TravelPrompt.isAlreadyClaimed("No GPS travel recorded for 2026-10-10"))
        XCTAssertFalse(TravelPrompt.isAlreadyClaimed(nil))
    }

    // MARK: - the amount and the claim

    func testThePreviewIsDistanceTimesTheChosenVehiclesRate() throws {
        let a = try XCTUnwrap(TravelPrompt.amountPreview(km: 23.4, vehicle: two))
        let b = try XCTUnwrap(TravelPrompt.amountPreview(km: 10.0, vehicle: car))
        let c = try XCTUnwrap(TravelPrompt.amountPreview(km: 2.5, vehicle: car))
        let d = try XCTUnwrap(TravelPrompt.amountPreview(km: 0.0, vehicle: car))
        XCTAssertEqual(a, 93.6, accuracy: 0.0001)
        XCTAssertEqual(b, 115.0, accuracy: 0.0001)
        XCTAssertEqual(c, 28.75, accuracy: 0.0001)
        XCTAssertEqual(d, 0.0, accuracy: 0.0001)
    }

    func testThereIsNoPreviewUntilAVehicleIsChosen() {
        XCTAssertNil(TravelPrompt.amountPreview(km: 23.4, vehicle: nil))
    }

    func testAChipSaysTheVehicleAndItsRate() {
        XCTAssertEqual(TravelPrompt.chipLabel(two, currency: "INR"), "Two wheeler · ₹4/km")
        XCTAssertEqual(TravelPrompt.chipLabel(car, currency: "INR"), "Car · ₹11.5/km")
        XCTAssertEqual(TravelPrompt.chipLabel(two, currency: "USD"), "Two wheeler · USD 4/km")
        // a vehicle without a label falls back to a readable id
        let unnamed = ExpenseVehicleRate(id: "three_wheeler", label: "", rate_per_km: 6)
        XCTAssertEqual(TravelPrompt.chipLabel(unnamed, currency: "INR"), "Three wheeler · ₹6/km")
    }

    func testTheDraftIsOneMileageLineForTheDayWithTheVehicleAndDistanceAndNoOdometerOrAmount() throws {
        let body = TravelPrompt.claimBody(try standard(), date: "2026-10-10", vehicleId: "two_wheeler", km: 23.456)
        XCTAssertEqual(body.items.count, 1)
        let line = try XCTUnwrap(body.items.first)
        XCTAssertEqual(line.category, "mileage")
        XCTAssertEqual(line.item_date, "2026-10-10")
        XCTAssertEqual(line.vehicle_type, "two_wheeler")
        let km = try XCTUnwrap(line.distance_km)
        XCTAssertEqual(km, 23.46, accuracy: 0.0001)
        XCTAssertNil(line.amount)                // the server prices a GPS-distance line
        XCTAssertNil(line.odometer_start)
        XCTAssertNil(line.odometer_end)
        XCTAssertNil(line.odometer_start_photo_url)
        XCTAssertNil(line.odometer_end_photo_url)
        XCTAssertNil(line.id)                     // a new line
        XCTAssertEqual(line.description, "GPS distance for 10 Oct 2026")
        XCTAssertEqual(body.title, "Travel · 10 Oct 2026")
    }

    func testTheDraftGoesToTheServerWithoutAnAmountOrOdometerKey() throws {
        let body = TravelPrompt.claimBody(nil, date: "2026-10-10", vehicleId: "car", km: 5)
        let data = try JSONEncoder().encode(body)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try XCTUnwrap(object["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        let line = items[0]
        XCTAssertEqual(line["category"] as? String, "mileage")
        XCTAssertEqual(line["vehicle_type"] as? String, "car")
        XCTAssertEqual(line["distance_km"] as? Double, 5.0)
        XCTAssertNil(line["amount"])
        XCTAssertNil(line["odometer_start"])
        XCTAssertNil(line["odometer_end"])
        XCTAssertNil(line["id"])
    }

    func testTheTitleFollowsThePoliciesNameForTheMileageCategory() throws {
        XCTAssertEqual(TravelPrompt.claimTitle(try rules(vehicles: [two, car], labels: ["mileage": "Conveyance"]), date: "2026-10-10"),
                       "Conveyance · 10 Oct 2026")
        XCTAssertEqual(TravelPrompt.claimTitle(nil, date: "2026-10-10"), "Travel · 10 Oct 2026")
        XCTAssertEqual(TravelPrompt.claimTitle(try rules(vehicles: [two, car], labels: ["mileage": "  "]), date: "2026-10-10"),
                       "Travel · 10 Oct 2026")
        // an unreadable date is printed as it came
        XCTAssertEqual(TravelPrompt.claimTitle(try standard(), date: "today"), "Travel · today")
    }
}

/// GET /api/v1/attendance/travel decodes the way the backend contract writes it, and tolerates what is missing.
@MainActor
final class TravelModelsTests: XCTestCase {

    /// The reply is `{ success, data }`; the app unwraps `data` (see `ExpensesAPI.travel`).
    private struct Reply: Decodable {
        let success: Bool
        let data: TravelSummary
    }

    private func parse(_ json: String) throws -> TravelSummary {
        try JSONDecoder().decode(Reply.self, from: Data(json.utf8)).data
    }

    func testTheDocumentedReplyDecodes() throws {
        let t = try parse("""
        {"success":true,"data":{
          "date":"2026-10-10","user_id":"u1","attendance_id":"a1","started_at":"2026-10-10T04:00:00.000Z","ended_at":"2026-10-10T12:00:00.000Z",
          "in_progress":false,"total_km":23.4,"method":"mixed",
          "legs":[{"index":0,"km":9.1,"method":"gps_trail",
                   "from":{"kind":"checkin","at":"2026-10-10T04:00:00.000Z","lat":13.0,"lng":80.1,"label":"Check-in"},
                   "to":{"kind":"form_checkin","at":"2026-10-10T05:00:00.000Z","lat":13.1,"lng":80.2,"label":"Customer Visit"}},
                  {"index":1,"km":14.3,"method":"straight_line","from":null,"to":null}],
          "stops":[{"submission_id":"s1","label":"Customer Visit","check_in_at":"2026-10-10T05:00:00.000Z","check_out_at":"2026-10-10T05:18:00.000Z","minutes":18}],
          "points_used":120,"points_excluded":3}}
        """)
        XCTAssertEqual(t.date, "2026-10-10")
        XCTAssertEqual(t.userId, "u1")
        XCTAssertEqual(t.attendanceId, "a1")
        XCTAssertEqual(t.inProgress, false)
        XCTAssertEqual(t.totalKm, 23.4)
        XCTAssertEqual(t.method, "mixed")
        XCTAssertEqual(t.legCount, 2)
        XCTAssertEqual(t.legList[0].km, 9.1)
        XCTAssertEqual(t.legList[0].from?.kind, "checkin")
        XCTAssertEqual(t.legList[0].to?.label, "Customer Visit")
        XCTAssertEqual(t.legList[0].to?.lat, 13.1)
        XCTAssertNil(t.legList[1].from)
        XCTAssertEqual(t.legList[1].method, "straight_line")
        XCTAssertEqual(t.stopList.count, 1)
        XCTAssertEqual(t.stopList.first?.minutes, 18)
        XCTAssertEqual(t.stopList.first?.submissionId, "s1")
        XCTAssertEqual(t.stopList.first?.checkOutAt, "2026-10-10T05:18:00.000Z")
        XCTAssertEqual(t.pointsUsed, 120)
        XCTAssertEqual(t.pointsExcluded, 3)
    }

    func testADayWithNoAttendanceDecodesAsNothingToClaim() throws {
        let t = try parse(#"{"success":true,"data":{"date":"2026-10-10","attendance_id":null,"total_km":0,"method":"none","legs":[],"stops":[]}}"#)
        XCTAssertNil(t.attendanceId)
        XCTAssertEqual(t.totalKm, 0.0)
        XCTAssertEqual(t.legCount, 0)
        XCTAssertTrue(t.stopList.isEmpty)
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: t, error: nil), .noTravel)
    }

    func testMissingOrNullListsReadAsEmptyNeverAsACrash() throws {
        let a = try parse(#"{"success":true,"data":{"total_km":5.5}}"#)
        XCTAssertTrue(a.legList.isEmpty)
        XCTAssertTrue(a.stopList.isEmpty)
        XCTAssertEqual(a.legCount, 0)
        let b = try parse(#"{"success":true,"data":{"total_km":5.5,"legs":null,"stops":null}}"#)
        XCTAssertTrue(b.legList.isEmpty)
        XCTAssertTrue(b.stopList.isEmpty)
    }

    func testAWrongTypedValueReadsAsNotThereAndCostsNothingElse() throws {
        // a string where a number belongs, a number where text belongs, an object where a list belongs
        let t = try parse(#"{"success":true,"data":{"total_km":"far","attendance_id":42,"in_progress":"no","legs":{"a":1},"method":"gps_trail","date":"2026-10-10"}}"#)
        XCTAssertNil(t.totalKm)
        XCTAssertNil(t.attendanceId)
        XCTAssertNil(t.inProgress)
        XCTAssertNil(t.legs)
        XCTAssertEqual(t.method, "gps_trail")
        XCTAssertEqual(t.date, "2026-10-10")
        // a wrong-typed list reads as empty
        XCTAssertEqual(t.legCount, 0)
    }

    func testALegWithoutPointsStillDecodes() throws {
        let u = try parse(#"{"success":true,"data":{"total_km":3,"legs":[{"index":0,"km":1.5}]}}"#)
        XCTAssertEqual(u.legCount, 1)
        XCTAssertEqual(u.legList[0].km, 1.5)
        XCTAssertNil(u.legList[0].from)
        XCTAssertNil(u.legList[0].to)
    }

    func testAnUnrelatedExtraKeyDoesNotMatter() throws {
        let t = try parse(#"{"success":true,"data":{"total_km":1.0,"something_new":{"a":1},"halts":[{"x":1}]}}"#)
        XCTAssertEqual(t.totalKm, 1.0)
    }

    func testAnInProgressDayReadsAsNotFinal() throws {
        let t = try parse(#"{"success":true,"data":{"attendance_id":"a1","in_progress":true,"total_km":4.2,"method":"gps_trail","legs":[{"index":0,"km":4.2}]}}"#)
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: t, error: nil), .notSynced)
    }

    func testAFinishedDayReadsAsReady() throws {
        let t = try parse(#"{"success":true,"data":{"attendance_id":"a1","in_progress":false,"total_km":4.2,"method":"straight_line","legs":[{"index":0,"km":4.2}]}}"#)
        XCTAssertEqual(TravelPrompt.outcomeOf(summary: t, error: nil), .ready(km: 4.2, legs: 1, method: "straight_line"))
    }
}
