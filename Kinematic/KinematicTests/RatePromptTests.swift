//
//  RatePromptTests.swift
//  KinematicTests
//
//  The rate-the-app prompt: when it may be shown (each boundary), how the counters move, how the memory is stored on
//  the device, and the session side (`RatePromptCoordinator`) driven with its own UserDefaults suite and a signed-in
//  user whose client has, or has not, switched the feature on. Mirrors the Android RatePromptTest.
//

import XCTest
@testable import Kinematic

@MainActor
final class RatePromptTests: XCTestCase {

    private let day: Int64 = 24 * 60 * 60 * 1000
    /// 2026-10-11 10:00:00 UTC, in ms since 1970.
    private let now: Int64 = 1_791_712_800_000

    /// A record that satisfies every rule, so each test breaks exactly one.
    private let ready = RatePrompt.Record(state: .undecided, openDays: 3, lastOpenDay: "2026-10-11", positives: 2, prompts: 0, lastPromptAtMs: 0)

    private var installedLongAgo: Int64 { now - 10 * day }

    private func changed(_ r: RatePrompt.Record, _ change: (inout RatePrompt.Record) -> Void) -> RatePrompt.Record {
        var out = r
        change(&out)
        return out
    }

    /// The common case: the record `r`, installed long ago, asked about right now, feature on.
    private func eligible(_ r: RatePrompt.Record) -> Bool {
        RatePrompt.eligible(featureOn: true, record: r, installMs: installedLongAgo, nowMs: now)
    }

    private func eligible(installMs: Int64?) -> Bool {
        RatePrompt.eligible(featureOn: true, record: ready, installMs: installMs, nowMs: now)
    }

    // MARK: - eligibility: every rule, on its boundary

    func testARepWhoMeetsEveryRuleIsEligible() {
        XCTAssertTrue(eligible(ready))
    }

    func testTheFeatureMustBeOn() {
        XCTAssertFalse(RatePrompt.eligible(featureOn: false, record: ready, installMs: installedLongAgo, nowMs: now))
    }

    func testARepWhoRatedOrSaidDontAskAgainIsNeverAsked() {
        XCTAssertFalse(eligible(changed(ready) { $0.state = .rated }))
        XCTAssertFalse(eligible(changed(ready) { $0.state = .never }))
    }

    func testTheAppMustHaveBeenInstalledForThreeDays() {
        XCTAssertTrue(eligible(installMs: now - 3 * day))              // exactly 3 days
        XCTAssertFalse(eligible(installMs: now - 3 * day + 1))         // a millisecond short
        XCTAssertFalse(eligible(installMs: now - 2 * day))
        XCTAssertFalse(eligible(installMs: now))
        XCTAssertTrue(eligible(installMs: now - 400 * day))
        // an unknown install time is not good enough
        XCTAssertFalse(eligible(installMs: nil))
        // an install time in the future (a changed clock) is not good enough either
        XCTAssertFalse(eligible(installMs: now + day))
    }

    func testTheAppMustHaveBeenOpenedOnThreeDifferentDays() {
        XCTAssertTrue(eligible(changed(ready) { $0.openDays = 3 }))
        XCTAssertFalse(eligible(changed(ready) { $0.openDays = 2 }))
        XCTAssertFalse(eligible(changed(ready) { $0.openDays = 0 }))
        XCTAssertTrue(eligible(changed(ready) { $0.openDays = 40 }))
    }

    func testThereMustHaveBeenTwoGoodMoments() {
        XCTAssertTrue(eligible(changed(ready) { $0.positives = 2 }))
        XCTAssertFalse(eligible(changed(ready) { $0.positives = 1 }))
        XCTAssertFalse(eligible(changed(ready) { $0.positives = 0 }))
        XCTAssertTrue(eligible(changed(ready) { $0.positives = 99 }))
    }

