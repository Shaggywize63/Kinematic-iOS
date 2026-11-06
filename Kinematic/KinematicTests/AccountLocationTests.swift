//
//  AccountLocationTests.swift
//  KinematicTests
//
//  The account create / edit forms' location block (Address, State, PIN code, Country; accounts have no City): the payloads
//  carry State (and the rest), edit preloads what is saved, and a field the admin hides is neither shown,
//  sent nor wiped.
//

import XCTest
@testable import Kinematic

@MainActor
final class AccountLocationTests: XCTestCase {

    private typealias FO = LeadFieldOverridesModel.FieldOverride

    private func account(_ extra: String = "") throws -> CRMAccount {
        let json = "{\"id\":\"a1\",\"name\":\"Acme\"\(extra)}"
        return try JSONDecoder().decode(CRMAccount.self, from: Data(json.utf8))
    }

    private func overrides(_ raw: [String: FO]) -> LeadFieldOverridesModel {
        let m = LeadFieldOverridesModel()
        m.ingest(rawOverrides: raw)
        return m
    }

    // MARK: Create

    func testNewDraftDefaultsCountryToIndia() {
        let d = AccountLocationDraft()
        XCTAssertEqual(d.country, "India")
        XCTAssertEqual(d.state, "")
    }

    func testCreateSendsStateAndEveryFilledField() {
        var d = AccountLocationDraft()
        d.addressLine1 = " 12 MG Road "
        d.addressLine2 = "Near Metro"
        d.state = "Karnataka"
        d.postalCode = "560001"
        let f = d.createFields()
        XCTAssertEqual(f["address_line1"] as? String, "12 MG Road")
        XCTAssertEqual(f["address_line2"] as? String, "Near Metro")
        XCTAssertEqual(f["state"] as? String, "Karnataka")
        XCTAssertNil(f["city"])
        XCTAssertEqual(f["postal_code"] as? String, "560001")
        XCTAssertEqual(f["country"] as? String, "India")
    }

    func testCreateOmitsBlankFields() {
        var d = AccountLocationDraft()
        d.state = "   "
        let f = d.createFields()
        XCTAssertEqual(Set(f.keys), ["country"])
    }

    func testLocationKeysHaveNoCity() {
        XCTAssertEqual(AccountLocationDraft.keys, ["address_line1", "address_line2", "state", "postal_code", "country"])
        XCTAssertFalse(AccountLocationDraft.keys.contains("city"))
    }

    // MARK: Edit

    func testEditPreloadsSavedValues() throws {
        let a = try account(",\"address_line1\":\"1 Hill St\",\"address_line2\":\"Floor 2\",\"city\":\"Pune\",\"state\":\"Maharashtra\",\"postal_code\":\"411001\",\"country\":\"India\"")
        let d = AccountLocationDraft(account: a)
        XCTAssertEqual(d.addressLine1, "1 Hill St")
        XCTAssertEqual(d.addressLine2, "Floor 2")
        XCTAssertEqual(d.state, "Maharashtra")
        XCTAssertEqual(d.postalCode, "411001")
        XCTAssertEqual(d.country, "India")
    }

    func testEditOfAccountWithNoLocationStaysBlank() throws {
        let d = AccountLocationDraft(account: try account())
        XCTAssertEqual(d.country, "")
        XCTAssertEqual(d.state, "")
        // Saving it unchanged only sends nulls, never a stamped country.
        let f = d.patchFields()
        XCTAssertTrue(f.values.allSatisfy { $0 is NSNull })
    }

    func testPatchSendsStateAndClearsBlankAsNull() throws {
        var d = AccountLocationDraft(account: try account(",\"state\":\"Kerala\",\"city\":\"Kochi\""))
        d.addressLine1 = ""
        let f = d.patchFields()
        XCTAssertEqual(f["state"] as? String, "Kerala")
        XCTAssertTrue(f["address_line1"] is NSNull)
        XCTAssertEqual(Set(f.keys), Set(AccountLocationDraft.keys))
    }

    /// Edit never sends `city` (not even null), so a city already stored on the account is left untouched.
    func testPatchNeverSendsCityEvenWhenAccountHasOne() throws {
        let d = AccountLocationDraft(account: try account(",\"city\":\"Kochi\",\"state\":\"Kerala\""))
        XCTAssertFalse(d.patchFields().keys.contains("city"))
        XCTAssertFalse(d.createFields().keys.contains("city"))
        let blank = AccountLocationDraft(account: try account())
        XCTAssertFalse(blank.patchFields().keys.contains("city"))
    }

