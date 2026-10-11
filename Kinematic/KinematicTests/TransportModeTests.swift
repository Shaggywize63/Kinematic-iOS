//
//  TransportModeTests.swift
//  KinematicTests
//
//  Mode of transport ("How are you travelling today?"): which choices are valid, what a check-in is allowed to carry,
//  what Home's chip says, when a change is refused, the self-heal, and what the pre-selection on the travel prompt does.
//  Everything here is pure; with the rule off / unknown nothing is asked or sent.
//

import XCTest
@testable import Kinematic

@MainActor
final class TransportModeTests: XCTestCase {

    private let two = TransportOption(id: "two_wheeler", label: "Two-wheeler", vehicle: true)
    private let car = TransportOption(id: "car", label: "Car", vehicle: true)
    private let bus = TransportOption(id: "public_transport", label: "Public transport")
    private let other = TransportOption(id: "other", label: "Other")
    private var all: [TransportOption] { [two, car, bus, other] }

    private func instant(_ iso: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso))
    }

    private func record(id: String = "srv-1", date: String = "2026-10-12",
                        checkinAt: String? = "2026-10-12T03:30:11.123Z",
                        mode: String? = nil, label: String? = nil, totalHours: Double? = nil) -> AttendanceRecord {
        AttendanceRecord(id: id, date: date, status: "checked_in", checkinAt: checkinAt, checkoutAt: nil,
                         totalHours: totalHours, checkinSelfieUrl: nil, checkoutSelfieUrl: nil,
                         transportMode: mode, transportLabel: label)
    }

    // MARK: - ids

    func testAnIdIsLowercaseLettersDigitsAndUnderscoresOneToFortyLong() {
        for ok in ["car", "two_wheeler", "own_bike", "a", "x9_", String(repeating: "a", count: 40)] {
            XCTAssertTrue(TransportMode.isValidId(ok), ok)
        }
        let bad: [String?] = [nil, "", " ", "Car", "two-wheeler", "two wheeler", "car!", String(repeating: "a", count: 41),
                              "bike\n", "../x", "বাইক"]
        for b in bad { XCTAssertFalse(TransportMode.isValidId(b), b ?? "nil") }
    }

    // MARK: - the choices

    func testSanitizeKeepsThePolicysOrderAndDropsWhatTheServerCouldNotAccept() {
        let raw: [TransportOption] = [
            two, TransportOption(id: "Bad Id", label: "Nope"), car, TransportOption(id: "car", label: "Car again"),
            TransportOption(id: "", label: "Empty"), TransportOption(id: String(repeating: "a", count: 41), label: "Too long"),
            bus, other,
        ]
        let clean = TransportMode.sanitize(raw)
        XCTAssertEqual(clean.map { $0.id }, ["two_wheeler", "car", "public_transport", "other"])
        // the first of a repeated id wins
        XCTAssertEqual(clean.first(where: { $0.id == "car" })?.label, "Car")
        XCTAssertEqual(TransportMode.sanitize(nil), [])
        XCTAssertEqual(TransportMode.sanitize([]), [])
    }

    func testABlankLabelReadsAsTheIdAnOverlongOneIsCutAndThereAreNeverMoreThanTwelve() {
        let s = TransportMode.sanitize([TransportOption(id: "own_bike", label: "  "),
                                        TransportOption(id: "x", label: String(repeating: "y", count: 200))])
        XCTAssertEqual(s[0].label, "Own bike")
        XCTAssertEqual(s[1].label.count, TransportMode.maxLabelLength)
        let many = TransportMode.sanitize((0..<30).map { TransportOption(id: "m\($0)", label: "Mode \($0)") })
        XCTAssertEqual(many.count, TransportMode.maxOptions)
        XCTAssertEqual(many.first?.id, "m0")
    }

    func testTheQuestionIsAskedOnlyWhenTheRuleIsOnAndThereIsSomethingToChoose() {
        XCTAssertTrue(TransportMode.isActive(trackTransportMode: true, options: all))
        // rule on, no choices: guessing ids would only get the check-in refused
        XCTAssertFalse(TransportMode.isActive(trackTransportMode: true, options: []))
        XCTAssertFalse(TransportMode.isActive(trackTransportMode: false, options: all))
        XCTAssertFalse(TransportMode.isActive(trackTransportMode: false, options: []))
    }

    func testAChoiceMustBeOneOfTheOfferedOnes() {
        XCTAssertEqual(TransportMode.choice(picked: "car", options: all), "car")
        XCTAssertEqual(TransportMode.choice(picked: " car ", options: all), "car")
        XCTAssertNil(TransportMode.choice(picked: "bicycle", options: all))
        XCTAssertNil(TransportMode.choice(picked: "", options: all))
        XCTAssertNil(TransportMode.choice(picked: nil, options: all))
        XCTAssertNil(TransportMode.choice(picked: "car", options: []))
    }

    // MARK: - what a check-in carries

    func testACheckInCarriesTheChoiceOnlyWhileTheRuleIsOnAndTheIdIsOffered() {
        XCTAssertEqual(TransportMode.modeToSend(trackTransportMode: true, options: all, chosen: "two_wheeler"), "two_wheeler")
        // rule off / unknown: never sent, whatever was chosen before
        XCTAssertNil(TransportMode.modeToSend(trackTransportMode: false, options: all, chosen: "two_wheeler"))
        XCTAssertNil(TransportMode.modeToSend(trackTransportMode: false, options: [], chosen: "two_wheeler"))
        XCTAssertNil(TransportMode.modeToSend(trackTransportMode: true, options: [], chosen: "two_wheeler"))
        // a stale or invented id is never sent
        XCTAssertNil(TransportMode.modeToSend(trackTransportMode: true, options: all, chosen: "rocket"))
        // nothing chosen: nothing sent (the request is exactly what it always was)
        XCTAssertNil(TransportMode.modeToSend(trackTransportMode: true, options: all, chosen: nil))
        XCTAssertNil(TransportMode.modeToSend(trackTransportMode: true, options: all, chosen: ""))
    }

    // MARK: - labels

    func testAModeReadsAsTheOfferedLabelElseTheServersElseAReadableId() {
        XCTAssertEqual(TransportMode.labelFor(id: "two_wheeler", options: all), "Two-wheeler")
        XCTAssertEqual(TransportMode.labelFor(id: "two_wheeler", options: all, serverLabel: "Server label"), "Two-wheeler")
        XCTAssertEqual(TransportMode.labelFor(id: "own_bike", options: all, serverLabel: "Own Bike"), "Own Bike")
        XCTAssertEqual(TransportMode.labelFor(id: "own_bike", options: all), "Own bike")
        XCTAssertEqual(TransportMode.labelFor(id: "own_bike", options: all, serverLabel: "  "), "Own bike")
        XCTAssertNil(TransportMode.labelFor(id: nil, options: all))
        XCTAssertNil(TransportMode.labelFor(id: "  ", options: all))
        XCTAssertEqual(TransportMode.prettify("public_transport"), "Public transport")
    }

    // MARK: - the pre-selection on the travel prompt

    func testAVehicleOfThePolicyIsPreselectedNothingElseIs() {
        let policy = ["two_wheeler", "car"]
        XCTAssertEqual(TransportMode.preselectVehicle(modeId: "car", policyVehicleIds: policy), "car")
        XCTAssertEqual(TransportMode.preselectVehicle(modeId: " two_wheeler ", policyVehicleIds: policy), "two_wheeler")
        // the two fixed non-vehicle choices do nothing special ...
        XCTAssertNil(TransportMode.preselectVehicle(modeId: "public_transport", policyVehicleIds: policy))
        XCTAssertNil(TransportMode.preselectVehicle(modeId: "other", policyVehicleIds: policy))
        // ... even if a policy happened to list a vehicle with such an id
        XCTAssertNil(TransportMode.preselectVehicle(modeId: "other", policyVehicleIds: ["other", "car"]))
        XCTAssertNil(TransportMode.preselectVehicle(modeId: "public_transport", policyVehicleIds: ["public_transport"]))
        // a vehicle the policy does not pay for, no mode, blank
        XCTAssertNil(TransportMode.preselectVehicle(modeId: "auto_rickshaw", policyVehicleIds: policy))
        XCTAssertNil(TransportMode.preselectVehicle(modeId: nil, policyVehicleIds: policy))
        XCTAssertNil(TransportMode.preselectVehicle(modeId: "", policyVehicleIds: policy))
        XCTAssertNil(TransportMode.preselectVehicle(modeId: "car", policyVehicleIds: [String]()))
        // any collection of ids works (the expense policy's vehicle ids may come as a set)
        XCTAssertEqual(TransportMode.preselectVehicle(modeId: "car", policyVehicleIds: Set(policy)), "car")
    }

    // MARK: - Home's chip

    func testTheChipShowsTodaysModeWithChangeOrAsksToSetOne() throws {
        let set = try XCTUnwrap(TransportMode.chip(active: true, record: record(mode: "two_wheeler"), options: all))
        XCTAssertEqual(set.text, "Travelling by Two-wheeler")
        XCTAssertEqual(set.action, "Change")
        XCTAssertNil(set.note)

        let unset = try XCTUnwrap(TransportMode.chip(active: true, record: record(), options: all))
        XCTAssertEqual(unset.text, "Travel mode not set")
        XCTAssertEqual(unset.action, "Set")

        // the server's label is used for a mode that is no longer on offer
        let old = try XCTUnwrap(TransportMode.chip(active: true, record: record(mode: "own_bike", label: "Own Bike"), options: all))
        XCTAssertEqual(old.text, "Travelling by Own Bike")
    }

    func testNoChipWhenTheRuleIsOffOrUnknownOrBeforeCheckIn() {
        XCTAssertNil(TransportMode.chip(active: false, record: record(mode: "car"), options: all))
        XCTAssertNil(TransportMode.chip(active: true, record: nil, options: all))
        XCTAssertNil(TransportMode.chip(active: true, record: record(checkinAt: nil), options: all))
    }

    func testACheckInStillWaitingInTheOfflineQueueShowsTheChoiceButOffersNoChange() throws {
        let standIn = record(id: OfflinePunchState.pendingRecordId, mode: "car")
        let chip = try XCTUnwrap(TransportMode.chip(active: true, record: standIn, options: all))
        XCTAssertEqual(chip.text, "Travelling by Car")
        XCTAssertNil(chip.action)
        XCTAssertTrue(chip.note?.contains("synced") ?? false)

        // a check-in waiting in the older queue (no stand-in record) is treated the same way
        let queued = try XCTUnwrap(TransportMode.chip(active: true, record: record(mode: "car"), options: all, checkinQueued: true))
        XCTAssertNil(queued.action)
        XCTAssertNotNil(queued.note)
    }

    func testAGarbageModeOnARecordReadsAsNotSet() throws {
        let chip = try XCTUnwrap(TransportMode.chip(active: true, record: record(mode: "Not An Id!"), options: all))
        XCTAssertEqual(chip.text, "Travel mode not set")
    }

    // MARK: - changing it: online only, honest otherwise

    func testAChangeIsRefusedWithTheReasonWhenOfflineBeforeCheckInOrBeforeTheCheckInSynced() {
        XCTAssertNil(TransportMode.cannotChange(online: true, record: record()))
        XCTAssertTrue(TransportMode.cannotChange(online: false, record: record())?.contains("offline") ?? false)
        XCTAssertTrue(TransportMode.cannotChange(online: true, record: nil)?.contains("Check in first") ?? false)
        XCTAssertTrue(TransportMode.cannotChange(online: true, record: record(checkinAt: nil))?.contains("Check in first") ?? false)
        XCTAssertTrue(TransportMode.cannotChange(online: true, record: record(id: OfflinePunchState.pendingRecordId))?.contains("synced") ?? false)
        XCTAssertTrue(TransportMode.cannotChange(online: true, record: record(), checkinQueued: true)?.contains("synced") ?? false)
        // offline wins: that is what the rep can fix first
        XCTAssertTrue(TransportMode.cannotChange(online: false, record: nil)?.contains("offline") ?? false)
    }

    func testAFailedChangeSaysWhetherItWasTheConnectionOrTheServersOwnReason() {
        XCTAssertTrue(TransportMode.changeFailure(httpStatus: nil, message: "Unable to resolve host", retryable: true)
            .contains("Couldn't reach the server"))
        XCTAssertTrue(TransportMode.changeFailure(httpStatus: 503, message: "Service Unavailable", retryable: true)
            .contains("Check your connection"))
        // no status and not an outage (an unreadable reply, a bug): plain words, never the technical message
        XCTAssertEqual(TransportMode.changeFailure(httpStatus: nil, message: "Expected BEGIN_OBJECT but was STRING", retryable: false),
                       "Couldn't change your travel mode.")
        XCTAssertEqual(TransportMode.changeFailure(httpStatus: 400, message: "No attendance found for 2026-10-12. Check in first.", retryable: false),
                       "No attendance found for 2026-10-12. Check in first.")
        XCTAssertEqual(TransportMode.changeFailure(httpStatus: 400, message: "  ", retryable: false), "Couldn't change your travel mode.")
        XCTAssertEqual(TransportMode.changeFailure(httpStatus: 403, message: nil, retryable: false), "Couldn't change your travel mode.")
    }

    func testTheDateIsSentOnlyForARecordOfAnotherDay() throws {
        let now = try instant("2026-10-12T05:00:00Z") // 10:30 IST on the 12th
        XCTAssertNil(TransportMode.changeDate(record: record(date: "2026-10-12"), now: now))
        XCTAssertNil(TransportMode.changeDate(record: record(date: "12--10--2026"), now: now))
        XCTAssertEqual(TransportMode.changeDate(record: record(date: "2026-10-11"), now: now), "2026-10-11")
        XCTAssertNil(TransportMode.changeDate(record: nil, now: now))
    }

    func testAfterAChangeTheRecordKeepsWhatItKnewAndTakesTheNewMode() throws {
        let before = record(mode: "car", label: "Car", totalHours: 1.5)
        let sameRow = record(mode: "two_wheeler", label: "Two-wheeler")
        let after = try XCTUnwrap(TransportMode.applyChange(record: before, mode: "two_wheeler", serverRow: sameRow))
        XCTAssertEqual(after.transportMode, "two_wheeler")
        XCTAssertEqual(after.transportLabel, "Two-wheeler")
        XCTAssertEqual(after.totalHours, 1.5)                 // untouched
        XCTAssertEqual(after.checkinAt, before.checkinAt)

        // the server did not echo a mode: take the one that was sent, and let the UI label it from the offered choices
        let noEcho = try XCTUnwrap(TransportMode.applyChange(record: before, mode: "two_wheeler", serverRow: nil))
        XCTAssertEqual(noEcho.transportMode, "two_wheeler")
        XCTAssertNil(noEcho.transportLabel)
        // a stale label for another mode is never kept
        let staleLabel = try XCTUnwrap(TransportMode.applyChange(record: before, mode: "two_wheeler", serverRow: record(mode: nil, label: "Car")))
        XCTAssertEqual(staleLabel.transportMode, "two_wheeler")
        XCTAssertNil(staleLabel.transportLabel)
        XCTAssertNil(TransportMode.applyChange(record: nil, mode: "car", serverRow: sameRow))
    }

    // MARK: - self-heal: the server lost the mode we sent

    func testACheckInThatSentAModeAndCameBackWithoutOneNeedsTheRepair() {
        XCTAssertTrue(TransportMode.needsRepair(modeSent: "car", returned: record(mode: nil)))
        XCTAssertTrue(TransportMode.needsRepair(modeSent: "two_wheeler", returned: record(mode: nil, label: nil)))
        XCTAssertTrue(TransportMode.needsRepair(modeSent: " car ", returned: record(mode: nil)))
        // a mode that is only blanks is no mode
        XCTAssertTrue(TransportMode.needsRepair(modeSent: "car", returned: record(mode: "  ")))
        XCTAssertTrue(TransportMode.needsRepair(modeSent: "car", returned: record(mode: "")))
    }

    func testARecordThatHasAModeIsNeverTouchedEvenADifferentOne() {
        XCTAssertFalse(TransportMode.needsRepair(modeSent: "car", returned: record(mode: "car")))
        XCTAssertFalse(TransportMode.needsRepair(modeSent: "car", returned: record(mode: "two_wheeler")))
    }

    func testNothingIsRepairedWhenNoModeWasSentOrItCouldNotHaveBeenAccepted() {
        // the rule is off / not a check-in with a mode
        XCTAssertFalse(TransportMode.needsRepair(modeSent: nil, returned: record(mode: nil)))
        XCTAssertFalse(TransportMode.needsRepair(modeSent: "", returned: record(mode: nil)))
        XCTAssertFalse(TransportMode.needsRepair(modeSent: "   ", returned: record(mode: nil)))
        // an id the server would refuse is never sent again
        XCTAssertFalse(TransportMode.needsRepair(modeSent: "Bad Id", returned: record(mode: nil)))
        XCTAssertFalse(TransportMode.needsRepair(modeSent: String(repeating: "a", count: 41), returned: record(mode: nil)))
    }

    func testNothingIsRepairedWithoutARealCheckInOnTheServer() {
        XCTAssertFalse(TransportMode.needsRepair(modeSent: "car", returned: nil))
        XCTAssertFalse(TransportMode.needsRepair(modeSent: "car", returned: record(checkinAt: nil, mode: nil)))
        // the offline stand-in is not a server row, there is nothing to change yet
        XCTAssertFalse(TransportMode.needsRepair(modeSent: "car", returned: record(id: OfflinePunchState.pendingRecordId, mode: nil)))
    }

    func testARecordOfAnotherDayIsLeftAloneWhenTheDayIsGiven() {
        let rec = record(date: "2026-10-12", mode: nil)
        XCTAssertTrue(TransportMode.needsRepair(modeSent: "car", returned: rec, expectedDate: "2026-10-12"))
        XCTAssertFalse(TransportMode.needsRepair(modeSent: "car", returned: rec, expectedDate: "2026-10-11"))
        // the record's date may come in the app's older format or as a timestamp
        XCTAssertTrue(TransportMode.needsRepair(modeSent: "car", returned: record(date: "12--10--2026", mode: nil), expectedDate: "2026-10-12"))
        XCTAssertTrue(TransportMode.needsRepair(modeSent: "car", returned: record(date: "2026-10-12T00:00:00Z", mode: nil), expectedDate: "2026-10-12"))
        // no day given: any day
        XCTAssertTrue(TransportMode.needsRepair(modeSent: "car", returned: rec, expectedDate: nil))
    }

    func testAfterARepairTheRecordCarriesTheMode() throws {
        let before = record(mode: nil)
        let after = try XCTUnwrap(TransportMode.applyChange(record: before, mode: "car", serverRow: record(mode: "car", label: "Car")))
        XCTAssertEqual(after.transportMode, "car")
        XCTAssertFalse(TransportMode.needsRepair(modeSent: "car", returned: after))
        // and the chip no longer offers "Set"
        XCTAssertEqual(TransportMode.chip(active: true, record: after, options: all)?.action, "Change")
        XCTAssertEqual(TransportMode.chip(active: true, record: before, options: all)?.action, "Set")
    }

    // MARK: - the record carries the new keys

    func testAttendanceRecordsReadTheModeAndItsLabelAndAnOlderReplyHasNeither() throws {
        let with = try JSONDecoder().decode(AttendanceRecord.self, from: Data(
            #"{"id":"a1","date":"2026-10-12","checkin_at":"2026-10-12T03:30:00Z","transport_mode":"own_bike","transport_label":"Own Bike"}"#.utf8))
        XCTAssertEqual(with.transportMode, "own_bike")
        XCTAssertEqual(with.transportLabel, "Own Bike")
        let without = try JSONDecoder().decode(AttendanceRecord.self, from: Data(
            #"{"id":"a1","date":"2026-10-12","checkin_at":"2026-10-12T03:30:00Z"}"#.utf8))
        XCTAssertNil(without.transportMode)
        XCTAssertNil(without.transportLabel)
        // and they survive the cached-Home save and load
        let back = try JSONDecoder().decode(AttendanceRecord.self, from: JSONEncoder().encode(with))
        XCTAssertEqual(back.transportMode, "own_bike")
        XCTAssertEqual(back.transportLabel, "Own Bike")
    }
}