    func testItIsAskedAtMostThreeTimes() {
        // 2 earlier "Maybe later" answers long ago: the third ask is allowed ...
        XCTAssertTrue(eligible(changed(ready) { $0.prompts = 2; $0.lastPromptAtMs = now - 31 * day }))
        // ... after the third answer it is over
        XCTAssertFalse(eligible(changed(ready) { $0.prompts = 3; $0.lastPromptAtMs = now - 400 * day }))
        XCTAssertFalse(eligible(changed(ready) { $0.prompts = 4; $0.lastPromptAtMs = now - 400 * day }))
    }

    func testAfterMaybeLaterItWaitsThirtyDays() {
        XCTAssertTrue(eligible(changed(ready) { $0.prompts = 1; $0.lastPromptAtMs = now - 30 * day }))        // exactly 30 days
        XCTAssertFalse(eligible(changed(ready) { $0.prompts = 1; $0.lastPromptAtMs = now - 30 * day + 1 }))   // a millisecond short
        XCTAssertFalse(eligible(changed(ready) { $0.prompts = 1; $0.lastPromptAtMs = now - 29 * day }))
        XCTAssertFalse(eligible(changed(ready) { $0.prompts = 1; $0.lastPromptAtMs = now }))
        // a "last asked" in the future (a changed clock) does not count as 30 days ago
        XCTAssertFalse(eligible(changed(ready) { $0.prompts = 1; $0.lastPromptAtMs = now + day }))
        // never asked: no wait
        XCTAssertTrue(eligible(changed(ready) { $0.prompts = 0; $0.lastPromptAtMs = 0 }))
    }

    func testAFreshRecordIsNotEligible() {
        XCTAssertFalse(eligible(RatePrompt.Record()))
    }

    func testTheRulesAreTheDocumentedNumbers() {
        XCTAssertEqual(RatePrompt.minInstallDays, 3)
        XCTAssertEqual(RatePrompt.minOpenDays, 3)
        XCTAssertEqual(RatePrompt.minPositiveMoments, 2)
        XCTAssertEqual(RatePrompt.maxPrompts, 3)
        XCTAssertEqual(RatePrompt.minDaysBetweenPrompts, 30)
        XCTAssertEqual(RatePrompt.featureId, "rate_prompt")
    }

    // MARK: - the counters

    func testEachDifferentDayTheAppIsOpenedCountsOnce() {
        var r = RatePrompt.Record()
        r = RatePrompt.noteOpen(r, day: "2026-10-09")
        XCTAssertEqual(r.openDays, 1)
        XCTAssertEqual(r.lastOpenDay, "2026-10-09")
        r = RatePrompt.noteOpen(r, day: "2026-10-09")   // same day again
        XCTAssertEqual(r.openDays, 1)
        r = RatePrompt.noteOpen(r, day: "2026-10-10")
        r = RatePrompt.noteOpen(r, day: "2026-10-10")
        r = RatePrompt.noteOpen(r, day: "2026-10-12")   // a gap in days is fine
        XCTAssertEqual(r.openDays, 3)
        XCTAssertEqual(r.lastOpenDay, "2026-10-12")
    }

    func testABlankDayIsIgnoredAndNothingCountsOnceTheRepHasAnsweredForGood() {
        XCTAssertEqual(RatePrompt.noteOpen(RatePrompt.Record(), day: ""), RatePrompt.Record())
        XCTAssertEqual(RatePrompt.noteOpen(RatePrompt.Record(), day: "  "), RatePrompt.Record())
        let rated = RatePrompt.Record(state: .rated, openDays: 1)
        XCTAssertEqual(RatePrompt.noteOpen(rated, day: "2026-10-12"), rated)
        XCTAssertEqual(RatePrompt.notePositive(rated), rated)
        XCTAssertEqual(RatePrompt.maybeLater(rated, nowMs: now), rated)
        let never = RatePrompt.Record(state: .never, positives: 1)
        XCTAssertEqual(RatePrompt.notePositive(never), never)
    }

