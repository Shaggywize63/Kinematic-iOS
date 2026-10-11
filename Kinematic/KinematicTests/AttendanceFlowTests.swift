//
//  AttendanceFlowTests.swift
//  KinematicTests
//
//  The promise behind every attendance rule: a client that configured nothing is exactly the app it was. With the
//  default rules nobody is asked how they are travelling, today's record is the server's record untouched, and the
//  interrupted-Clock-In plumbing (the question's sheet) does what it says: carry on only after an answer, never after a
//  cancel.
//

import XCTest
@testable import Kinematic

@MainActor
final class AttendanceFlowTests: XCTestCase {

    private func record(date: String = "2026-10-12", checkin: String? = "2026-10-12T03:30:11.123Z",
                        mode: String? = nil) -> AttendanceRecord {
        AttendanceRecord(id: "srv-1", date: date, status: "checked_in", checkinAt: checkin, checkoutAt: nil,
                         totalHours: nil, checkinSelfieUrl: nil, checkoutSelfieUrl: nil, transportMode: mode)
    }

    // MARK: - nothing configured, nothing changes

    func testAClientThatConfiguredNothingIsNeverAskedHowItIsTravelling() {
        let vm = AttendanceViewModel()
        var resumed = false
        XCTAssertFalse(vm.askClockInQuestionIfNeeded(isCheckIn: true, resume: { resumed = true }))
        XCTAssertNil(vm.transportRequest)
        XCTAssertFalse(resumed)
        // and a check-out is never asked, whatever the rules
        XCTAssertFalse(vm.askClockInQuestionIfNeeded(isCheckIn: false, resume: { resumed = true }))
        XCTAssertNil(vm.transportRequest)
    }

    func testTodayIsTheServersRecordUntouchedWhenNothingIsQueuedAndNoModeIsKnown() throws {
        let vm = AttendanceViewModel()
        let server = record()
        let merged = try XCTUnwrap(vm.mergedToday(server))
        XCTAssertEqual(merged.id, "srv-1")
        XCTAssertEqual(merged.checkinAt, "2026-10-12T03:30:11.123Z")
        XCTAssertEqual(merged.status, "checked_in")
        XCTAssertNil(merged.transportMode)
        XCTAssertNil(vm.mergedToday(nil))
    }

    // MARK: - what the phone knows is laid over a read that leaves it out

    func testAKnownTravelModeIsLaidOverTheHomePayloadOfTheSameDayOnly() throws {
        let vm = AttendanceViewModel()
        vm.knownTransport = KnownTransportMode(date: "2026-10-12", mode: "car", label: "Car")
        let same = try XCTUnwrap(vm.mergedToday(record(date: "12--10--2026")))
        XCTAssertEqual(same.transportMode, "car")
        XCTAssertEqual(same.transportLabel, "Car")
        // another day's record never takes it
        let other = try XCTUnwrap(vm.mergedToday(record(date: "2026-10-13")))
        XCTAssertNil(other.transportMode)
        // a record that already holds a mode keeps it
        let own = try XCTUnwrap(vm.mergedToday(record(mode: "two_wheeler")))
        XCTAssertEqual(own.transportMode, "two_wheeler")
        // and nothing is invented before a check-in
        let before = try XCTUnwrap(vm.mergedToday(record(checkin: nil)))
        XCTAssertNil(before.transportMode)
    }

    func testTodaysModeFallsBackToWhatThePhoneKnows() {
        let std = KiniAppState.shared
        let saved = std.today
        defer { std.today = saved }
        let vm = AttendanceViewModel()

        std.today = record(mode: "car")
        XCTAssertEqual(vm.todayTransportMode, "car")

        std.today = record()
        XCTAssertNil(vm.todayTransportMode)
        vm.knownTransport = KnownTransportMode(date: "2026-10-12", mode: "two_wheeler", label: nil)
        XCTAssertEqual(vm.todayTransportMode, "two_wheeler")
        // a mode known for another day is not today's
        vm.knownTransport = KnownTransportMode(date: "2026-10-11", mode: "two_wheeler", label: nil)
        XCTAssertNil(vm.todayTransportMode)
    }