    // MARK: Field overrides

    func testHiddenStateIsNotSentOnCreateOrEdit() {
        let m = overrides(["account.state": FO(label: nil, required: nil, hidden: true)])
        let hidden = AccountLocationDraft.hiddenKeys(m)
        XCTAssertEqual(hidden, ["state"])
        var d = AccountLocationDraft()
        d.state = "Goa"
        d.postalCode = "403001"
        XCTAssertNil(d.createFields(hidden: hidden)["state"])
        XCTAssertEqual(d.createFields(hidden: hidden)["postal_code"] as? String, "403001")
        // Hiding a field must not wipe the saved value: no null either.
        XCTAssertNil(d.patchFields(hidden: hidden)["state"])
        XCTAssertEqual(d.patchFields(hidden: hidden)["postal_code"] as? String, "403001")
    }

    func testStateVisibleWhenNotHidden() {
        let m = overrides(["account.postal_code": FO(label: nil, required: nil, hidden: true)])
        let hidden = AccountLocationDraft.hiddenKeys(m)
        XCTAssertEqual(hidden, ["postal_code"])
        var d = AccountLocationDraft()
        d.state = "Goa"
        XCTAssertEqual(d.createFields(hidden: hidden)["state"] as? String, "Goa")
    }

    func testRelabelAndRequiredAreReadFromAccountKeys() {
        let m = overrides(["account.state": FO(label: "Province", required: true, hidden: nil)])
        XCTAssertEqual(m.labelFor(entity: "account", "state", "State"), "Province")
        XCTAssertEqual(AccountLocationDraft.requiredKeys(m), ["state"])
        var d = AccountLocationDraft()
        XCTAssertTrue(d.isIncomplete(m))
        d.state = "Goa"
        XCTAssertFalse(d.isIncomplete(m))
    }

    /// An account.city override (hidden or required) is ignored: accounts have no City.
    func testCityOverridesAreIgnored() {
        let m = overrides(["account.city": FO(label: nil, required: true, hidden: true)])
        XCTAssertEqual(AccountLocationDraft.hiddenKeys(m), [])
        XCTAssertEqual(AccountLocationDraft.requiredKeys(m), [])
        XCTAssertFalse(AccountLocationDraft().isIncomplete(m))
    }

    func testRequiredButHiddenDoesNotBlockSave() {
        let m = overrides(["account.state": FO(label: nil, required: true, hidden: true)])
        XCTAssertFalse(AccountLocationDraft().isIncomplete(m))
    }

    // MARK: Detail

    func testDisplayLinesOrderAndGating() {
        var d = AccountLocationDraft()
        d.addressLine1 = "12 MG Road"
        d.state = "Karnataka"
        d.postalCode = "560001"
        XCTAssertEqual(d.displayLines(), ["12 MG Road", "Karnataka 560001", "India"])
        XCTAssertEqual(d.displayLines(hidden: ["state", "country"]), ["12 MG Road", "560001"])
        XCTAssertEqual(d.displayLines(hidden: Set(AccountLocationDraft.keys)), [])
    }

    func testDisplayLinesShowNoCityForAccountWithOne() throws {
        let a = try account(",\"city\":\"Pune\",\"state\":\"Maharashtra\",\"country\":\"India\"")
        XCTAssertEqual(AccountLocationDraft(account: a).displayLines(), ["Maharashtra", "India"])
    }

    func testDisplayLinesEmptyWhenNothingSaved() throws {
        XCTAssertEqual(AccountLocationDraft(account: try account()).displayLines(), [])
    }

    func testAccountDecodesLocationColumns() throws {
        let a = try account(",\"address_line1\":\"X\",\"postal_code\":\"1\",\"state\":\"S\"")
        XCTAssertEqual(a.addressLine1, "X")
        XCTAssertEqual(a.postalCode, "1")
        XCTAssertEqual(a.state, "S")
        XCTAssertNil(a.city)
        // `city` is still decoded (harmless) even though the forms never show or send it.
        XCTAssertEqual(try account(",\"city\":\"Pune\"").city, "Pune")
    }
}