    func testGoodMomentsAddUp() {
        var r = RatePrompt.Record()
        r = RatePrompt.notePositive(r)
        r = RatePrompt.notePositive(r)
        XCTAssertEqual(r.positives, 2)
    }

    func testCountersStopGrowingAtASaneCeiling() {
        var r = RatePrompt.Record(openDays: 999, positives: 999)
        for _ in 0..<5 { r = RatePrompt.notePositive(r) }
        XCTAssertEqual(r.positives, 1000)
        r = RatePrompt.noteOpen(r, day: "d1")
        r = RatePrompt.noteOpen(r, day: "d2")
        XCTAssertEqual(r.openDays, 1000)
    }

    func testMaybeLaterRecordsTheTimeAndCountsAsAPrompt() {
        let r = RatePrompt.maybeLater(RatePrompt.Record(prompts: 1), nowMs: now)
        XCTAssertEqual(r.prompts, 2)
        XCTAssertEqual(r.lastPromptAtMs, now)
        XCTAssertEqual(r.state, .undecided)
    }

    func testRateNowAndDontAskAgainAreFinal() {
        XCTAssertEqual(RatePrompt.rated(RatePrompt.Record()).state, .rated)
        XCTAssertEqual(RatePrompt.never(RatePrompt.Record()).state, .never)
        // the first answer stays
        XCTAssertEqual(RatePrompt.never(RatePrompt.rated(RatePrompt.Record())).state, .rated)
        XCTAssertEqual(RatePrompt.rated(RatePrompt.never(RatePrompt.Record())).state, .never)
        // and afterwards the rep is not eligible however much they use the app
        XCTAssertFalse(eligible(RatePrompt.rated(ready)))
        XCTAssertFalse(eligible(RatePrompt.never(ready)))
    }

    func testAWholeStoryEligibleOnlyOnceAllTheRulesAreMetThenMaybeLaterWaitsThirtyDays() {
        let t0: Int64 = 1_790_845_200_000          // 2026-10-01 09:00 UTC
        let ist: TimeZone = TimeZone(secondsFromGMT: 19_800) ?? TimeZone.current
        var r = RatePrompt.Record()
        // day 0: install, open, one good moment
        r = RatePrompt.noteOpen(r, day: RatePrompt.dayOf(ms: t0, timeZone: ist))
        r = RatePrompt.notePositive(r)
        XCTAssertFalse(RatePrompt.eligible(featureOn: true, record: r, installMs: t0, nowMs: t0))
        // day 1: second day, second good moment - still not 3 days installed
        r = RatePrompt.noteOpen(r, day: RatePrompt.dayOf(ms: t0 + 1 * day, timeZone: ist))
        r = RatePrompt.notePositive(r)
        XCTAssertFalse(RatePrompt.eligible(featureOn: true, record: r, installMs: t0, nowMs: t0 + 2 * day))
        // day 3: third day opened, installed 3 days: eligible
        r = RatePrompt.noteOpen(r, day: RatePrompt.dayOf(ms: t0 + 3 * day, timeZone: ist))
        XCTAssertEqual(r.openDays, 3)
        XCTAssertTrue(RatePrompt.eligible(featureOn: true, record: r, installMs: t0, nowMs: t0 + 3 * day))
        // the rep says Maybe later
        r = RatePrompt.maybeLater(r, nowMs: t0 + 3 * day)
        XCTAssertFalse(RatePrompt.eligible(featureOn: true, record: r, installMs: t0, nowMs: t0 + 20 * day))
        XCTAssertFalse(RatePrompt.eligible(featureOn: true, record: r, installMs: t0, nowMs: t0 + 33 * day - 1))
        XCTAssertTrue(RatePrompt.eligible(featureOn: true, record: r, installMs: t0, nowMs: t0 + 33 * day))
    }