    // MARK: - the question's sheet

    func testTheInterruptedClockInGoesOnOnlyAfterTheSheetClosedWithAnAnswer() {
        let vm = AttendanceViewModel()
        var resumed = 0
        vm.afterTransportChoice = { resumed += 1 }
        vm.transportRequest = TransportPickRequest(options: [TransportOption(id: "car", label: "Car", vehicle: true)])

        vm.transportAnswered("car")
        // the sheet is on its way out: nothing runs yet (the camera must not open over it)
        XCTAssertEqual(resumed, 0)
        XCTAssertNil(vm.transportRequest)
        XCTAssertEqual(vm.transportChoice, "car")

        vm.transportSheetDismissed()
        XCTAssertEqual(resumed, 1)
        // once only
        vm.transportSheetDismissed()
        XCTAssertEqual(resumed, 1)
    }

    func testCancellingTheQuestionNeverContinuesTheClockIn() {
        let vm = AttendanceViewModel()
        var resumed = 0
        vm.afterTransportChoice = { resumed += 1 }
        vm.transportRequest = TransportPickRequest(options: [TransportOption(id: "car", label: "Car", vehicle: true)])

        vm.transportCancelled()
        vm.transportSheetDismissed()

        XCTAssertEqual(resumed, 0)
        XCTAssertNil(vm.transportRequest)
        XCTAssertNil(vm.transportChoice)
    }

    func testAnAnswerIsGoodOnlyForTheClockInItWasGivenFor() {
        let vm = AttendanceViewModel()
        var rules = AttendanceRules()
        rules.trackTransportMode = true
        rules.transportModes = [TransportOption(id: "car", label: "Car", vehicle: true)]

        XCTAssertFalse(vm.transportAnswerIsCurrent(rules))                 // nothing answered
        vm.transportChoice = "car"
        vm.transportChoiceAt = Date()
        XCTAssertTrue(vm.transportAnswerIsCurrent(rules))
        vm.transportChoiceAt = Date().addingTimeInterval(-(AttendanceViewModel.transportChoiceLifetime + 1))
        XCTAssertFalse(vm.transportAnswerIsCurrent(rules))                 // a stale answer is asked again
        vm.transportChoiceAt = Date()
        vm.transportChoice = "rocket"
        XCTAssertFalse(vm.transportAnswerIsCurrent(rules))                 // an id the rules no longer offer is not an answer
        vm.transportChoice = "car"
        vm.clearTransportChoice()
        XCTAssertFalse(vm.transportAnswerIsCurrent(rules))                 // used up by the Clock-In it belonged to
    }

    // MARK: - the final-check-out signal and sign-out

    func testTheFinalCheckOutSignalIsATakeOnceState() {
        let vm = AttendanceViewModel()
        XCTAssertNil(vm.freshCheckoutDate)
        vm.freshCheckoutDate = "2026-10-12"
        vm.consumeFreshCheckout()
        XCTAssertNil(vm.freshCheckoutDate)
    }

    func testSignOutLeavesNothingOfThePersonsAttendanceFlowForTheNextOne() {
        let vm = AttendanceViewModel()
        vm.transportChoice = "car"
        vm.transportChoiceAt = Date()
        vm.transportRequest = TransportPickRequest(options: [TransportOption(id: "car", label: "Car", vehicle: true)])
        vm.afterTransportChoice = { }
        vm.transportBusy = true
        vm.transportMessage = "Travel mode updated"
        vm.gpsPunching = true
        vm.freshCheckoutDate = "2026-10-12"
        vm.knownTransport = KnownTransportMode(date: "2026-10-12", mode: "car", label: "Car")

        vm.resetForSignOut()

        XCTAssertNil(vm.transportChoice)
        XCTAssertNil(vm.transportChoiceAt)
        XCTAssertNil(vm.transportRequest)
        XCTAssertNil(vm.afterTransportChoice)
        XCTAssertFalse(vm.transportBusy)
        XCTAssertNil(vm.transportMessage)
        XCTAssertFalse(vm.gpsPunching)
        XCTAssertNil(vm.freshCheckoutDate)
        XCTAssertNil(vm.knownTransport)
    }
}
