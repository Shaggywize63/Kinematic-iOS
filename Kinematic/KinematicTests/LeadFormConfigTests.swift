//
//  LeadFormConfigTests.swift
//  KinematicTests
//
//  The per-client lead form (Dealer / Farmers): lead-type names, the B2B address block, the optional
//  Schedule visit, the searchable / products option tokens, and what blocks "Create lead". A client
//  WITHOUT `lead_form` must behave exactly as before — most tests pin that. Mirrors the Android
//  LeadFormConfigTest.
//

import XCTest
@testable import Kinematic

@MainActor
final class LeadFormConfigTests: XCTestCase {

    // MARK: - parsing `config.lead_form`

    private func str(_ s: String) -> AnyJSON { .string(s) }

    private func agrisynx() -> [String: AnyJSON] {
        [
            "lead_form": .object([
                "segment_labels": .object(["b2b": .string("Dealer"), "b2c": .string("Farmers")]),
                "address_on_b2b": .bool(true),
                "schedule_visit": .object(["segments": .array([.string("b2b")])]),
            ]),
        ]
    }

    func testNoLeadFormMeansTheLegacyBehaviour() {
        for cfg in [LeadFormConfig.parse(nil), LeadFormConfig.parse([:]), LeadFormConfig.parse(["lead_form": .string("nonsense")])] {
            XCTAssertEqual(cfg, LeadFormConfig())
            XCTAssertEqual(cfg.segmentName(isB2C: false), "B2B")
            XCTAssertEqual(cfg.segmentName(isB2C: true), "B2C")
            XCTAssertEqual(cfg.segmentPickerLabel(isB2C: false), "B2B (Business)")
            XCTAssertEqual(cfg.segmentPickerLabel(isB2C: true), "B2C (Consumer)")
            XCTAssertFalse(cfg.showsAddress(isB2C: false))
            XCTAssertTrue(cfg.showsAddress(isB2C: true))
            XCTAssertFalse(cfg.offersScheduleVisit(isB2C: false))
            XCTAssertFalse(cfg.offersScheduleVisit(isB2C: true))
        }
    }

    func testDealerAndFarmersReplaceB2BAndB2C() {
        let cfg = LeadFormConfig.parse(agrisynx())
        XCTAssertEqual(cfg.segmentName(isB2C: false), "Dealer")
        XCTAssertEqual(cfg.segmentName(isB2C: true), "Farmers")
        XCTAssertEqual(cfg.segmentPickerLabel(isB2C: false), "Dealer")
        XCTAssertEqual(cfg.segmentPickerLabel(isB2C: true), "Farmers")
        XCTAssertTrue(cfg.hasCustomName(isB2C: false))
    }

    func testAddressOnB2BAndScheduleVisitFollowTheConfig() {
        let cfg = LeadFormConfig.parse(agrisynx())
        XCTAssertTrue(cfg.showsAddress(isB2C: false))
        XCTAssertTrue(cfg.showsAddress(isB2C: true))
        XCTAssertTrue(cfg.offersScheduleVisit(isB2C: false))
        XCTAssertFalse(cfg.offersScheduleVisit(isB2C: true))
    }

    func testAHalfConfiguredBlockOnlyChangesWhatItSets() {
        let cfg = LeadFormConfig.parse(["lead_form": .object(["segment_labels": .object(["b2c": .string("Farmers")])])])
        XCTAssertEqual(cfg.segmentName(isB2C: true), "Farmers")
        XCTAssertEqual(cfg.segmentName(isB2C: false), "B2B")
        XCTAssertFalse(cfg.hasCustomName(isB2C: false))
        XCTAssertFalse(cfg.showsAddress(isB2C: false))
    }

    func testBadValuesAreIgnoredNotTrusted() {
        let cfg = LeadFormConfig.parse(["lead_form": .object([
            "segment_labels": .object(["b2b": .string("   "), "b2c": .number(42)]),
            "address_on_b2b": .string("yes"),
            "schedule_visit": .object(["segments": .array([.string("b2b"), .string("x"), .number(7), .string("B2C")])]),
        ])])
        XCTAssertTrue(cfg.segmentLabels.isEmpty)
        XCTAssertFalse(cfg.addressOnB2b)
        // Only valid segments survive (case-insensitive).
        XCTAssertTrue(cfg.offersScheduleVisit(isB2C: false))
        XCTAssertTrue(cfg.offersScheduleVisit(isB2C: true))
    }