    func testTheDayIsThePhonesOwnCalendarDay() throws {
        let ms: Int64 = 1_791_748_800_000          // 2026-10-11 20:00 UTC
        let utc: TimeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let ist: TimeZone = TimeZone(secondsFromGMT: 19_800) ?? TimeZone.current
        let la: TimeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(RatePrompt.dayOf(ms: ms, timeZone: utc), "2026-10-11")
        XCTAssertEqual(RatePrompt.dayOf(ms: ms, timeZone: ist), "2026-10-12")
        XCTAssertEqual(RatePrompt.dayOf(ms: ms, timeZone: la), "2026-10-11")
    }

    func testMillisecondsSince1970() {
        XCTAssertEqual(RatePrompt.ms(Date(timeIntervalSince1970: 1_760_000_000)), 1_760_000_000_000)
        XCTAssertEqual(RatePrompt.ms(Date(timeIntervalSince1970: 1_760_000_000.5)), 1_760_000_000_500)
        XCTAssertEqual(RatePrompt.ms(Date(timeIntervalSince1970: 0)), 0)
    }

    // MARK: - did a form reach the server

    func testAFormReachedTheServerWhenTheOfflineQueueDidNotGrow() {
        XCTAssertTrue(RatePrompt.formReachedServer(pendingBefore: 0, pendingAfter: 0))
        XCTAssertTrue(RatePrompt.formReachedServer(pendingBefore: 2, pendingAfter: 2))
        // the queue emptied in the meantime
        XCTAssertTrue(RatePrompt.formReachedServer(pendingBefore: 3, pendingAfter: 1))
        // held back for later
        XCTAssertFalse(RatePrompt.formReachedServer(pendingBefore: 0, pendingAfter: 1))
        XCTAssertFalse(RatePrompt.formReachedServer(pendingBefore: 2, pendingAfter: 3))
    }

    // MARK: - the stored memory

    func testTheRecordRoundTripsThroughItsStoredText() {
        let r = RatePrompt.Record(state: .never, openDays: 7, lastOpenDay: "2026-10-11", positives: 12, prompts: 2, lastPromptAtMs: 1_760_000_000_000)
        XCTAssertEqual(RatePrompt.decode(RatePrompt.encode(r)), r)
        XCTAssertEqual(RatePrompt.decode(RatePrompt.encode(RatePrompt.Record())), RatePrompt.Record())
        for state in RatePrompt.State.allCases {
            XCTAssertEqual(RatePrompt.decode(RatePrompt.encode(RatePrompt.Record(state: state))).state, state)
        }
    }

    func testTheStoredTextHasTheDocumentedShape() {
        let r = RatePrompt.Record(state: .rated, openDays: 3, lastOpenDay: "2026-10-11", positives: 2, prompts: 1, lastPromptAtMs: 5)
        XCTAssertEqual(RatePrompt.encode(r), "v1;RATED;3;2026-10-11;2;1;5")
        XCTAssertEqual(RatePrompt.encode(RatePrompt.Record()), "v1;NONE;0;;0;0;0")
    }

    func testAnUnreadableMemoryReadsAsAFreshRecord() {
        let junk: [String?] = [nil, "", "  ", "garbage", "v2;NONE;1;d;1;1;1", "v1;NONE;1;d;1;1", "v1;NONE;1;d;1;1;1;9",
                               "v1;MAYBE;1;d;1;1;1", "v1;NONE;x;d;1;1;1", "v1;NONE;1;d;x;1;1", "v1;NONE;1;d;1;x;1", "v1;NONE;1;d;1;1;x"]
        for bad in junk {
            XCTAssertEqual(RatePrompt.decode(bad), RatePrompt.Record(), bad ?? "nil")
        }
    }

    func testNegativeOrHugeStoredNumbersAreBroughtBackIntoRange() {
        let r = RatePrompt.decode("v1;NONE;-5;d;999999;-1;-100")
        XCTAssertEqual(r.openDays, 0)
        XCTAssertEqual(r.positives, 1000)
        XCTAssertEqual(r.prompts, 0)
        XCTAssertEqual(r.lastPromptAtMs, 0)
    }

    // MARK: - the store (its own UserDefaults suite)

