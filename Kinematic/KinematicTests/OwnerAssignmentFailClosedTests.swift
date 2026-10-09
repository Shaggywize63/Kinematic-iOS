//
//  OwnerAssignmentFailClosedTests.swift
//  KinematicTests
//
//  `lead_form.owner_assignment == "admin_only"` must not switch itself off just because the settings request
//  failed. A load that SUCCEEDS decides by itself, exactly as it always did (no flag = the owner picker as before);
//  a load that FAILS keeps the value this user last loaded successfully for this client, and with none a non-admin
//  is treated as restricted (their Owner controls stay hidden). Admins are never affected. Also: the real
//  GET /crm/settings payload of a client with every lead-form key decodes and parses, and a reply without the
//  `config` object counts as a failed load (it is what a mis-shaped reply silently decodes to).
//

import XCTest
@testable import Kinematic

@MainActor
final class OwnerAssignmentFailClosedTests: XCTestCase {

    // MARK: - the pure rule

    func testASuccessfulLoadDecidesByItselfWhateverWasCachedAndWhoeverAsks() {
        for cached in [nil, true, false] as [Bool?] {
            for isAdmin in [true, false] {
                XCTAssertTrue(LeadOwnerRules.effectiveAdminOnly(loaded: true, cached: cached, isAdmin: isAdmin))
                // "No flag" is a success that says false: the picker as before, even if the last value was true.
                XCTAssertFalse(LeadOwnerRules.effectiveAdminOnly(loaded: false, cached: cached, isAdmin: isAdmin))
            }
        }
    }

    func testAFailedLoadKeepsTheLastKnownValue() {
        for isAdmin in [true, false] {
            XCTAssertTrue(LeadOwnerRules.effectiveAdminOnly(loaded: nil, cached: true, isAdmin: isAdmin))
            XCTAssertFalse(LeadOwnerRules.effectiveAdminOnly(loaded: nil, cached: false, isAdmin: isAdmin))
        }
    }

    func testAFailedLoadWithNothingRememberedRestrictsANonAdminButNotAnAdmin() {
        XCTAssertTrue(LeadOwnerRules.effectiveAdminOnly(loaded: nil, cached: nil, isAdmin: false))
        XCTAssertFalse(LeadOwnerRules.effectiveAdminOnly(loaded: nil, cached: nil, isAdmin: true))
    }

    func testTheFailClosedValueHidesTheNonAdminsControlsAndLeavesAnAdminsAlone() {
        // The value the model ends up with, run through the existing gates.
        let restricted = LeadOwnerRules.effectiveAdminOnly(loaded: nil, cached: nil, isAdmin: false)
        XCTAssertFalse(LeadOwnerRules.mayChooseOwner(ownerAdminOnly: restricted, didLoad: true, role: "city_manager", dataScope: nil))
        XCTAssertTrue(LeadOwnerRules.isLocked(ownerAdminOnly: restricted, role: "city_manager", dataScope: nil))
        let adminValue = LeadOwnerRules.effectiveAdminOnly(loaded: nil, cached: true, isAdmin: true)
        XCTAssertTrue(LeadOwnerRules.mayChooseOwner(ownerAdminOnly: adminValue, didLoad: true, role: "admin", dataScope: nil))
        XCTAssertFalse(LeadOwnerRules.isLocked(ownerAdminOnly: adminValue, role: "admin", dataScope: nil))
    }

    // MARK: - the remembered value

