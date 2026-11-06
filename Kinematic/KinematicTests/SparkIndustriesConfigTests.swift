//
//  SparkIndustriesConfigTests.swift
//  KinematicTests
//
//  Spark & Ray's config-driven industries (`config.industries` from GET /crm/settings): parsing with the
//  built-in fallback, colours, the dropdown options (a removed / legacy industry stays selectable and renders
//  grey), the Sub-industry dropdown rules and the cache-backed store.
//

import XCTest
@testable import Kinematic

@MainActor
final class SparkIndustriesConfigTests: XCTestCase {

    /// The store and the facade share one process-wide list; every test that touches it puts the defaults back.
    private func resetActive() { SparkIndustries.active = .defaults }

    private func settings(_ json: String) throws -> CRMService.CRMSettingsRaw {
        try JSONDecoder().decode(CRMService.CRMSettingsRaw.self, from: Data(json.utf8))
    }

    private func config(_ json: String) throws -> IndustriesConfig {
        IndustriesConfig.parse(settings: try settings(json))
    }

    private let custom = """
    {"business_type":"b2b","config":{"industries":[
      {"name":"Steel","color":"#112233","sub_industries":["Flat","Long"]},
      {"name":"Textiles","color":"#abcdef","sub_industries":[]},
      {"name":"Plastics","color":"not-a-colour"}
    ]}}
    """

    // MARK: defaults

    func testDefaultsAreTheSevenWithTheirColoursAndNoSubIndustries() {
        let d = IndustriesConfig.defaults
        XCTAssertEqual(d.names, [
            "Manufacturing", "Automotive", "Pharma & Healthcare", "Food & Beverage",
            "Construction & Infrastructure", "Power & Energy", "Other",
        ])
        XCTAssertEqual(d.color(for: "Manufacturing"), "#2563EB")
        XCTAssertEqual(d.color(for: "Automotive"), "#DC2626")
        XCTAssertEqual(d.color(for: "Pharma & Healthcare"), "#16A34A")
        XCTAssertEqual(d.color(for: "Food & Beverage"), "#F59E0B")
        XCTAssertEqual(d.color(for: "Construction & Infrastructure"), "#7C3AED")
        XCTAssertEqual(d.color(for: "Power & Energy"), "#0891B2")
        XCTAssertEqual(d.color(for: "Other"), "#6B7280")
        XCTAssertTrue(d.industries.allSatisfy { $0.subIndustries.isEmpty })
    }

