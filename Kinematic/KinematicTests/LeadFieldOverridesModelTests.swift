//
//  LeadFieldOverridesModelTests.swift
//  KinematicTests
//
//  Exercises the built-in field-override merge/lookup logic that gates every
//  lead/contact/deal/account form field. Uses the `ingest(rawOverrides:)`
//  seam to seed state without hitting `/api/v1/crm/settings`.
//

import XCTest
import SwiftUI
@testable import Kinematic

@MainActor
final class LeadFieldOverridesModelTests: XCTestCase {

    private typealias FO = LeadFieldOverridesModel.FieldOverride

    /// A representative override map covering universal keys, scoped keys,
    /// per-property fallback and other-entity keys.
    private func seededModel() -> LeadFieldOverridesModel {
        let raw: [String: FO] = [
            // Universal hidden — applies to both B2C and B2B.
            "lead.city": FO(label: nil, required: nil, hidden: true),
            // Universal label only; a scoped variant hides it on B2C.
            "lead.gender": FO(label: "Sex", required: nil, hidden: nil),
            "lead.gender@b2c": FO(label: nil, required: nil, hidden: true),
            // Scoped divergence: shown on B2B, hidden on B2C.
            "lead.company@b2b": FO(label: nil, required: nil, hidden: false),
            "lead.company@b2c": FO(label: nil, required: nil, hidden: true),
            // Universal label + required.
            "lead.first_name": FO(label: "Given Name", required: true, hidden: nil),
            // Explicitly un-hidden on B2C (persisted hidden:false).
            "lead.email@b2c": FO(label: nil, required: nil, hidden: false),
            // Other entities — live only in the flat `overrides` map.
            "contact.title": FO(label: nil, required: nil, hidden: true),
            "deal.amount": FO(label: "Value", required: nil, hidden: nil),
        ]
        let model = LeadFieldOverridesModel()
        model.ingest(rawOverrides: raw, businessType: "both")
        return model
    }

    func testIngestFlipsDidLoad() {
        let model = LeadFieldOverridesModel()
        XCTAssertFalse(model.didLoad)
        model.ingest(rawOverrides: [:])
        XCTAssertTrue(model.didLoad)
    }

    func testUniversalHiddenAppliesToBothScopes() {
        let m = seededModel()
        XCTAssertTrue(m.isHidden("city", isB2C: true))
        XCTAssertTrue(m.isHidden("city", isB2C: false))
    }

    func testPerPropertyFallbackKeepsUniversalLabelWhileScopedHides() {
        let m = seededModel()
        // On B2C the scoped entry hides it, but its label is nil so the
        // universal "Sex" label still wins (scoped-per-property merge).
        XCTAssertTrue(m.isHidden("gender", isB2C: true))
        XCTAssertEqual(m.labelFor("gender", defaultLabel: "Gender", isB2C: true), "Sex")
        // On B2B there is no scoped entry: label from universal, not hidden.
        XCTAssertFalse(m.isHidden("gender", isB2C: false))
        XCTAssertEqual(m.labelFor("gender", defaultLabel: "Gender", isB2C: false), "Sex")
    }

    func testScopedB2BvsB2CDiverge() {
        let m = seededModel()
        XCTAssertTrue(m.isHidden("company", isB2C: true))
        XCTAssertFalse(m.isHidden("company", isB2C: false))
    }

    func testLabelAndRequiredFallThroughUniversal() {
        let m = seededModel()
        XCTAssertEqual(m.labelFor("first_name", defaultLabel: "First Name", isB2C: true), "Given Name")
        XCTAssertTrue(m.requiredFor("first_name", defaultRequired: false, isB2C: true))
        XCTAssertTrue(m.requiredFor("first_name", defaultRequired: false, isB2C: false))
    }