    func testTheKeyNamesTheUserAndTheClient() {
        XCTAssertEqual(OwnerAssignmentCache.key(userId: "u1", clientId: "c1"), "lead_owner_admin_only.u1.c1")
        XCTAssertEqual(OwnerAssignmentCache.key(userId: " u1 ", clientId: " c1 "), "lead_owner_admin_only.u1.c1")
        // A user with no client of their own and none picked still gets a key.
        XCTAssertEqual(OwnerAssignmentCache.key(userId: "u1", clientId: nil), "lead_owner_admin_only.u1.-")
        XCTAssertEqual(OwnerAssignmentCache.key(userId: "u1", clientId: "  "), "lead_owner_admin_only.u1.-")
        // Nobody signed in: nothing to key it by, so nothing is read or written.
        XCTAssertNil(OwnerAssignmentCache.key(userId: nil, clientId: "c1"))
        XCTAssertNil(OwnerAssignmentCache.key(userId: "  ", clientId: "c1"))
        XCTAssertTrue(OwnerAssignmentCache.key(userId: "u1", clientId: "c1")!.hasPrefix(OwnerAssignmentCache.keyPrefix))
    }

    func testAFalseValueIsRememberedAsFalseNotAsMissing() {
        withSuite { d in
            let k = OwnerAssignmentCache.key(userId: "u1", clientId: "c1")
            XCTAssertNil(OwnerAssignmentCache.read(key: k, in: d))
            OwnerAssignmentCache.write(false, key: k, in: d)
            XCTAssertEqual(OwnerAssignmentCache.read(key: k, in: d), false)
            OwnerAssignmentCache.write(true, key: k, in: d)
            XCTAssertEqual(OwnerAssignmentCache.read(key: k, in: d), true)
        }
    }

    func testOnePersonsValueIsNeverAnotherOnesOrAnotherClients() {
        withSuite { d in
            OwnerAssignmentCache.write(true, key: OwnerAssignmentCache.key(userId: "u1", clientId: "c1"), in: d)
            XCTAssertNil(OwnerAssignmentCache.read(key: OwnerAssignmentCache.key(userId: "u2", clientId: "c1"), in: d))
            XCTAssertNil(OwnerAssignmentCache.read(key: OwnerAssignmentCache.key(userId: "u1", clientId: "c2"), in: d))
            // No key (nobody signed in): nothing is written and nothing is found.
            OwnerAssignmentCache.write(true, key: nil, in: d)
            XCTAssertNil(OwnerAssignmentCache.read(key: nil, in: d))
        }
    }

    // MARK: - the settings payload