    func testMissingNullEmptyOrMalformedConfigFallsBackToTheDefaults() throws {
        XCTAssertEqual(try config(#"{"config":{}}"#), .defaults)
        XCTAssertEqual(try config(#"{"config":{"industries":null}}"#), .defaults)
        XCTAssertEqual(try config(#"{"config":{"industries":[]}}"#), .defaults)
        XCTAssertEqual(try config(#"{"config":{"industries":"Steel"}}"#), .defaults)
        XCTAssertEqual(try config(#"{"config":{"industries":[{"color":"#112233"},{"name":"  "},5]}}"#), .defaults)
        XCTAssertEqual(IndustriesConfig.parse(settings: nil), .defaults)
        XCTAssertEqual(IndustriesConfig.parse(nil), .defaults)
    }

    // MARK: parsing

    func testParsesNamesColoursAndSubIndustriesInOrder() throws {
        let c = try config(custom)
        XCTAssertEqual(c.names, ["Steel", "Textiles", "Plastics"])
        XCTAssertEqual(c.color(for: "Steel"), "#112233")
        XCTAssertEqual(c.color(for: "Textiles"), "#ABCDEF")
        XCTAssertEqual(c.subIndustries(for: "Steel"), ["Flat", "Long"])
        XCTAssertTrue(c.subIndustries(for: "Textiles").isEmpty)
    }

    func testABadColourBecomesGreyAndRepeatedNamesKeepTheFirst() throws {
        let c = try config(custom)
        XCTAssertEqual(c.color(for: "Plastics"), IndustriesConfig.fallbackColor)
        let dup = try config(#"{"config":{"industries":[{"name":"Steel","color":"#111111"},{"name":" steel ","color":"#222222"}]}}"#)
        XCTAssertEqual(dup.names, ["Steel"])
        XCTAssertEqual(dup.color(for: "Steel"), "#111111")
    }

    func testSubIndustriesAreTrimmedDedupedAndBlankFree() throws {
        let c = try config(#"{"config":{"industries":[{"name":"Steel","color":"#111111","sub_industries":[" Flat ","flat","","Long",7]}]}}"#)
        XCTAssertEqual(c.subIndustries(for: "Steel"), ["Flat", "Long"])
    }

    func testHexValidation() {
        XCTAssertTrue(IndustriesConfig.isValidHex("#A1b2C3"))
        XCTAssertFalse(IndustriesConfig.isValidHex("A1B2C3"))
        XCTAssertFalse(IndustriesConfig.isValidHex("#A1B2C"))
        XCTAssertFalse(IndustriesConfig.isValidHex("#GGGGGG"))
    }

    // MARK: lookups, colours, dropdown

    func testColourLookupIsCaseAndWhitespaceTolerantAndGreyWhenUnknown() throws {
        let c = try config(custom)
        XCTAssertEqual(c.color(for: "  steel "), "#112233")
        XCTAssertEqual(c.color(for: "Welding"), IndustriesConfig.fallbackColor)
        XCTAssertEqual(c.color(for: ""), IndustriesConfig.fallbackColor)
        XCTAssertEqual(c.color(for: nil), IndustriesConfig.fallbackColor)
    }

    func testAnIndustryRemovedFromTheListStaysSelectableOnceAndRendersGrey() throws {
        let c = try config(custom)
        let options = c.pickerOptions(including: "Manufacturing")
        XCTAssertEqual(options, ["Steel", "Textiles", "Plastics", "Manufacturing"])
        XCTAssertEqual(c.color(for: "Manufacturing"), IndustriesConfig.fallbackColor)
        XCTAssertEqual(c.pickerOptions(including: "Steel"), c.names)
        XCTAssertEqual(c.pickerOptions(including: "  "), c.names)
        XCTAssertEqual(c.pickerOptions(including: ""), c.names)
    }

    func testTheStaticFacadeReadsTheActiveList() throws {
        defer { resetActive() }
        XCTAssertEqual(SparkIndustries.color(for: "Manufacturing"), "#2563EB")
        SparkIndustries.active = try config(custom)
        XCTAssertEqual(SparkIndustries.options, ["Steel", "Textiles", "Plastics"])
        XCTAssertEqual(SparkIndustries.color(for: "Steel"), "#112233")
        XCTAssertEqual(SparkIndustries.color(for: "Manufacturing"), "#6B7280")
        XCTAssertEqual(SparkIndustries.pickerOptions(including: "Legacy"), ["Steel", "Textiles", "Plastics", "Legacy"])
        let rgb = SparkIndustries.rgb(for: "Steel")
        XCTAssertEqual(rgb.r, 0x11 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(rgb.g, 0x22 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(rgb.b, 0x33 / 255.0, accuracy: 0.0001)
    }

    // MARK: sub-industry

    func testSubIndustryIsADropdownOnlyWhenTheIndustryListsSome() throws {
        let c = try config(custom)
        XCTAssertTrue(c.usesSubIndustryDropdown(for: "Steel"))
        XCTAssertFalse(c.usesSubIndustryDropdown(for: "Textiles"))
        XCTAssertFalse(c.usesSubIndustryDropdown(for: "Unknown"))
        XCTAssertFalse(c.usesSubIndustryDropdown(for: ""))
        XCTAssertFalse(IndustriesConfig.defaults.usesSubIndustryDropdown(for: "Manufacturing"))
    }

    func testTheStoredSubIndustryStaysSelectableEvenWhenNotListed() throws {
        let c = try config(custom)
        XCTAssertEqual(c.subIndustryChoices(for: "Steel", current: ""), ["Flat", "Long"])
        XCTAssertEqual(c.subIndustryChoices(for: "Steel", current: "Flat"), ["Flat", "Long"])
        XCTAssertEqual(c.subIndustryChoices(for: "Steel", current: "Rebar"), ["Flat", "Long", "Rebar"])
        // No list = free text: no dropdown choices at all.
        XCTAssertEqual(c.subIndustryChoices(for: "Textiles", current: "Cotton"), [])
    }

    func testChangingIndustryClearsASubIndustryThatDoesNotBelong() throws {
        let c = try config(custom)
        // New industry lists sub-industries: keep a listed value, clear anything else.
        XCTAssertEqual(c.subIndustryAfterIndustryChange(current: "Flat", from: "Steel", to: "Steel"), "Flat")
        XCTAssertEqual(c.subIndustryAfterIndustryChange(current: "Cotton", from: "Textiles", to: "Steel"), "")
        // New industry lists none (free text): keep a typed value ...
        XCTAssertEqual(c.subIndustryAfterIndustryChange(current: "Cotton", from: "Textiles", to: "Plastics"), "Cotton")
        // ... unless it was a sub-industry of the industry just left.
        XCTAssertEqual(c.subIndustryAfterIndustryChange(current: "Flat", from: "Steel", to: "Textiles"), "")
        // Nothing to clear.
        XCTAssertEqual(c.subIndustryAfterIndustryChange(current: "", from: "Steel", to: "Textiles"), "")
        // First pick (no previous industry) keeps a free-text value when the new industry has no list.
        XCTAssertEqual(c.subIndustryAfterIndustryChange(current: "Cotton", from: "", to: "Textiles"), "Cotton")
    }

    // MARK: cache + store

    private func freshDefaults() -> UserDefaults {
        let suite = "SparkIndustriesConfigTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testCacheRoundTrips() throws {
        let d = freshDefaults()
        let c = try config(custom)
        let key = IndustriesCache.key(clientId: "ABC")
        XCTAssertNil(IndustriesCache.read(key: key, in: d))
        IndustriesCache.write(c, key: key, in: d)
        XCTAssertEqual(IndustriesCache.read(key: key, in: d), c)
        XCTAssertEqual(IndustriesCache.key(clientId: "ABC"), IndustriesCache.key(clientId: "abc"))
    }

    func testStoreLoadsAndAppliesTheTenantList() async throws {
        defer { resetActive() }
        let store = IndustriesStore()
        let raw = try settings(custom)
        await store.load(isSpark: true, scope: "c1", defaults: freshDefaults()) { raw }
        XCTAssertTrue(store.didLoad)
        XCTAssertEqual(store.config.names, ["Steel", "Textiles", "Plastics"])
        XCTAssertEqual(SparkIndustries.options, ["Steel", "Textiles", "Plastics"])
    }

    func testStoreKeepsTheCachedListWhenTheRequestFails() async throws {
        defer { resetActive() }
        let d = freshDefaults()
        let c = try config(custom)
        IndustriesCache.write(c, key: IndustriesCache.key(clientId: "c1"), in: d)
        let store = IndustriesStore()
        await store.load(isSpark: true, scope: "c1", defaults: d) { nil }
        XCTAssertEqual(store.config, c)
        XCTAssertEqual(SparkIndustries.options, ["Steel", "Textiles", "Plastics"])
    }

    func testStoreFallsBackToTheDefaultsWithNothingCachedAndNoReply() async {
        defer { resetActive() }
        let store = IndustriesStore()
        await store.load(isSpark: true, scope: "c2", defaults: freshDefaults()) { nil }
        XCTAssertEqual(store.config, .defaults)
        XCTAssertTrue(store.didLoad)
    }

    func testAResetOnTheServerReturnsTheDefaults() async throws {
        defer { resetActive() }
        let d = freshDefaults()
        let store = IndustriesStore()
        let raw = try settings(custom)
        await store.load(isSpark: true, scope: "c1", defaults: d) { raw }
        XCTAssertNotEqual(store.config, .defaults)
        let reset = try settings(#"{"business_type":"b2b","config":{"industries":null}}"#)
        await store.load(isSpark: true, scope: "c1", defaults: d) { reset }
        XCTAssertEqual(store.config, .defaults)
    }

    func testOtherTenantsNeverFetchAndKeepTheDefaults() async throws {
        defer { resetActive() }
        let store = IndustriesStore()
        var fetched = false
        await store.load(isSpark: false, scope: "other", defaults: freshDefaults()) {
            fetched = true
            return nil
        }
        XCTAssertFalse(fetched)
        XCTAssertEqual(store.config, .defaults)
        XCTAssertEqual(SparkIndustries.options, SparkIndustries.defaultOptions)
    }

    func testSwitchingClientDoesNotLeakTheOtherClientsList() async throws {
        defer { resetActive() }
        let d = freshDefaults()
        let store = IndustriesStore()
        let raw = try settings(custom)
        await store.load(isSpark: true, scope: "c1", defaults: d) { raw }
        await store.load(isSpark: true, scope: "c3", defaults: d) { nil }
        XCTAssertEqual(store.config, .defaults)
    }
}