    func testAbsentKeyDropsToDefaults() {
        let m = seededModel()
        XCTAssertFalse(m.isHidden("last_name", isB2C: true))
        XCTAssertEqual(m.labelFor("last_name", defaultLabel: "Last Name", isB2C: true), "Last Name")
        XCTAssertFalse(m.requiredFor("last_name", defaultRequired: false, isB2C: true))
        XCTAssertTrue(m.requiredFor("last_name", defaultRequired: true, isB2C: true))
    }

    func testPrefixAndSuffixAreStrippedInLookup() {
        // Callers index by bare field name ("first_name"), never the raw
        // "lead.first_name@b2c" storage key.
        let m = seededModel()
        XCTAssertEqual(m.labelFor("first_name", defaultLabel: "x", isB2C: true), "Given Name")
        // A raw key must NOT resolve.
        XCTAssertEqual(m.labelFor("lead.first_name", defaultLabel: "x", isB2C: true), "x")
    }

    func testExplicitlyShownOnB2COnlyForPersistedHiddenFalse() {
        let m = seededModel()
        // email is persisted hidden:false on B2C.
        XCTAssertTrue(m.explicitlyShownOnB2C("email"))
        // company is hidden:true on B2C — not "explicitly shown".
        XCTAssertFalse(m.explicitlyShownOnB2C("company"))
        // gender has no B2C hidden:false (it is hidden:true there).
        XCTAssertFalse(m.explicitlyShownOnB2C("gender"))
        // first_name has hidden == nil, not an explicit false.
        XCTAssertFalse(m.explicitlyShownOnB2C("first_name"))
        // Absent key.
        XCTAssertFalse(m.explicitlyShownOnB2C("nope"))
    }

    func testGenericEntityScopedLookup() {
        let m = seededModel()
        // contact.title is hidden; passing a scope still merges universal.
        XCTAssertTrue(m.isHidden(entity: "contact", "title", isB2C: true))
        XCTAssertTrue(m.isHidden(entity: "contact", "title", isB2C: false))
    }

    func testGenericEntityUnscopedLookup() {
        let m = seededModel()
        // deal.amount: no scope, universal label only.
        XCTAssertFalse(m.isHidden(entity: "deal", "amount"))
        XCTAssertEqual(m.labelFor(entity: "deal", "amount", "Amount"), "Value")
        XCTAssertTrue(m.requiredFor(entity: "deal", "amount", true))
        // Absent entity key falls back to default.
        XCTAssertEqual(m.labelFor(entity: "deal", "stage", "Stage"), "Stage")
    }

    func testBusinessTypeCaptured() {
        let m = seededModel()
        XCTAssertEqual(m.businessType, "both")
    }

    // MARK: - data_consent (the DPDP "Data Collection & Consent" block)

    func testNoOverrideMeansTheConsentBlockStaysVisible() {
        // Today's behaviour: absent = shown, so Tata, ByteBack, EFocus and the rest are unchanged.
        let m = seededModel()
        XCTAssertFalse(m.isHidden("data_consent", isB2C: true))
        XCTAssertFalse(m.isHidden("data_consent", isB2C: false))
        XCTAssertEqual(m.labelFor("data_consent", defaultLabel: "Data Collection & Consent", isB2C: false), "Data Collection & Consent")
    }

    func testTheConsentBlockCanBeHiddenForBothLeadTypesOrOne() {
        let both = LeadFieldOverridesModel()
        both.ingest(rawOverrides: ["lead.data_consent": FO(label: nil, required: nil, hidden: true)])
        XCTAssertTrue(both.isHidden("data_consent", isB2C: true))
        XCTAssertTrue(both.isHidden("data_consent", isB2C: false))

        let dealersOnly = LeadFieldOverridesModel()
        dealersOnly.ingest(rawOverrides: ["lead.data_consent@b2b": FO(label: nil, required: nil, hidden: true)])
        XCTAssertTrue(dealersOnly.isHidden("data_consent", isB2C: false))
        XCTAssertFalse(dealersOnly.isHidden("data_consent", isB2C: true))
    }

