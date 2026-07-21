//
//  LeadFieldOverridesModelTests.swift
//  KinematicTests
//
//  Exercises the built-in field-override merge/lookup logic that gates every
//  lead/contact/deal/account form field. Uses the `ingest(rawOverrides:)`
//  seam to seed state without hitting `/api/v1/crm/settings`.
//

import XCTest
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
}