    private func withSuite(_ body: (UserDefaults) throws -> Void) throws {
        let name = "RatePromptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testAnEmptyDeviceHasAFreshRecordAndNoFirstLaunch() throws {
        try withSuite { d in
            XCTAssertEqual(RatePromptStore.read(in: d), RatePrompt.Record())
            XCTAssertNil(RatePromptStore.firstLaunchMs(in: d))
        }
    }

    func testAnUpdateIsStoredAndReadBack() throws {
        try withSuite { d in
            RatePromptStore.update(in: d) { RatePrompt.notePositive(RatePrompt.noteOpen($0, day: "2026-10-10")) }
            let back = RatePromptStore.read(in: d)
            XCTAssertEqual(back.openDays, 1)
            XCTAssertEqual(back.positives, 1)
            XCTAssertEqual(back.lastOpenDay, "2026-10-10")
            XCTAssertEqual(d.string(forKey: "rate_prompt_record"), "v1;NONE;1;2026-10-10;1;0;0")
        }
    }

    func testAnUpdateThatChangesNothingWritesNothing() throws {
        try withSuite { d in
            RatePromptStore.update(in: d) { $0 }
            XCTAssertNil(d.string(forKey: RatePromptStore.recordKey))
            RatePromptStore.update(in: d) { RatePrompt.noteOpen($0, day: "") }
            XCTAssertNil(d.string(forKey: RatePromptStore.recordKey))
        }
    }

    func testADamagedStoredRecordIsReplacedByTheNextUpdate() throws {
        try withSuite { d in
            d.set("garbage", forKey: RatePromptStore.recordKey)
            XCTAssertEqual(RatePromptStore.read(in: d), RatePrompt.Record())
            RatePromptStore.update(in: d) { RatePrompt.notePositive($0) }
            XCTAssertEqual(RatePromptStore.read(in: d).positives, 1)
        }
    }

    func testTheFirstLaunchIsRecordedOnceAndNeverMoved() throws {
        try withSuite { d in
            RatePromptStore.recordFirstLaunchIfNeeded(now: Date(timeIntervalSince1970: 1_760_000_000), in: d)
            XCTAssertEqual(RatePromptStore.firstLaunchMs(in: d), 1_760_000_000_000)
            RatePromptStore.recordFirstLaunchIfNeeded(now: Date(timeIntervalSince1970: 1_770_000_000), in: d)
            XCTAssertEqual(RatePromptStore.firstLaunchMs(in: d), 1_760_000_000_000)
        }
    }

    func testAnUnusableFirstLaunchValueReadsAsUnknown() throws {
        try withSuite { d in
            d.set(NSNumber(value: 0 as Int64), forKey: RatePromptStore.firstLaunchKey)
            XCTAssertNil(RatePromptStore.firstLaunchMs(in: d))
            d.set(NSNumber(value: -5 as Int64), forKey: RatePromptStore.firstLaunchKey)
            XCTAssertNil(RatePromptStore.firstLaunchMs(in: d))
            d.set("soon", forKey: RatePromptStore.firstLaunchKey)
            XCTAssertNil(RatePromptStore.firstLaunchMs(in: d))
        }
    }

    // MARK: - the coordinator (the session side)

    private let userKey = "current_user"