    func testTheConsentBlockCanBeRelabelled() {
        let m = LeadFieldOverridesModel()
        m.ingest(rawOverrides: ["lead.data_consent@b2c": FO(label: "Farmer consent", required: nil, hidden: nil)])
        XCTAssertEqual(m.labelFor("data_consent", defaultLabel: "Data Collection & Consent", isB2C: true), "Farmer consent")
        XCTAssertEqual(m.labelFor("data_consent", defaultLabel: "Data Collection & Consent", isB2C: false), "Data Collection & Consent")
    }

    func testTheOverridesAreNotReadyUntilTheyHaveLoaded() {
        // The forms wait for this before showing an admin-gated row; before it, nothing reads as hidden.
        let m = LeadFieldOverridesModel()
        XCTAssertFalse(m.didLoad)
        XCTAssertFalse(m.isHidden("data_consent", isB2C: true))
        m.ingest(rawOverrides: ["lead.data_consent": FO(label: nil, required: nil, hidden: true)])
        XCTAssertTrue(m.didLoad)
        XCTAssertTrue(m.isHidden("data_consent", isB2C: true))
    }

    // MARK: - Custom lead statuses (config.lead_statuses)
    //
    // The status / pipeline-stage pickers (create, edit, detail status menu,
    // list filter, marketing visit, telecaller log) all source their options
    // from `statusOptions(default:)`, which returns the tenant's custom set
    // parsed from `config.lead_statuses` when present and falls back to the
    // caller's hardcoded array otherwise. These exercise the parse + sort +
    // fallback + colour/kind mapping the pickers depend on, through the real
    // `load()` decode path (the `ingest` seam does not seed statuses).

    /// Decode a `GET /crm/settings` envelope into the raw settings, as
    /// `CRMService.getCRMSettings()` would after `perform`.
    private func settings(_ json: String) throws -> CRMService.CRMSettingsRaw? {
        try JSONDecoder().decode(APIEnvelope<CRMService.CRMSettingsRaw>.self, from: Data(json.utf8)).data
    }

    /// Run the real `load()` against a canned settings reply, using a
    /// throwaway UserDefaults so no owner-assignment cache leaks between tests.
    private func loadedModel(_ json: String) async throws -> LeadFieldOverridesModel {
        let raw = try settings(json)
        let suite = "LeadFieldOverridesModelTests.status." + UUID().uuidString
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let m = LeadFieldOverridesModel()
        await m.load(using: { raw }, defaults: d)
        return m
    }

