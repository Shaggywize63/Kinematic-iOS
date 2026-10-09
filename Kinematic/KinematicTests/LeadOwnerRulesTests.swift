//
//  LeadOwnerRulesTests.swift
//  KinematicTests
//
//  `lead_form.owner_assignment == "admin_only"`: a non-admin of a client that sets it sees no control that
//  chooses or changes a lead's owner and never sends one. Who is an admin (the roles the backend treats as admin
//  for this, but NOT a user whose org role limits them to their own records), that nothing changes for a client
//  without the flag, that a non-admin's controls wait for the settings to load, and how the flag reaches the
//  model from `/crm/settings`. Mirrors the web and Android implementations of the same contract.
//

import XCTest
@testable import Kinematic

@MainActor
final class LeadOwnerRulesTests: XCTestCase {

    // MARK: - parsing `config.lead_form.owner_assignment`

    private func form(_ owner: AnyJSON?) -> LeadFormConfig {
        var lf: [String: AnyJSON] = [:]
        if let owner { lf["owner_assignment"] = owner }
        return LeadFormConfig.parse(["lead_form": .object(lf)])
    }

    func testNoFlagMeansTodaysBehaviour() {
        XCTAssertFalse(LeadFormConfig().ownerAdminOnly)
        XCTAssertFalse(LeadFormConfig.parse(nil).ownerAdminOnly)
        XCTAssertFalse(LeadFormConfig.parse([:]).ownerAdminOnly)
        XCTAssertFalse(LeadFormConfig.parse(["lead_form": .string("nonsense")]).ownerAdminOnly)
        XCTAssertFalse(form(nil).ownerAdminOnly)
        // A lead_form that never mentions it is the legacy config, exactly.
        XCTAssertEqual(form(nil), LeadFormConfig())
    }

    func testAdminOnlyRestrictsAndNothingElseDoes() {
        XCTAssertTrue(form(.string("admin_only")).ownerAdminOnly)
        XCTAssertTrue(form(.string(" Admin_Only ")).ownerAdminOnly)
        // Anything else — another word, nothing, or a non-string — leaves owner assignment as it was.
        XCTAssertFalse(form(.string("anyone")).ownerAdminOnly)
        XCTAssertFalse(form(.string("")).ownerAdminOnly)
        XCTAssertFalse(form(.bool(true)).ownerAdminOnly)
        XCTAssertFalse(form(.number(1)).ownerAdminOnly)
        XCTAssertFalse(form(.null).ownerAdminOnly)
    }

    func testTheFlagSitsBesideTheOtherLeadFormSettings() throws {
        let json = #"{"lead_form":{"segment_labels":{"b2b":"Dealer","b2c":"Farmers"},"address_on_b2b":true,"owner_assignment":"admin_only"}}"#
        let cfg = try JSONDecoder().decode([String: AnyJSON].self, from: Data(json.utf8))
        let parsed = LeadFormConfig.parse(cfg)
        XCTAssertTrue(parsed.ownerAdminOnly)
        XCTAssertEqual(parsed.segmentName(isB2C: false), "Dealer")
        XCTAssertTrue(parsed.showsAddress(isB2C: false))
        // And the other settings parse the same without it.
        let without = LeadFormConfig.parse(["lead_form": .object(["address_on_b2b": .bool(true)])])
        XCTAssertFalse(without.ownerAdminOnly)
        XCTAssertTrue(without.showsAddress(isB2C: false))
    }

    // MARK: - who is an admin

    func testEveryAdminRoleIsAnAdminUnlessLimitedToOwnRecords() {
        for role in ["admin", "super_admin", "main_admin", "org_admin", "sub_admin", "client"] {
            XCTAssertTrue(LeadOwnerRules.isAdmin(role: role, dataScope: nil), role)
            XCTAssertTrue(LeadOwnerRules.isAdmin(role: role, dataScope: "all"), role)
            XCTAssertTrue(LeadOwnerRules.isAdmin(role: role, dataScope: "team"), role)
            // An org role limited to the user's own records is not an admin, whatever the system role says.
            XCTAssertFalse(LeadOwnerRules.isAdmin(role: role, dataScope: "own"), role)
            XCTAssertFalse(LeadOwnerRules.isAdmin(role: role, dataScope: " OWN "), role)
        }
    }

