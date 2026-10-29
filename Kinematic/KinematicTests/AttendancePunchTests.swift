//
//  AttendancePunchTests.swift
//  KinematicTests
//
//  The GPS-only punch (attendance rule `selfie_required: false`): the words the Home / Attendance screens use, when a
//  remembered fix may stand in for a fresh one, and when a selfie is demanded. With the rule on (or unknown) every
//  string is the one the app always had.
//

import XCTest
@testable import Kinematic

@MainActor
final class AttendancePunchTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_791_777_791)

    // MARK: - a fix that is fresh enough

    func testAFixIsFreshForAMinuteAndASlightlyFutureOneIsFineToo() {
        XCTAssertTrue(AttendancePunch.isFreshEnough(fixTime: t0, now: t0))
        XCTAssertTrue(AttendancePunch.isFreshEnough(fixTime: t0.addingTimeInterval(-30), now: t0))
        XCTAssertTrue(AttendancePunch.isFreshEnough(fixTime: t0.addingTimeInterval(-60), now: t0))
        XCTAssertFalse(AttendancePunch.isFreshEnough(fixTime: t0.addingTimeInterval(-61), now: t0))
        // a clock that moved a little
        XCTAssertTrue(AttendancePunch.isFreshEnough(fixTime: t0.addingTimeInterval(5), now: t0))
        XCTAssertFalse(AttendancePunch.isFreshEnough(fixTime: t0.addingTimeInterval(6), now: t0))
        // no fix time at all is never fresh
        XCTAssertFalse(AttendancePunch.isFreshEnough(fixTime: nil, now: t0))
    }

    // MARK: - the words

    func testWithTheSelfieRequiredEveryStringIsTheOneTheAppAlwaysHad() {
        // The Home card's headline, exactly as it was written inline before the rule existed.
        // Multiple check-in/out per day: a clocked-out rep is "Clocked Out" (re-check-in),
        // not a terminal "Shift Completed".
        func legacy(ended: Bool, isIn: Bool, hasCheckin: Bool) -> String {
            ended ? "Clocked Out" : (isIn ? "Shift Active" : (!hasCheckin ? "Daily Selfie Required" : "Check In to Resume"))
        }
        for ended in [false, true] {
            for isIn in [false, true] {
                for hasCheckin in [false, true] {
                    XCTAssertEqual(AttendancePunch.headline(shiftEnded: ended, isIn: isIn, hasCheckin: hasCheckin, selfieRequired: true),
                                   legacy(ended: ended, isIn: isIn, hasCheckin: hasCheckin),
                                   "ended=\(ended) in=\(isIn) checkin=\(hasCheckin)")
                }
            }
        }
        XCTAssertEqual(AttendancePunch.tapHint(selfieRequired: true), "Tap to complete check-in")
        XCTAssertEqual(AttendancePunch.actionGlyph(shiftEnded: false, selfieRequired: true), "camera.fill")
        // Clocked-out stays actionable (the rep may check in again), not a terminal seal.
        XCTAssertEqual(AttendancePunch.actionGlyph(shiftEnded: true, selfieRequired: true), "camera.fill")
        XCTAssertEqual(AttendancePunch.checkInButtonTitle(needsSelfie: true), "TAKE SELFIE TO CHECK IN")
    }

    func testWithNoSelfieOnlyTheNotCheckedInYetStateChanges() {
        XCTAssertEqual(AttendancePunch.headline(shiftEnded: false, isIn: false, hasCheckin: false, selfieRequired: false), "Daily Check-In Required")
        XCTAssertEqual(AttendancePunch.headline(shiftEnded: false, isIn: true, hasCheckin: true, selfieRequired: false), "Shift Active")
        XCTAssertEqual(AttendancePunch.headline(shiftEnded: true, isIn: false, hasCheckin: true, selfieRequired: false), "Clocked Out")
        XCTAssertEqual(AttendancePunch.headline(shiftEnded: false, isIn: false, hasCheckin: true, selfieRequired: false), "Check In to Resume")
        XCTAssertEqual(AttendancePunch.tapHint(selfieRequired: false), "Tap to check in")
        XCTAssertEqual(AttendancePunch.actionGlyph(shiftEnded: false, selfieRequired: false), "location.fill")
        XCTAssertEqual(AttendancePunch.actionGlyph(shiftEnded: true, selfieRequired: false), "location.fill")
        XCTAssertEqual(AttendancePunch.checkInButtonTitle(needsSelfie: false), "CHECK IN NOW")
    }

    func testTheNoFixMessageNamesTheAction() {
        XCTAssertTrue(AttendancePunch.noFixMessage(isCheckIn: true).contains("check in"))
        XCTAssertTrue(AttendancePunch.noFixMessage(isCheckIn: false).contains("check out"))
        XCTAssertTrue(AttendancePunch.noFixMessage(isCheckIn: true).hasPrefix("Couldn't get your location"))
    }

    // MARK: - when a selfie is demanded

    func testASelfieIsDemandedOfAnExecutiveUnlessTheRuleSaysNo() {
        XCTAssertTrue(AttendancePunch.selfieDemanded(isExecutive: true, ruleRequired: true))
        XCTAssertFalse(AttendancePunch.selfieDemanded(isExecutive: true, ruleRequired: false))
        XCTAssertFalse(AttendancePunch.selfieDemanded(isExecutive: false, ruleRequired: true))
        XCTAssertFalse(AttendancePunch.selfieDemanded(isExecutive: false, ruleRequired: false))
    }

    // MARK: - the rules decide the flow

    func testUnknownRulesKeepTheCameraFlow() {
        // never loaded / nothing configured: the camera, no travel question, no offline capture
        let r = AttendanceRules()
        XCTAssertTrue(r.needsCamera)
        XCTAssertFalse(r.transportPromptActive)
        XCTAssertFalse(r.allowOfflineCheckin)
        var off = AttendanceRules()
        off.selfieRequired = false
        XCTAssertFalse(off.needsCamera)
    }
}