    /// A tenant's custom set, deliberately out of position order, with one
    /// invalid slug, one label-less entry (prettify fallback), a colour, and
    /// won/lost flags.
    private let customStatusesSettings = #"""
    {"success":true,"data":{"business_type":"both","config":{"lead_statuses":[
      {"value":"qualified","label":"Qualified","color":"#10B981","position":2},
      {"value":"cold_call","position":0},
      {"value":"Invalid Slug","position":1},
      {"value":"closed_won","label":"Won","color":"#3B82F6","position":4,"is_won":true},
      {"value":"dropped","label":"Dropped","position":3,"is_lost":true}
    ]}}}
    """#

    func testCustomStatusesParseSortedByPositionAndSkipInvalidSlugs() async throws {
        let m = try await loadedModel(customStatusesSettings)
        // "Invalid Slug" (space + capitals) is dropped; the rest sort by position.
        XCTAssertEqual(m.leadStatuses.map { $0.value }, ["cold_call", "qualified", "dropped", "closed_won"])
    }

    func testCustomStatusLabelFallsBackToPrettifiedValue() async throws {
        let m = try await loadedModel(customStatusesSettings)
        let byValue = Dictionary(uniqueKeysWithValues: m.leadStatuses.map { ($0.value, $0) })
        // No `label` supplied -> prettified slug.
        XCTAssertEqual(byValue["cold_call"]?.label, "Cold Call")
        // Supplied label is kept verbatim.
        XCTAssertEqual(byValue["qualified"]?.label, "Qualified")
    }

    func testCustomStatusWonLostAndColourAreMapped() async throws {
        let m = try await loadedModel(customStatusesSettings)
        let byValue = Dictionary(uniqueKeysWithValues: m.leadStatuses.map { ($0.value, $0) })
        XCTAssertEqual(byValue["closed_won"]?.isWon, true)
        XCTAssertEqual(byValue["closed_won"]?.isLost, false)
        XCTAssertEqual(byValue["dropped"]?.isLost, true)
        XCTAssertEqual(byValue["dropped"]?.isWon, false)
        XCTAssertEqual(byValue["qualified"]?.color, "#10B981")
        // Absent colour stays nil so the picker uses its own fallback palette.
        XCTAssertNil(byValue["cold_call"]?.color)
    }

    func testCustomStatusesFeedStatusOptionsAndIgnoreTheCallerDefaults() async throws {
        let m = try await loadedModel(customStatusesSettings)
        // The pickers pass their hardcoded list as `default:`; a configured
        // tenant must see the custom set, not the fallback.
        let opts = m.statusOptions(default: ["new", "working", "converted", "lost"])
        XCTAssertEqual(opts.map { $0.value }, ["cold_call", "qualified", "dropped", "closed_won"])
    }

    func testEqualPositionsKeepOriginalArrayOrder() async throws {
        let m = try await loadedModel(#"""
        {"success":true,"data":{"config":{"lead_statuses":[
          {"value":"beta","position":5},{"value":"alpha","position":5}
        ]}}}
        """#)
        // Stable tiebreak: original order wins when positions tie.
        XCTAssertEqual(m.leadStatuses.map { $0.value }, ["beta", "alpha"])
    }

    func testMissingPositionDefaultsToZero() async throws {
        let m = try await loadedModel(#"""
        {"success":true,"data":{"config":{"lead_statuses":[
          {"value":"has_pos","position":3},{"value":"no_pos"}
        ]}}}
        """#)
        // `no_pos` has no position -> 0 -> sorts ahead of position 3.
        XCTAssertEqual(m.leadStatuses.map { $0.value }, ["no_pos", "has_pos"])
    }

    func testNonObjectAndValuelessEntriesAreIgnored() async throws {
        let m = try await loadedModel(#"""
        {"success":true,"data":{"config":{"lead_statuses":[
          7, null, "x", [1,2], {"label":"No value here"}, {"value":"ok"}
        ]}}}
        """#)
        // Only the well-formed entry survives; stray scalars/arrays/valueless objects are skipped.
        XCTAssertEqual(m.leadStatuses.map { $0.value }, ["ok"])
    }

    func testNoCustomSetFallsBackToTheCallerBuiltInList() async throws {
        // A tenant with no `lead_statuses` key: the picker keeps today's behaviour.
        let m = try await loadedModel(#"{"success":true,"data":{"config":{}}}"#)
        XCTAssertTrue(m.leadStatuses.isEmpty)
        let opts = m.statusOptions(default: ["new", "working", "converted", "lost", "unqualified"])
        XCTAssertEqual(opts.map { $0.value }, ["new", "working", "converted", "lost", "unqualified"])
        // Built-in kind mapping: converted -> won; lost / unqualified -> lost.
        let byValue = Dictionary(uniqueKeysWithValues: opts.map { ($0.value, $0) })
        XCTAssertEqual(byValue["new"]?.isWon, false)
        XCTAssertEqual(byValue["new"]?.isLost, false)
        XCTAssertEqual(byValue["new"]?.label, "New")        // capitalized slug
        XCTAssertEqual(byValue["converted"]?.isWon, true)
        XCTAssertEqual(byValue["lost"]?.isLost, true)
        XCTAssertEqual(byValue["unqualified"]?.isLost, true)
    }

    func testStatusOptionsFallbackOnAFreshModelNeedsNoLoad() {
        // A brand-new model (statuses empty) still yields the built-ins so a
        // picker that renders before `load()` returns is never empty.
        let m = LeadFieldOverridesModel()
        XCTAssertEqual(m.statusOptions(default: ["new", "lost"]).map { $0.value }, ["new", "lost"])
    }

    // MARK: - Per-status colour resolution

    func testColorForUsesConfiguredHexElseFallback() async throws {
        let m = try await loadedModel(customStatusesSettings)
        // Configured hex wins.
        XCTAssertEqual(m.color(for: "qualified", fallback: .black), Color(hex: "#10B981"))
        XCTAssertNotEqual(m.color(for: "qualified", fallback: .black), .black)
        // Configured option but no hex -> caller fallback.
        XCTAssertEqual(m.color(for: "cold_call", fallback: .black), .black)
        // Unknown value -> caller fallback.
        XCTAssertEqual(m.color(for: "nope", fallback: .black), .black)
    }

    func testColorForFallsBackWhenNoCustomSet() {
        let m = LeadFieldOverridesModel()
        XCTAssertEqual(m.color(for: "new", fallback: .gray), .gray)
    }

    func testHexColorInitParsesCommonFormsAndRejectsGarbage() {
        XCTAssertNotNil(Color(hex: "#FFF"))        // 3-digit
        XCTAssertNotNil(Color(hex: "#3B82F6"))     // 6-digit
        XCTAssertNotNil(Color(hex: "3B82F6"))      // no leading '#'
        XCTAssertNotNil(Color(hex: "#3B82F6FF"))   // 8-digit with alpha
        XCTAssertNil(Color(hex: "nope"))           // not hex
        XCTAssertNil(Color(hex: "#12"))            // wrong length
        XCTAssertNil(Color(hex: ""))               // empty
    }

    // MARK: - LeadStatusDisplay (label / prettify / resolvedStatus)

    func testLeadStatusDisplayPrettify() {
        XCTAssertEqual(LeadStatusDisplay.prettify("cold_call"), "Cold Call")
        XCTAssertEqual(LeadStatusDisplay.prettify("visit planned"), "Visit Planned")
        XCTAssertEqual(LeadStatusDisplay.prettify("new"), "New")
    }

    func testLeadStatusDisplayLabelUsesConfiguredLabelCaseInsensitively() {
        let opts = [LeadStatusOption(value: "cold_call", label: "Custom Cold", color: nil, isWon: false, isLost: false)]
        XCTAssertEqual(LeadStatusDisplay.label(for: "cold_call", options: opts), "Custom Cold")
        // Lookup is case-insensitive on the incoming value.
        XCTAssertEqual(LeadStatusDisplay.label(for: "COLD_CALL", options: opts), "Custom Cold")
        // Unknown value -> prettified fallback, even with options present.
        XCTAssertEqual(LeadStatusDisplay.label(for: "brand_new", options: opts), "Brand New")
        // No options at all -> prettified.
        XCTAssertEqual(LeadStatusDisplay.label(for: "new", options: []), "New")
    }

    func testLeadStatusDisplayResolvedStatus() {
        let open = LeadStatusOption(value: "cold_call", label: "Cold", color: nil, isWon: false, isLost: false)
        let won = LeadStatusOption(value: "closed_won", label: "Won", color: nil, isWon: true, isLost: false)
        let lost = LeadStatusOption(value: "dropped", label: "Lost", color: nil, isWon: false, isLost: true)

        // No custom set -> current stands unchanged.
        XCTAssertEqual(LeadStatusDisplay.resolvedStatus(current: "new", options: []), "new")
        // Custom set that already contains current -> current stands.
        XCTAssertEqual(LeadStatusDisplay.resolvedStatus(current: "closed_won", options: [open, won, lost]), "closed_won")
        // Current not in the custom set -> first OPEN (not won/lost) stage.
        XCTAssertEqual(LeadStatusDisplay.resolvedStatus(current: "new", options: [won, open, lost]), "cold_call")
        // Current not in set and no open stage -> first stage.
        XCTAssertEqual(LeadStatusDisplay.resolvedStatus(current: "new", options: [won, lost]), "closed_won")
    }
}
