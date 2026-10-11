//
//  AttendanceRulesTests.swift
//  KinematicTests
//
//  The per-client attendance rules (`GET /attendance/rules`): the defaults ARE today's behaviour (selfie required, no
//  form check-in, no travel question, no offline capture), only an explicit value changes anything, a missing / unknown /
//  mistyped key never fails the load, the last answer is remembered per user (and wiped at sign-out), and the holder
//  that the screens read fails soft.
//

import XCTest
@testable import Kinematic

@MainActor
final class AttendanceRulesTests: XCTestCase {

    /// The reply's JSON as the app sees it (the tolerant tree), parsed the way `fetchAttendanceRules` does.
    private func info(_ json: String) -> AttendanceRulesInfo? {
        let tree: AnyJSON? = try? JSONDecoder().decode(AnyJSON.self, from: Data(json.utf8))
        return AttendanceRulesParser.info(from: tree)
    }

    /// Runs `body` with a UserDefaults of its own (never `.standard`), removed afterwards.
    private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "AttendanceRulesTests." + UUID().uuidString
        guard let d = UserDefaults(suiteName: name) else { return XCTFail("could not make a test UserDefaults") }
        defer { d.removePersistentDomain(forName: name) }
        try body(d)
    }

    private let fourModes = """
    [{"id":"two_wheeler","label":"Two-wheeler","vehicle":true},
     {"id":"car","label":"Car","vehicle":true},
     {"id":"public_transport","label":"Public transport","vehicle":false},
     {"id":"other","label":"Other","vehicle":false}]
    """

    // MARK: - the defaults are today's behaviour

    func testTheDefaultsAreTheAppAsItWas() {
        let r = AttendanceRules()
        XCTAssertTrue(r.selfieRequired)
        XCTAssertFalse(r.formCheckinRequired)
        XCTAssertFalse(r.trackTransportMode)
        XCTAssertEqual(r.transportModes, [])
        XCTAssertFalse(r.allowOfflineCheckin)
        XCTAssertFalse(r.transportPromptActive)
        XCTAssertTrue(r.needsCamera)
        XCTAssertNil(r.shiftStart)
        XCTAssertNil(r.graceMinutes)
    }

    // MARK: - reading the reply

    func testConfiguredRulesAreRead() throws {
        let i = try XCTUnwrap(info("""
        {"success":true,"data":{"configured":true,"rules":{"shift_start":"10:00","shift_end":"19:00","grace_minutes":10,
         "weekly_off":[0,6],"allow_offline_checkin":true}}}
        """))
        XCTAssertTrue(i.configured)
        XCTAssertEqual(i.rules.shiftStart, "10:00")
        XCTAssertEqual(i.rules.shiftEnd, "19:00")
        XCTAssertEqual(i.rules.graceMinutes, 10)
        XCTAssertEqual(i.rules.weeklyOff, [0, 6])
        XCTAssertTrue(i.rules.allowOfflineCheckin)
    }

    func testUnconfiguredRulesComeBackAsTheDefaults() throws {
        let i = try XCTUnwrap(info(#"{"configured":false,"rules":{}}"#))
        XCTAssertFalse(i.configured)
        XCTAssertEqual(i.rules, AttendanceRules())
    }

    func testMissingOrOddValuesFallBackToDefaultsAndAMissingConfiguredFlagMeansNotConfigured() throws {
        let i = try XCTUnwrap(info(#"{"data":{"rules":{"shift_start":"09:00","grace_minutes":"20","allow_offline_checkin":"true"}}}"#))
        XCTAssertFalse(i.configured)
        XCTAssertEqual(i.rules.shiftStart, "09:00")
        XCTAssertNil(i.rules.shiftEnd)
        XCTAssertEqual(i.rules.graceMinutes, 20)          // a number sent as a string is tolerated
        XCTAssertTrue(i.rules.allowOfflineCheckin)        // so is a boolean
        XCTAssertNil(i.rules.weeklyOff)
    }

    func testSelfieAndFormCheckInAbsentMeansSelfieRequiredAndNoFormCheckIn() throws {
        let off = try XCTUnwrap(info(#"{"success":true,"data":{"configured":true,"rules":{"selfie_required":false,"form_checkin_required":true}}}"#))
        XCTAssertFalse(off.rules.selfieRequired)
        XCTAssertTrue(off.rules.formCheckinRequired)
        XCTAssertFalse(off.rules.needsCamera)

        let on = try XCTUnwrap(info(#"{"data":{"configured":true,"rules":{"selfie_required":true,"form_checkin_required":false}}}"#))
        XCTAssertTrue(on.rules.selfieRequired)
        XCTAssertFalse(on.rules.formCheckinRequired)

        // an older server that does not send them: the safe defaults
        let old = try XCTUnwrap(info(#"{"data":{"configured":true,"rules":{"shift_start":"10:00","allow_offline_checkin":true}}}"#))
        XCTAssertTrue(old.rules.selfieRequired)
        XCTAssertFalse(old.rules.formCheckinRequired)
        XCTAssertTrue(old.rules.allowOfflineCheckin)

        let none = try XCTUnwrap(info(#"{"configured":false,"rules":{}}"#))
        XCTAssertTrue(none.rules.selfieRequired)
        XCTAssertFalse(none.rules.formCheckinRequired)
    }

    func testOddValuesForTheSwitchesFallBackToTheSafeDefaultsAndStringsAreTolerated() throws {
        let odd = try XCTUnwrap(info(#"{"data":{"rules":{"selfie_required":"maybe","form_checkin_required":[]}}}"#))
        XCTAssertTrue(odd.rules.selfieRequired)
        XCTAssertFalse(odd.rules.formCheckinRequired)
        let str = try XCTUnwrap(info(#"{"data":{"rules":{"selfie_required":"false","form_checkin_required":"true"}}}"#))
        XCTAssertFalse(str.rules.selfieRequired)
        XCTAssertTrue(str.rules.formCheckinRequired)
    }

    func testUnknownKeysAndExtraTopLevelKeysNeverFailTheLoad() throws {
        let i = try XCTUnwrap(info("""
        {"success":true,"message":"ok","data":{"configured":true,"future":{"a":1},"rules":{"selfie_required":false,"some_new_rule":[1,2,3],"another":null}}}
        """))
        XCTAssertTrue(i.configured)
        XCTAssertFalse(i.rules.selfieRequired)
    }

    func testAReplyThatIsNotAnObjectIsUnreadable() {
        XCTAssertNil(AttendanceRulesParser.info(from: nil))
        XCTAssertNil(info("[]"))
        XCTAssertNil(info("\"x\""))
        // a null `data` leaves the envelope itself, which holds no rules: the defaults, not configured
        let bare = info(#"{"success":true,"data":null}"#)
        XCTAssertEqual(bare?.configured, false)
        XCTAssertEqual(bare?.rules, AttendanceRules())
    }

    // MARK: - mode of transport in the reply

    func testTrackTransportModeAndTheChoicesAreRead() throws {
        let i = try XCTUnwrap(info("""
        {"success":true,"data":{"configured":true,"rules":{"shift_start":"10:00","track_transport_mode":true},"transport_modes":\(fourModes)}}
        """))
        XCTAssertTrue(i.rules.trackTransportMode)
        XCTAssertEqual(i.rules.transportModes.map { $0.id }, ["two_wheeler", "car", "public_transport", "other"])
        XCTAssertEqual(i.rules.transportModes.map { $0.label }, ["Two-wheeler", "Car", "Public transport", "Other"])
        XCTAssertEqual(i.rules.transportModes.map { $0.vehicle }, [true, true, false, false])
        XCTAssertTrue(i.rules.transportPromptActive)
    }

    func testWithoutTheRuleOrTheChoicesTheQuestionStaysOff() throws {
        // an older server that sends neither
        let old = try XCTUnwrap(info(#"{"data":{"configured":true,"rules":{"shift_start":"10:00","allow_offline_checkin":true}}}"#))
        XCTAssertFalse(old.rules.trackTransportMode)
        XCTAssertEqual(old.rules.transportModes, [])
        // the rule explicitly off
        let off = try XCTUnwrap(info(#"{"data":{"rules":{"track_transport_mode":false}}}"#))
        XCTAssertFalse(off.rules.trackTransportMode)
        // the rule on, the choices missing: nothing is asked (guessing ids would only get the check-in refused)
        let noChoices = try XCTUnwrap(info(#"{"data":{"rules":{"track_transport_mode":true}}}"#))
        XCTAssertTrue(noChoices.rules.trackTransportMode)
        XCTAssertEqual(noChoices.rules.transportModes, [])
        XCTAssertFalse(noChoices.rules.transportPromptActive)
        // choices sent while the rule is off are not kept
        let ignored = try XCTUnwrap(info("""
        {"data":{"rules":{"track_transport_mode":false},"transport_modes":\(fourModes)}}
        """))
        XCTAssertEqual(ignored.rules.transportModes, [])
        // nothing configured at all
        let none = try XCTUnwrap(info(#"{"configured":false,"rules":{}}"#))
        XCTAssertFalse(none.rules.trackTransportMode)
        XCTAssertEqual(none.rules.transportModes, [])
    }

    func testOddTransportValuesFallBackToTheSafeDefaultsAndStringsAreTolerated() throws {
        let odd = try XCTUnwrap(info(#"{"data":{"rules":{"track_transport_mode":"maybe"},"transport_modes":"car"}}"#))
        XCTAssertFalse(odd.rules.trackTransportMode)
        XCTAssertEqual(odd.rules.transportModes, [])
        let str = try XCTUnwrap(info(#"{"data":{"rules":{"track_transport_mode":"true"}}}"#))
        XCTAssertTrue(str.rules.trackTransportMode)
    }

    func testAChoiceWithoutAnAcceptableIdIsSkippedAndAMissingLabelReadsAsTheId() throws {
        let i = try XCTUnwrap(info("""
        {"data":{"rules":{"track_transport_mode":true},"transport_modes":[
          {"id":"own_bike","vehicle":true},
          {"label":"No id"},
          {"id":"Bad Id","label":"Spaces and capitals"},
          {"id":"car","label":"Car","vehicle":"true"},
          {"id":"car","label":"Car again"},
          "junk", 7, null,
          {"id":"other","label":"Other"}]}}
        """))
        let modes = i.rules.transportModes
        XCTAssertEqual(modes.map { $0.id }, ["own_bike", "car", "other"])
        XCTAssertEqual(modes[0].label, "Own bike")
        XCTAssertTrue(modes[0].vehicle)
        XCTAssertTrue(modes[1].vehicle)               // "true" as a string is tolerated, like the other flags
        XCTAssertEqual(modes[1].label, "Car")         // the first of a repeated id wins
    }

    func testTheChoicesAreAlsoReadWhenAServerNestsThemInsideRules() throws {
        let i = try XCTUnwrap(info("""
        {"data":{"rules":{"track_transport_mode":true,"transport_modes":[{"id":"car","label":"Car","vehicle":true}]}}}
        """))
        XCTAssertEqual(i.rules.transportModes.map { $0.id }, ["car"])
    }

    // MARK: - the model decodes (and survives a save and load) without failing

    func testTheModelDecodesFromAnyShapeWithoutFailing() throws {
        let weird = try JSONDecoder().decode(AttendanceRules.self, from: Data(#"{"selfie_required":"nope","track_transport_mode":3,"x":{}}"#.utf8))
        XCTAssertTrue(weird.selfieRequired)
        // a number is a switch (non-zero = on) but with no choices nothing is asked
        XCTAssertTrue(weird.trackTransportMode)
        XCTAssertFalse(weird.transportPromptActive)
        let notAnObject = try JSONDecoder().decode(AttendanceRules.self, from: Data("[1,2]".utf8))
        XCTAssertEqual(notAnObject, AttendanceRules())
        let empty = try JSONDecoder().decode(AttendanceRules.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, AttendanceRules())
    }

    func testTheRulesSurviveASaveAndLoad() throws {
        var r = AttendanceRules()
        r.selfieRequired = false
        r.formCheckinRequired = true
        r.trackTransportMode = true
        r.allowOfflineCheckin = true
        r.shiftStart = "10:00"
        r.shiftEnd = "19:00"
        r.graceMinutes = 10
        r.weeklyOff = [0, 6]
        r.transportModes = [TransportOption(id: "car", label: "Car", vehicle: true), TransportOption(id: "other", label: "Other")]
        let back = try JSONDecoder().decode(AttendanceRules.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }

    func testAChoiceDecodesWhateverIsMissing() throws {
        let o = try JSONDecoder().decode(TransportOption.self, from: Data(#"{"id":"car"}"#.utf8))
        XCTAssertEqual(o, TransportOption(id: "car", label: "", vehicle: false))
        let none = try JSONDecoder().decode(TransportOption.self, from: Data("{}".utf8))
        XCTAssertEqual(none.id, "")
    }

    // MARK: - remembered per user

    func testTheCacheKeyIsPerUserAndNeedsAUser() {
        XCTAssertEqual(AttendanceRulesCache.key(userId: "u1"), "attendance_rules.u1")
        XCTAssertEqual(AttendanceRulesCache.key(userId: " u1 "), "attendance_rules.u1")
        XCTAssertNil(AttendanceRulesCache.key(userId: nil))
        XCTAssertNil(AttendanceRulesCache.key(userId: "  "))
    }

    func testTheRememberedAnswerIsThisUsersAndSurvivesALoad() {
        withSuite { d in
            var r = AttendanceRules()
            r.selfieRequired = false
            r.trackTransportMode = true
            r.transportModes = [TransportOption(id: "car", label: "Car", vehicle: true)]
            let k = AttendanceRulesCache.key(userId: "u1")
            XCTAssertNil(AttendanceRulesCache.read(key: k, in: d))
            AttendanceRulesCache.write(r, key: k, in: d)
            XCTAssertEqual(AttendanceRulesCache.read(key: k, in: d), r)
            // another person never reads it
            XCTAssertNil(AttendanceRulesCache.read(key: AttendanceRulesCache.key(userId: "u2"), in: d))
            // nothing is written without a user
            AttendanceRulesCache.write(r, key: nil, in: d)
            XCTAssertNil(AttendanceRulesCache.read(key: nil, in: d))
        }
    }

    func testSigningOutWipesTheRememberedRulesOfEveryone() {
        withSuite { d in
            var r = AttendanceRules()
            r.selfieRequired = false
            AttendanceRulesCache.write(r, key: AttendanceRulesCache.key(userId: "u1"), in: d)
            AttendanceRulesCache.write(r, key: AttendanceRulesCache.key(userId: "u2"), in: d)
            d.set("dark", forKey: "app_theme")
            XCTAssertTrue(SessionCleanup.userDefaultsKeyPrefixes.contains(AttendanceRulesCache.keyPrefix))

            SessionCleanup.clearPersistedUserState(in: d)

            XCTAssertNil(AttendanceRulesCache.read(key: AttendanceRulesCache.key(userId: "u1"), in: d))
            XCTAssertNil(AttendanceRulesCache.read(key: AttendanceRulesCache.key(userId: "u2"), in: d))
            XCTAssertEqual(d.string(forKey: "app_theme"), "dark")
        }
    }

    // MARK: - when to ask the server again

    func testASuccessfulAnswerIsTrustedForFiveMinutesAFailedOneRetriedAfterAMinute() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // nothing asked yet this run, or forced: ask
        XCTAssertTrue(AttendanceRulesRefresh.shouldRefresh(now: t0, stamp: nil, force: false))
        XCTAssertTrue(AttendanceRulesRefresh.shouldRefresh(now: t0, stamp: t0, force: true))

        let ok = AttendanceRulesRefresh.stampAfterAttempt(now: t0, success: true)
        XCTAssertFalse(AttendanceRulesRefresh.shouldRefresh(now: t0.addingTimeInterval(299), stamp: ok, force: false))
        XCTAssertTrue(AttendanceRulesRefresh.shouldRefresh(now: t0.addingTimeInterval(300), stamp: ok, force: false))

        let failed = AttendanceRulesRefresh.stampAfterAttempt(now: t0, success: false)
        XCTAssertFalse(AttendanceRulesRefresh.shouldRefresh(now: t0.addingTimeInterval(59), stamp: failed, force: false))
        XCTAssertTrue(AttendanceRulesRefresh.shouldRefresh(now: t0.addingTimeInterval(60), stamp: failed, force: false))

        // the clock moved back: ask rather than trust a stamp from the future
        XCTAssertTrue(AttendanceRulesRefresh.shouldRefresh(now: t0.addingTimeInterval(-10), stamp: ok, force: false))
    }

    // MARK: - the holder the screens read

    private func configured(selfie: Bool = false) -> AttendanceRulesInfo {
        var r = AttendanceRules()
        r.selfieRequired = selfie
        r.trackTransportMode = true
        r.transportModes = [TransportOption(id: "car", label: "Car", vehicle: true)]
        return AttendanceRulesInfo(configured: true, rules: r)
    }

    func testBeforeAnyAnswerTheHolderIsTodaysBehaviour() {
        withSuite { d in
            let store = AttendanceRulesStore(defaults: d, userId: { "u1" }, fetch: { nil })
            XCTAssertEqual(store.rules, AttendanceRules())
            XCTAssertFalse(store.didLoad)
        }
    }

    func testAnAnswerIsAdoptedRememberedAndMarksTheHolderLoaded() async {
        let d = UserDefaults(suiteName: "AttendanceRulesTests.store1")!
        d.removePersistentDomain(forName: "AttendanceRulesTests.store1")
        defer { d.removePersistentDomain(forName: "AttendanceRulesTests.store1") }
        let answer = configured()
        let store = AttendanceRulesStore(defaults: d, userId: { "u1" }, fetch: { answer })
        await store.refresh()
        XCTAssertEqual(store.rules, answer.rules)
        XCTAssertTrue(store.didLoad)
        XCTAssertEqual(AttendanceRulesCache.read(key: AttendanceRulesCache.key(userId: "u1"), in: d), answer.rules)
    }

    func testAFailedFetchFailsSoftToTheDefaultsAndStillUnblocksTheScreen() async {
        let d = UserDefaults(suiteName: "AttendanceRulesTests.store2")!
        d.removePersistentDomain(forName: "AttendanceRulesTests.store2")
        defer { d.removePersistentDomain(forName: "AttendanceRulesTests.store2") }
        let store = AttendanceRulesStore(defaults: d, userId: { "u1" }, fetch: { nil })
        await store.refresh()
        XCTAssertEqual(store.rules, AttendanceRules())
        XCTAssertTrue(store.didLoad)
        XCTAssertNil(AttendanceRulesCache.read(key: AttendanceRulesCache.key(userId: "u1"), in: d))
    }

    func testARememberedAnswerIsUsedAtOnceAndKeptWhenTheFetchFails() async {
        let d = UserDefaults(suiteName: "AttendanceRulesTests.store3")!
        d.removePersistentDomain(forName: "AttendanceRulesTests.store3")
        defer { d.removePersistentDomain(forName: "AttendanceRulesTests.store3") }
        let answer = configured()
        AttendanceRulesCache.write(answer.rules, key: AttendanceRulesCache.key(userId: "u1"), in: d)

        let store = AttendanceRulesStore(defaults: d, userId: { "u1" }, fetch: { nil })
        // an offline start: the behaviour the server last told this person, before any network
        XCTAssertEqual(store.rules, answer.rules)
        XCTAssertTrue(store.didLoad)
        await store.refresh()
        XCTAssertEqual(store.rules, answer.rules)
    }

    func testAnotherPersonNeverInheritsTheRules() async {
        let d = UserDefaults(suiteName: "AttendanceRulesTests.store4")!
        d.removePersistentDomain(forName: "AttendanceRulesTests.store4")
        defer { d.removePersistentDomain(forName: "AttendanceRulesTests.store4") }
        let answer = configured()
        var who: String? = "u1"
        let store = AttendanceRulesStore(defaults: d, userId: { who }, fetch: { answer })
        await store.refresh()
        XCTAssertEqual(store.currentRules(), answer.rules)

        who = "u2"
        XCTAssertEqual(store.currentRules(), AttendanceRules())
        XCTAssertFalse(store.didLoad)

        who = nil
        XCTAssertEqual(store.currentRules(), AttendanceRules())

        store.reset()
        XCTAssertEqual(store.rules, AttendanceRules())
        XCTAssertFalse(store.didLoad)
    }

    func testTheServerIsAskedAgainOnlyWhenDueOrForced() async {
        let d = UserDefaults(suiteName: "AttendanceRulesTests.store5")!
        d.removePersistentDomain(forName: "AttendanceRulesTests.store5")
        defer { d.removePersistentDomain(forName: "AttendanceRulesTests.store5") }
        let answer = configured()
        var calls = 0
        let store = AttendanceRulesStore(defaults: d, userId: { "u1" }, fetch: { calls += 1; return answer })
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(calls, 1)
        await store.refresh(force: true)
        XCTAssertEqual(calls, 2)
    }

    func testAnAnswerThatArrivesAfterTheUserChangedIsNotTheirs() async {
        let d = UserDefaults(suiteName: "AttendanceRulesTests.store6")!
        d.removePersistentDomain(forName: "AttendanceRulesTests.store6")
        defer { d.removePersistentDomain(forName: "AttendanceRulesTests.store6") }
        let answer = configured()
        var who: String? = "u1"
        let store = AttendanceRulesStore(defaults: d, userId: { who }, fetch: {
            who = "u2"            // somebody else signs in while the request is in flight
            return answer
        })
        await store.refresh()
        XCTAssertEqual(store.currentRules(), AttendanceRules())
        XCTAssertNil(AttendanceRulesCache.read(key: AttendanceRulesCache.key(userId: "u1"), in: d))
        XCTAssertNil(AttendanceRulesCache.read(key: AttendanceRulesCache.key(userId: "u2"), in: d))
    }
}