    func testRoleMatchingIgnoresCaseAndStrayWhitespace() {
        XCTAssertTrue(LeadOwnerRules.isAdmin(role: "Super_Admin", dataScope: nil))
        XCTAssertTrue(LeadOwnerRules.isAdmin(role: " admin ", dataScope: ""))
    }

    func testEveryoneElseIsNotAnAdmin() {
        for role in ["executive", "field_executive", "manager", "city_manager", "supervisor", "hr", "program_manager", "", "administrator"] {
            XCTAssertFalse(LeadOwnerRules.isAdmin(role: role, dataScope: nil), role)
            XCTAssertFalse(LeadOwnerRules.isAdmin(role: role, dataScope: "all"), role)
        }
        // No signed-in role is not an admin either.
        XCTAssertFalse(LeadOwnerRules.isAdmin(role: nil, dataScope: nil))
    }

    // MARK: - locked / may choose

    func testWithoutTheFlagNobodyIsLocked() {
        for role in ["admin", "executive", "", "client"] {
            XCTAssertFalse(LeadOwnerRules.isLocked(ownerAdminOnly: false, role: role, dataScope: nil), role)
            XCTAssertFalse(LeadOwnerRules.isLocked(ownerAdminOnly: false, role: role, dataScope: "own"), role)
        }
    }

    func testWithTheFlagEveryNonAdminIsLockedAndAdminsAreNot() {
        XCTAssertTrue(LeadOwnerRules.isLocked(ownerAdminOnly: true, role: "executive", dataScope: nil))
        XCTAssertTrue(LeadOwnerRules.isLocked(ownerAdminOnly: true, role: "manager", dataScope: "team"))
        XCTAssertTrue(LeadOwnerRules.isLocked(ownerAdminOnly: true, role: nil, dataScope: nil))
        XCTAssertTrue(LeadOwnerRules.isLocked(ownerAdminOnly: true, role: "admin", dataScope: "own"))
        XCTAssertFalse(LeadOwnerRules.isLocked(ownerAdminOnly: true, role: "admin", dataScope: nil))
        XCTAssertFalse(LeadOwnerRules.isLocked(ownerAdminOnly: true, role: "sub_admin", dataScope: "all"))
        XCTAssertFalse(LeadOwnerRules.isLocked(ownerAdminOnly: true, role: "client", dataScope: nil))
    }

    func testAnAdminIsOfferedTheControlsBeforeAndAfterTheSettingsLoad() {
        for (flag, loaded) in [(false, false), (false, true), (true, false), (true, true)] {
            XCTAssertTrue(LeadOwnerRules.mayChooseOwner(ownerAdminOnly: flag, didLoad: loaded, role: "admin", dataScope: nil))
        }
    }

    func testANonAdminWaitsForTheSettingsAndThenOnlyWithoutTheFlag() {
        // Not loaded: the flag is unknown, so nothing flashes up and vanishes.
        XCTAssertFalse(LeadOwnerRules.mayChooseOwner(ownerAdminOnly: false, didLoad: false, role: "executive", dataScope: nil))
        XCTAssertFalse(LeadOwnerRules.mayChooseOwner(ownerAdminOnly: true, didLoad: false, role: "executive", dataScope: nil))
        // Loaded, no flag: exactly as before.
        XCTAssertTrue(LeadOwnerRules.mayChooseOwner(ownerAdminOnly: false, didLoad: true, role: "executive", dataScope: nil))
        XCTAssertTrue(LeadOwnerRules.mayChooseOwner(ownerAdminOnly: false, didLoad: true, role: "manager", dataScope: "team"))
        // Loaded, flag set: gone.
        XCTAssertFalse(LeadOwnerRules.mayChooseOwner(ownerAdminOnly: true, didLoad: true, role: "executive", dataScope: nil))
        XCTAssertFalse(LeadOwnerRules.mayChooseOwner(ownerAdminOnly: true, didLoad: true, role: "admin", dataScope: "own"))
    }

    // MARK: - through the model (the signed-in user comes from the stored session)

    private let userKey = "current_user"