    /// Runs `body` with a stored session whose client has `features` (a JSON object such as `{"rate_prompt":true}`, nil
    /// = no `features` at all), putting the stored session back exactly as it was afterwards (the session is a global).
    private func withSignedInClient(features: String?, _ body: () throws -> Void) throws {
        let saved = UserDefaults.standard.data(forKey: userKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: userKey) }
            else { UserDefaults.standard.removeObject(forKey: userKey) }
        }
        let extra = features.map { #","app_ui_config":{"features":\#($0)}"# } ?? ""
        let json = #"{"id":"u1","name":"Asha","role":"executive"\#(extra)}"#
        Session.currentUser = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        try body()
    }

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private let oneDay: TimeInterval = 24 * 60 * 60

    private func at(_ days: Double) -> Date { t0.addingTimeInterval(days * oneDay) }

    /// A phone that has been used enough: first launch at t0, opened on three days, two good moments.
    private func useTheAppEnough(_ c: RatePromptCoordinator, _ d: UserDefaults) {
        RatePromptStore.recordFirstLaunchIfNeeded(now: t0, in: d)
        c.noteAppOpened(now: at(0))
        c.noteAppOpened(now: at(1))
        c.noteAppOpened(now: at(2))
        c.notePositiveMoment()
        c.notePositiveMoment()
    }

    func testNothingMovesForAClientThatHasNotOptedIn() throws {
        let clients: [String?] = [nil, #"{}"#, #"{"rate_prompt":false}"#, #"{"something_else":true}"#]
        for features in clients {
            try withSignedInClient(features: features) {
                try withSuite { d in
                    let c = RatePromptCoordinator(defaults: d)
                    useTheAppEnough(c, d)
                    c.offer(now: at(40))
                    XCTAssertFalse(c.showingPrompt, features ?? "nil")
                    XCTAssertEqual(RatePromptStore.read(in: d), RatePrompt.Record(), features ?? "nil")
                    XCTAssertNil(d.string(forKey: RatePromptStore.recordKey), features ?? "nil")
                }
            }
        }
    }

    func testNothingMovesWithNoSignedInUser() throws {
        let saved = UserDefaults.standard.data(forKey: userKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: userKey) }
            else { UserDefaults.standard.removeObject(forKey: userKey) }
        }
        UserDefaults.standard.removeObject(forKey: userKey)
        try withSuite { d in
            let c = RatePromptCoordinator(defaults: d)
            useTheAppEnough(c, d)
            c.offer(now: at(40))
            XCTAssertFalse(c.showingPrompt)
            XCTAssertEqual(RatePromptStore.read(in: d), RatePrompt.Record())
        }
    }

    func testAnOptedInClientCountsDaysAndGoodMomentsAndIsOfferedTheDialogOnceTheRulesAreMet() throws {
        try withSignedInClient(features: #"{"rate_prompt":true}"#) {
            try withSuite { d in
                let c = RatePromptCoordinator(defaults: d)
                useTheAppEnough(c, d)
                let record = RatePromptStore.read(in: d)
                XCTAssertEqual(record.openDays, 3)
                XCTAssertEqual(record.positives, 2)
                // installed 2 days: too early
                c.offer(now: at(2))
                XCTAssertFalse(c.showingPrompt)
                // installed exactly 3 days: due
                c.offer(now: at(3))
                XCTAssertTrue(c.showingPrompt)
            }
        }
    }

    func testTheSameDayCountsOnce() throws {
        try withSignedInClient(features: #"{"rate_prompt":true}"#) {
            try withSuite { d in
                let c = RatePromptCoordinator(defaults: d)
                c.noteAppOpened(now: at(0))
                c.noteAppOpened(now: at(0).addingTimeInterval(60))
                XCTAssertEqual(RatePromptStore.read(in: d).openDays, 1)
                // another session (a new coordinator) on the same day does not count it again either
                let again = RatePromptCoordinator(defaults: d)
                again.noteAppOpened(now: at(0).addingTimeInterval(120))
                XCTAssertEqual(RatePromptStore.read(in: d).openDays, 1)
            }
        }
    }

    func testWithdrawingTakesTheDialogBackAndItCanComeAgainOnALaterVisit() throws {
        try withSignedInClient(features: #"{"rate_prompt":true}"#) {
            try withSuite { d in
                let c = RatePromptCoordinator(defaults: d)
                useTheAppEnough(c, d)
                c.offer(now: at(3))
                XCTAssertTrue(c.showingPrompt)
                c.withdraw()
                XCTAssertFalse(c.showingPrompt)
                // nothing was answered, nothing was remembered as a prompt
                XCTAssertEqual(RatePromptStore.read(in: d).prompts, 0)
                c.offer(now: at(3))
                XCTAssertTrue(c.showingPrompt)
            }
        }
    }

    func testMaybeLaterEndsTheOfferForThisSessionAndWaitsThirtyDaysAfterwards() throws {
        try withSignedInClient(features: #"{"rate_prompt":true}"#) {
            try withSuite { d in
                let c = RatePromptCoordinator(defaults: d)
                useTheAppEnough(c, d)
                c.offer(now: at(3))
                XCTAssertTrue(c.showingPrompt)
                c.maybeLater(now: at(3))
                XCTAssertFalse(c.showingPrompt)
                XCTAssertEqual(RatePromptStore.read(in: d).prompts, 1)
                XCTAssertEqual(RatePromptStore.read(in: d).lastPromptAtMs, RatePrompt.ms(at(3)))
                // once per session: not again, however long the app stays open
                c.offer(now: at(60))
                XCTAssertFalse(c.showingPrompt)
                // a later session: still inside the 30 days ...
                let later = RatePromptCoordinator(defaults: d)
                later.offer(now: at(32))
                XCTAssertFalse(later.showingPrompt)
                // ... and exactly 30 days after the answer it is due again
                later.offer(now: at(33))
                XCTAssertTrue(later.showingPrompt)
            }
        }
    }

    func testRatingEndsItForGood() throws {
        try withSignedInClient(features: #"{"rate_prompt":true}"#) {
            try withSuite { d in
                let c = RatePromptCoordinator(defaults: d)
                useTheAppEnough(c, d)
                c.offer(now: at(3))
                XCTAssertTrue(c.showingPrompt)
                c.rated()
                XCTAssertFalse(c.showingPrompt)
                XCTAssertEqual(RatePromptStore.read(in: d).state, .rated)
                let later = RatePromptCoordinator(defaults: d)
                later.offer(now: at(400))
                XCTAssertFalse(later.showingPrompt)
            }
        }
    }

    func testDontAskAgainEndsItForGood() throws {
        try withSignedInClient(features: #"{"rate_prompt":true}"#) {
            try withSuite { d in
                let c = RatePromptCoordinator(defaults: d)
                useTheAppEnough(c, d)
                c.offer(now: at(3))
                c.never()
                XCTAssertFalse(c.showingPrompt)
                XCTAssertEqual(RatePromptStore.read(in: d).state, .never)
                let later = RatePromptCoordinator(defaults: d)
                later.offer(now: at(400))
                XCTAssertFalse(later.showingPrompt)
                // and nothing counts any more
                later.notePositiveMoment()
                later.noteAppOpened(now: at(401))
                XCTAssertEqual(RatePromptStore.read(in: d).positives, 2)
                XCTAssertEqual(RatePromptStore.read(in: d).openDays, 3)
            }
        }
    }

    func testTheSettingsRowRatingWorksEvenBeforeTheRulesAreMet() throws {
        // `rated()` is also what the Settings row calls: a rep who rates from there is never nagged
        try withSignedInClient(features: #"{"rate_prompt":true}"#) {
            try withSuite { d in
                let c = RatePromptCoordinator(defaults: d)
                c.rated()
                XCTAssertEqual(RatePromptStore.read(in: d).state, .rated)
                useTheAppEnough(c, d)
                c.offer(now: at(10))
                XCTAssertFalse(c.showingPrompt)
            }
        }
    }

    func testTheCountersAreTheDevicesAndNotThePersons() throws {
        // another person signs in on the same phone: the same record, the same install date
        try withSuite { d in
            try withSignedInClient(features: #"{"rate_prompt":true}"#) {
                let c = RatePromptCoordinator(defaults: d)
                useTheAppEnough(c, d)
            }
            try withSignedInClient(features: #"{"rate_prompt":true}"#) {
                let other = RatePromptCoordinator(defaults: d)
                other.offer(now: at(3))
                XCTAssertTrue(other.showingPrompt)
            }
        }
    }
}