    /// GET /crm/settings for a client that configures everything the lead form and the apps read from `config`.
    private let agrisynxSettings = #"""
    {"success":true,"data":{"id":"s1","org_id":"o1","client_id":"c1","business_type":"both","config":{
      "lead_form":{"segment_labels":{"b2b":"Dealer","b2c":"Farmers"},"address_on_b2b":true,"schedule_visit":{"segments":["b2b"]},"owner_assignment":"admin_only"},
      "lead_statuses":[{"value":"new","label":"New","color":"#3B82F6","position":0,"is_won":false,"is_lost":false},{"value":"visit_planned","position":1}],
      "field_overrides":{"lead.city":{"hidden":true},"lead.first_name":{"label":"Name","required":true},"lead.data_consent@b2c":{"hidden":true}},
      "targets":{"types":[{"key":"sales"},{"key":"collection","label":"Recovery target"}]},
      "consent":{"lead_pii":{"required":false}},
      "score_boost_signals":[],
      "unknown_future_key":{"nested":[1,2.5,null,true,"x",{"a":[]}],"flag":false},
      "a_number":3,"a_null":null,"a_string":"x"
    },"created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-09T00:00:00Z"}}
    """#

    private func reply(_ json: String) throws -> CRMService.CRMSettingsRaw? {
        try JSONDecoder().decode(APIEnvelope<CRMService.CRMSettingsRaw>.self, from: Data(json.utf8)).data
    }

    func testTheFullSettingsPayloadDecodesAndCarriesTheFlag() throws {
        let raw = try XCTUnwrap(try reply(agrisynxSettings))
        XCTAssertEqual(raw.business_type, "both")
        guard case let .object(cfg)? = raw.config else { return XCTFail("config should be an object") }
        let form = LeadFormConfig.parse(cfg)
        XCTAssertTrue(form.ownerAdminOnly)
        XCTAssertEqual(form.segmentName(isB2C: false), "Dealer")
        XCTAssertTrue(form.showsAddress(isB2C: false))
        XCTAssertTrue(form.offersScheduleVisit(isB2C: false))
        XCTAssertFalse(form.offersScheduleVisit(isB2C: true))
    }

    func testAnUnknownOrOddlyTypedKeyNextToTheLeadFormCannotBreakTheDecode() throws {
        // Every key of `config` goes through AnyJSON, which never throws: numbers, nulls, arrays and nested objects
        // in keys the app has never heard of leave the lead_form (and the rest) readable.
        let json = #"{"success":true,"data":{"business_type":"b2c","config":{"lead_form":{"owner_assignment":"admin_only"},"x":[1,{"y":null}],"z":1.5e3,"w":true,"v":null,"u":{}}}}"#
        let raw = try XCTUnwrap(try reply(json))
        guard case let .object(cfg)? = raw.config else { return XCTFail("config should be an object") }
        XCTAssertTrue(LeadFormConfig.parse(cfg).ownerAdminOnly)
    }

    func testTheEnvelopeReadAsTheSettingsItselfIsEmptyNotAnError() throws {
        // What `CRMService.perform` falls back to when the envelope read fails: the whole reply decoded as the
        // settings. It does not throw — it comes back with nothing in it. That is why a reply without a `config`
        // object has to count as a FAILED load, not as "this client has no flag".
        let fallback = try JSONDecoder().decode(CRMService.CRMSettingsRaw.self, from: Data(agrisynxSettings.utf8))
        XCTAssertNil(fallback.business_type)
        XCTAssertNil(fallback.config)
    }

    // MARK: - through the model (the signed-in user comes from the stored session)

    private let userKey = "current_user"

    /// Runs `body` with the stored session put back exactly as it was afterwards (the session is a global).
    private func withStoredSession(_ body: () async throws -> Void) async rethrows {
        let saved = UserDefaults.standard.data(forKey: userKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: userKey) }
            else { UserDefaults.standard.removeObject(forKey: userKey) }
        }
        try await body()
    }

    /// Runs `body` with a UserDefaults of its own (never `.standard`), removed afterwards.
    private func withSuite(_ body: (UserDefaults) -> Void) {
        let name = "OwnerAssignmentFailClosedTests." + UUID().uuidString
        guard let d = UserDefaults(suiteName: name) else { return XCTFail("could not make a test UserDefaults") }
        defer { d.removePersistentDomain(forName: name) }
        body(d)
    }

    private func signIn(role: String, dataScope: String? = nil, id: String = "u1", clientId: String? = "c1") throws {
        var extra = ""
        if let dataScope { extra += #","org_role_data_scope":"\#(dataScope)""# }
        if let clientId { extra += #","client_id":"\#(clientId)""# }
        let json = #"{"id":"\#(id)","name":"Hariom","role":"\#(role)"\#(extra)}"#
        Session.currentUser = try JSONDecoder().decode(User.self, from: Data(json.utf8))
    }

    private var u1c1: String? { OwnerAssignmentCache.key(userId: "u1", clientId: "c1") }

    func testASuccessfulLoadWithTheFlagHidesTheOwnerControlsFromACityManagerAndRemembersIt() async throws {
        try await withStoredSession {
            try signIn(role: "city_manager")
            let r = try reply(agrisynxSettings)
            let name = "OwnerAssignmentFailClosedTests." + UUID().uuidString
            let d = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { d.removePersistentDomain(forName: name) }

            let m = LeadFieldOverridesModel()
            await m.load(using: { r }, defaults: d)

            XCTAssertTrue(m.didLoad)
            XCTAssertTrue(m.leadForm.ownerAdminOnly)
            XCTAssertFalse(m.mayChooseLeadOwner)
            XCTAssertTrue(m.leadOwnerLocked)
            XCTAssertEqual(OwnerAssignmentCache.read(key: u1c1, in: d), true)
            // The rest of the settings still arrive as they did.
            XCTAssertEqual(m.leadForm.segmentName(isB2C: false), "Dealer")
            XCTAssertEqual(m.businessType, "both")
            XCTAssertTrue(m.isHidden("city", isB2C: true))
            XCTAssertEqual(m.statusOptions(default: ["new"]).map { $0.value }, ["new", "visit_planned"])
        }
    }

    func testASuccessfulLoadWithoutTheFlagLeavesThePickerAsBeforeEvenAfterATrueWasRemembered() async throws {
        try await withStoredSession {
            try signIn(role: "city_manager")
            let name = "OwnerAssignmentFailClosedTests." + UUID().uuidString
            let d = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { d.removePersistentDomain(forName: name) }
            OwnerAssignmentCache.write(true, key: u1c1, in: d)

            for json in [#"{"success":true,"data":{"business_type":"both","config":{"lead_form":{"segment_labels":{"b2b":"Dealer"}}}}}"#,
                         #"{"success":true,"data":{"business_type":"both","config":{}}}"#] {
                let m = LeadFieldOverridesModel()
                let r = try reply(json)
                await m.load(using: { r }, defaults: d)
                XCTAssertTrue(m.didLoad)
                XCTAssertFalse(m.leadForm.ownerAdminOnly)
                XCTAssertTrue(m.mayChooseLeadOwner)
                XCTAssertFalse(m.leadOwnerLocked)
                XCTAssertEqual(OwnerAssignmentCache.read(key: u1c1, in: d), false)   // the new truth replaces the old
                OwnerAssignmentCache.write(true, key: u1c1, in: d)
            }
        }
    }

    func testAFailedLoadKeepsARememberedTrueAndARememberedFalse() async throws {
        try await withStoredSession {
            try signIn(role: "city_manager")
            let name = "OwnerAssignmentFailClosedTests." + UUID().uuidString
            let d = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { d.removePersistentDomain(forName: name) }

            OwnerAssignmentCache.write(true, key: u1c1, in: d)
            let restricted = LeadFieldOverridesModel()
            await restricted.load(using: { nil }, defaults: d)
            XCTAssertTrue(restricted.didLoad)
            XCTAssertFalse(restricted.mayChooseLeadOwner)
            XCTAssertTrue(restricted.leadOwnerLocked)
            XCTAssertEqual(OwnerAssignmentCache.read(key: u1c1, in: d), true)   // a failure never rewrites it

            OwnerAssignmentCache.write(false, key: u1c1, in: d)
            let open = LeadFieldOverridesModel()
            await open.load(using: { nil }, defaults: d)
            XCTAssertTrue(open.didLoad)
            XCTAssertTrue(open.mayChooseLeadOwner)
            XCTAssertFalse(open.leadOwnerLocked)
            XCTAssertEqual(OwnerAssignmentCache.read(key: u1c1, in: d), false)
        }
    }

    func testAFailedLoadWithNothingRememberedRestrictsANonAdminAndNotAnAdmin() async throws {
        try await withStoredSession {
            let name = "OwnerAssignmentFailClosedTests." + UUID().uuidString
            let d = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { d.removePersistentDomain(forName: name) }

            try signIn(role: "city_manager")
            let rep = LeadFieldOverridesModel()
            await rep.load(using: { nil }, defaults: d)
            XCTAssertTrue(rep.didLoad)
            XCTAssertFalse(rep.mayChooseLeadOwner)
            XCTAssertTrue(rep.leadOwnerLocked)
            XCTAssertNil(OwnerAssignmentCache.read(key: u1c1, in: d))            // nothing was learnt, nothing is stored

            try signIn(role: "admin", id: "u2")
            let admin = LeadFieldOverridesModel()
            await admin.load(using: { nil }, defaults: d)
            XCTAssertTrue(admin.didLoad)
            XCTAssertTrue(admin.mayChooseLeadOwner)
            XCTAssertFalse(admin.leadOwnerLocked)

            // An org role limited to own records is not an admin, whatever the system role says.
            try signIn(role: "admin", dataScope: "own", id: "u3")
            let limited = LeadFieldOverridesModel()
            await limited.load(using: { nil }, defaults: d)
            XCTAssertFalse(limited.mayChooseLeadOwner)
            XCTAssertTrue(limited.leadOwnerLocked)
        }
    }

    func testAReplyWithoutAConfigObjectIsAFailedLoadToo() async throws {
        try await withStoredSession {
            try signIn(role: "city_manager")
            let name = "OwnerAssignmentFailClosedTests." + UUID().uuidString
            let d = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { d.removePersistentDomain(forName: name) }

            // Nothing but a business type — what the envelope read falls back to when it goes wrong.
            for json in [#"{"success":true,"data":{"business_type":"b2c"}}"#,
                         #"{"success":true,"data":{"business_type":"b2c","config":null}}"#,
                         #"{"success":true,"data":{"business_type":"b2c","config":"oops"}}"#] {
                let r = try reply(json)
                let m = LeadFieldOverridesModel()
                await m.load(using: { r }, defaults: d)
                XCTAssertTrue(m.didLoad, json)
                XCTAssertFalse(m.mayChooseLeadOwner, json)
                XCTAssertTrue(m.leadOwnerLocked, json)
                XCTAssertEqual(m.businessType, "b2c", json)          // what did arrive is still used
                XCTAssertNil(OwnerAssignmentCache.read(key: u1c1, in: d), json)
            }
        }
    }

    func testAnotherPersonsRememberedValueNeverStandsInForYours() async throws {
        try await withStoredSession {
            let name = "OwnerAssignmentFailClosedTests." + UUID().uuidString
            let d = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { d.removePersistentDomain(forName: name) }
            // u1 last saw an unrestricted client; u2, who has never loaded, then fails to load.
            OwnerAssignmentCache.write(false, key: u1c1, in: d)
            try signIn(role: "city_manager", id: "u2")
            let m = LeadFieldOverridesModel()
            await m.load(using: { nil }, defaults: d)
            XCTAssertFalse(m.mayChooseLeadOwner)
            XCTAssertTrue(m.leadOwnerLocked)
        }
    }

    func testAReloadStartsFromScratchAndWaitsForTheNewAnswer() async throws {
        try await withStoredSession {
            let name = "OwnerAssignmentFailClosedTests." + UUID().uuidString
            let d = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { d.removePersistentDomain(forName: name) }

            // A first load for a non-admin: restricted client with its own lead-type names.
            try signIn(role: "city_manager")
            let m = LeadFieldOverridesModel()
            let r = try reply(agrisynxSettings)
            await m.load(using: { r }, defaults: d)
            XCTAssertTrue(m.leadForm.ownerAdminOnly)
            XCTAssertTrue(m.leadForm.hasCustomName(isB2C: false))

            // The same object is loaded again, now for an admin who has never loaded and whose request fails:
            // nothing of the earlier answer may linger, and while the request is in flight nothing is "loaded".
            try signIn(role: "admin", id: "u2")
            var loadedWhileInFlight: Bool? = nil
            var restrictedWhileInFlight: Bool? = nil
            await m.load(using: {
                loadedWhileInFlight = m.didLoad
                restrictedWhileInFlight = m.leadForm.ownerAdminOnly
                return nil
            }, defaults: d)
            XCTAssertEqual(loadedWhileInFlight, false)
            XCTAssertEqual(restrictedWhileInFlight, false)
            XCTAssertTrue(m.didLoad)
            XCTAssertFalse(m.leadForm.ownerAdminOnly)
            XCTAssertFalse(m.leadForm.hasCustomName(isB2C: false))
        }
    }
}