    /// Runs `body` with the stored session put back exactly as it was afterwards (the session is a global).
    private func withStoredSession(_ body: () throws -> Void) rethrows {
        let saved = UserDefaults.standard.data(forKey: userKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: userKey) }
            else { UserDefaults.standard.removeObject(forKey: userKey) }
        }
        try body()
    }

    private func signIn(role: String, dataScope: String? = nil) throws {
        let scope = dataScope.map { #","org_role_data_scope":"\#($0)""# } ?? ""
        let json = #"{"id":"u1","name":"Asha","role":"\#(role)"\#(scope)}"#
        Session.currentUser = try JSONDecoder().decode(User.self, from: Data(json.utf8))
    }

    private func loadedModel(adminOnly: Bool) -> LeadFieldOverridesModel {
        let m = LeadFieldOverridesModel()
        m.ingest(rawOverrides: [:], leadForm: LeadFormConfig(ownerAdminOnly: adminOnly))
        return m
    }

    func testAClientWithoutTheFlagIsUnchangedForEveryone() throws {
        try withStoredSession {
            let m = loadedModel(adminOnly: false)
            for (role, scope) in [("admin", nil), ("executive", nil), ("manager", "team"), ("admin", "own")] as [(String, String?)] {
                try signIn(role: role, dataScope: scope)
                XCTAssertTrue(m.mayChooseLeadOwner, role)
                XCTAssertFalse(m.leadOwnerLocked, role)
            }
        }
    }

    func testWithTheFlagOnlyAdminsKeepTheOwnerControls() throws {
        try withStoredSession {
            let m = loadedModel(adminOnly: true)
            try signIn(role: "admin")
            XCTAssertTrue(m.mayChooseLeadOwner)
            XCTAssertFalse(m.leadOwnerLocked)
            try signIn(role: "super_admin", dataScope: "all")
            XCTAssertTrue(m.mayChooseLeadOwner)
            XCTAssertFalse(m.leadOwnerLocked)
            try signIn(role: "executive")
            XCTAssertFalse(m.mayChooseLeadOwner)
            XCTAssertTrue(m.leadOwnerLocked)
            try signIn(role: "admin", dataScope: "own")
            XCTAssertFalse(m.mayChooseLeadOwner)
            XCTAssertTrue(m.leadOwnerLocked)
        }
    }

    func testBeforeTheSettingsLoadANonAdminIsNotOfferedTheControlsButAnAdminIs() throws {
        try withStoredSession {
            let m = LeadFieldOverridesModel()
            XCTAssertFalse(m.didLoad)
            try signIn(role: "executive")
            XCTAssertFalse(m.mayChooseLeadOwner)
            try signIn(role: "admin")
            XCTAssertTrue(m.mayChooseLeadOwner)
        }
    }

    func testNoSignedInUserIsNotAnAdmin() {
        withStoredSession {
            UserDefaults.standard.removeObject(forKey: userKey)
            XCTAssertFalse(loadedModel(adminOnly: true).mayChooseLeadOwner)
            XCTAssertTrue(loadedModel(adminOnly: true).leadOwnerLocked)
            XCTAssertTrue(loadedModel(adminOnly: false).mayChooseLeadOwner)
        }
    }

    func testTheFlagLeavesTheOwnerFieldOverrideAlone() throws {
        // `owner_id` is a built-in field: the admin's hide / relabel keeps working for everyone, flag or not.
        typealias FO = LeadFieldOverridesModel.FieldOverride
        try withStoredSession {
            let m = LeadFieldOverridesModel()
            m.ingest(rawOverrides: ["lead.owner_id": FO(label: "Assigned to", required: nil, hidden: true)],
                     leadForm: LeadFormConfig(ownerAdminOnly: true))
            try signIn(role: "admin")
            XCTAssertTrue(m.isHidden("owner_id", isB2C: true))
            XCTAssertTrue(m.isHidden("owner_id", isB2C: false))
            XCTAssertEqual(m.labelFor("owner_id", defaultLabel: "Owner", isB2C: true), "Assigned to")
            XCTAssertTrue(m.mayChooseLeadOwner)   // the new rule is additional: it does not un-hide anything
        }
    }
}