    func testALabelIsTrimmedAndCappedAt40Characters() {
        let long = "  " + String(repeating: "D", count: 60) + "  "
        let cfg = LeadFormConfig.parse(["lead_form": .object(["segment_labels": .object(["b2b": .string(long)])])])
        XCTAssertEqual(cfg.segmentName(isB2C: false), String(repeating: "D", count: 40))
    }

    // MARK: - custom-field option tokens

    func testReservedTokensAreNeverShownAsChoices() {
        let crop = [CustomFieldOptions.searchable, "Rice (Paddy)", "Wheat"]
        XCTAssertEqual(CustomFieldOptions.visible(crop), ["Rice (Paddy)", "Wheat"])
        XCTAssertTrue(CustomFieldOptions.isSearchable(crop))
        XCTAssertFalse(CustomFieldOptions.isProductSource(crop))

        let product = [CustomFieldOptions.sourceProducts]
        XCTAssertEqual(CustomFieldOptions.visible(product), [])
        XCTAssertTrue(CustomFieldOptions.isProductSource(product))
        // A products-sourced list is always searchable.
        XCTAssertTrue(CustomFieldOptions.isSearchable(product))
    }

    func testAPlainSelectKeepsEveryOptionAndIsNotSearchable() {
        let plain = ["Dealer Visit", "First Time Visit", "Dealer Appoint", "Order/Collection"]
        XCTAssertEqual(CustomFieldOptions.visible(plain), plain)
        XCTAssertFalse(CustomFieldOptions.isSearchable(plain))
        XCTAssertFalse(CustomFieldOptions.isSearchable(nil))
        XCTAssertEqual(CustomFieldOptions.visible(nil), [])
        // Image-field camera tokens are not reserved tokens.
        XCTAssertFalse(CustomFieldOptions.isReserved("camera_only"))
        XCTAssertTrue(CustomFieldOptions.isReserved("__x__"))
        XCTAssertFalse(CustomFieldOptions.isReserved("____"))
    }

    func testProductChoicesAreTheActiveNamesOnceSorted() {
        let names = CustomFieldOptions.productNames([
            (name: "Neem Oil", isActive: true), (name: "NPK 19-19-19", isActive: true), (name: "Retired", isActive: false),
            (name: "  Neem Oil ", isActive: true), (name: "", isActive: true),
        ])
        XCTAssertEqual(names, ["NPK 19-19-19", "Neem Oil"])
    }

    // MARK: - schedule visit

    func testTheVisitTimeIsSentAsISOUTC() {
        XCTAssertEqual(ScheduleVisitRules.iso(Date(timeIntervalSince1970: 1_760_000_000)), "2025-10-09T08:53:20Z")
    }

    func testAVisitInThePastIsNotUsableButAMinuteOfGraceIsAllowed() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertTrue(ScheduleVisitRules.isUsable(now.addingTimeInterval(3600), now: now))
        XCTAssertTrue(ScheduleVisitRules.isUsable(now.addingTimeInterval(-30), now: now))
        XCTAssertFalse(ScheduleVisitRules.isUsable(now.addingTimeInterval(-3600), now: now))
    }

    func testTheVisitSubjectIsTheDescriptionAndWho() {
        XCTAssertEqual(ScheduleVisitRules.subject(description: "Dealer Visit", who: "Sharma Agro"), "Dealer Visit — Sharma Agro")
        XCTAssertEqual(ScheduleVisitRules.subject(description: " Order/Collection ", who: nil), "Order/Collection")
        XCTAssertNil(ScheduleVisitRules.subject(description: nil, who: "Sharma Agro"))
        XCTAssertNil(ScheduleVisitRules.subject(description: "  ", who: "Sharma Agro"))
    }

    // MARK: - what blocks Create lead

    private typealias FO = LeadFieldOverridesModel.FieldOverride

    private func model(_ form: LeadFormConfig, _ raw: [String: FO] = [:]) -> LeadFieldOverridesModel {
        let m = LeadFieldOverridesModel()
        m.ingest(rawOverrides: raw, businessType: "both", leadForm: form)
        return m
    }

    /// The overrides the Agrisynx seeder writes.
    private func agri() -> LeadFieldOverridesModel {
        model(LeadFormConfig.parse(agrisynx()), [
            "lead.first_name@b2b": FO(label: "Dealer Name", required: true, hidden: nil),
            "lead.last_name@b2b": FO(label: nil, required: false, hidden: true),
            "lead.company@b2b": FO(label: "Shop Name", required: true, hidden: nil),
            "lead.phone@b2b": FO(label: "Mobile Number", required: true, hidden: nil),
            "lead.address_line1@b2b": FO(label: "Location", required: true, hidden: nil),
            "lead.first_name@b2c": FO(label: "Farmer Name", required: true, hidden: nil),
            "lead.last_name@b2c": FO(label: nil, required: false, hidden: true),
            "lead.phone@b2c": FO(label: "Mobile Number", required: true, hidden: nil),
            "lead.address_line1@b2c": FO(label: "Location", required: true, hidden: nil),
        ])
    }

    private func problem(
        _ o: LeadFieldOverridesModel, isB2C: Bool = false, first: String = "Ramesh", last: String = "",
        phone: String = "9876543210", company: String = "Sharma Agro", address: String = "Market Road",
        visit: Date? = nil, now: Date = Date(timeIntervalSince1970: 1_000)
    ) -> String? {
        LeadCreateRules.firstProblem(overrides: o, isB2C: isB2C, firstName: first, lastName: last, phone: phone,
                                     company: company, addressLine1: address, visitAt: visit, now: now)
    }

    func testAHiddenLastNameNoLongerBlocksCreate() {
        XCTAssertNil(problem(agri()))
        XCTAssertNil(problem(agri(), isB2C: true, company: ""))
    }

    func testAVisibleRequiredLastNameStillBlocksAsBefore() {
        let legacy = model(LeadFormConfig())
        XCTAssertEqual(problem(legacy, last: ""), "Last name is required.")
        XCTAssertNil(problem(legacy, last: "Sharma"))
        let optional = model(LeadFormConfig(), ["lead.last_name": FO(label: nil, required: false, hidden: nil)])
        XCTAssertNil(problem(optional, last: ""))
    }

    func testMobileMustBeExactly10Digits() {
        XCTAssertEqual(problem(agri(), phone: "98765"), "Mobile Number must be a 10-digit number.")
        XCTAssertNil(problem(agri(), phone: "9876543210"))
        XCTAssertEqual(problem(agri(), phone: ""), "Mobile Number is required.")
        // Not required and left blank: fine. Typed but short: still refused.
        let relaxed = model(LeadFormConfig())
        XCTAssertNil(problem(relaxed, last: "S", phone: ""))
        XCTAssertEqual(problem(relaxed, last: "S", phone: "12345"), "Primary mobile must be a 10-digit number.")
    }

    func testShopNameAndLocationAreRequiredForADealerUnderTheirOwnNames() {
        XCTAssertEqual(problem(agri(), company: " "), "Shop Name is required for Dealer leads.")
        XCTAssertEqual(problem(agri(), address: ""), "Location is required — search for it or type it in.")
        XCTAssertEqual(problem(agri(), first: ""), "Dealer Name is required.")
        // A farmer has no shop; location is still required.
        XCTAssertEqual(problem(agri(), isB2C: true, company: "", address: ""), "Location is required — search for it or type it in.")
    }

    func testAClientWithoutExplicitRequiredFlagsKeepsTodaysBehaviour() {
        let legacy = model(LeadFormConfig())
        XCTAssertNil(problem(legacy, first: "", last: "S", address: ""))
    }

    func testTheAddressIsOnlyDemandedWhereTheAddressBlockShows() {
        let noAddr = model(LeadFormConfig(), [
            "lead.address_line1": FO(label: nil, required: true, hidden: nil),
            "lead.last_name": FO(label: nil, required: nil, hidden: true),
        ])
        XCTAssertNil(problem(noAddr, isB2C: false, address: ""))
        XCTAssertEqual(problem(noAddr, isB2C: true, address: ""), "Address is required — search for it or type it in.")
    }

    func testAVisitInThePastIsRefusedAndOnlyWhereTheVisitIsOffered() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let msg = "Pick a visit time in the future — or clear it to save the lead without a visit."
        XCTAssertEqual(problem(agri(), visit: now.addingTimeInterval(-3600), now: now), msg)
        XCTAssertNil(problem(agri(), visit: now.addingTimeInterval(3600), now: now))
        XCTAssertNil(problem(agri(), visit: nil, now: now))
        // Farmers are not offered a visit, so a stray value never blocks them.
        XCTAssertNil(problem(agri(), isB2C: true, visit: now.addingTimeInterval(-3600), now: now))
    }
}
