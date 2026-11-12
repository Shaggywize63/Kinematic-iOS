//
//  LeadNumberAndTypeTests.swift
//  KinematicTests
//
//  Lead number (`ref_no`) and lead type (`lead_type`): the wire model, the label mapping, what is shown
//  (a missing number shows nothing), the search placeholder, the create / edit body fields (set, cleared,
//  untouched), the required rule, the field-override gate and the custom-stage status helpers.
//

import XCTest
import Foundation
@testable import Kinematic

final class LeadNumberAndTypeTests: XCTestCase {

    private typealias FO = LeadFieldOverridesModel.FieldOverride

    private func lead(_ extra: String = "") throws -> Lead {
        let json = #"{"id":"L1""# + extra + "}"
        return try JSONDecoder().decode(Lead.self, from: Data(json.utf8))
    }

    private func option(_ value: String, won: Bool = false, lost: Bool = false) -> LeadStatusOption {
        LeadStatusOption(value: value, label: LeadStatusDisplay.prettify(value), color: nil, isWon: won, isLost: lost)
    }

    // MARK: Wire model

    func testLeadDecodesRefNoAndLeadType() throws {
        let l = try lead(#","ref_no":"SR/LD/2627-12","lead_type":"requirement""#)
        XCTAssertEqual(l.refNo, "SR/LD/2627-12")
        XCTAssertEqual(l.leadType, "requirement")
    }

    func testLeadWithoutTheNewKeysDecodesToNil() throws {
        let l = try lead()
        XCTAssertNil(l.refNo)
        XCTAssertNil(l.leadType)
    }

    func testLeadTypeNullDecodesToNil() throws {
        let l = try lead(#","ref_no":null,"lead_type":null"#)
        XCTAssertNil(l.refNo)
        XCTAssertNil(l.leadType)
    }

    // MARK: Labels

    func testLabelMapping() {
        XCTAssertEqual(LeadNumberAndType.label(for: "requirement"), "Requirement")
        XCTAssertEqual(LeadNumberAndType.label(for: "discussion"), "Discussion")
        XCTAssertEqual(LeadNumberAndType.label(for: " Requirement "), "Requirement")
        XCTAssertEqual(LeadNumberAndType.label(for: "some_type"), "Some Type")
        XCTAssertNil(LeadNumberAndType.label(for: nil))
        XCTAssertNil(LeadNumberAndType.label(for: "  "))
    }

    func testLeadTypeParsing() {
        XCTAssertEqual(LeadType(raw: "requirement"), .requirement)
        XCTAssertEqual(LeadType(raw: "DISCUSSION"), .discussion)
        XCTAssertNil(LeadType(raw: nil))
        XCTAssertNil(LeadType(raw: ""))
        XCTAssertNil(LeadType(raw: "other"))
        XCTAssertEqual(LeadType.allCases.map { $0.label }, ["Requirement", "Discussion"])
    }

    // MARK: Lead number display

    func testRefDisplayTrimsAndNeverShowsAPlaceholder() {
        XCTAssertEqual(LeadNumberAndType.refDisplay(" SR/LD/2627-12 "), "SR/LD/2627-12")
        XCTAssertNil(LeadNumberAndType.refDisplay(nil))
        XCTAssertNil(LeadNumberAndType.refDisplay(""))
        XCTAssertNil(LeadNumberAndType.refDisplay("   "))
    }

    func testRefDisplayIsSparkOnly() {
        XCTAssertEqual(LeadNumberAndType.refDisplay("SR/LD/2627-12", isSpark: true), "SR/LD/2627-12")
        XCTAssertNil(LeadNumberAndType.refDisplay("SR/LD/2627-12", isSpark: false))
        XCTAssertNil(LeadNumberAndType.refDisplay(nil, isSpark: true))
    }

    func testSearchPlaceholder() {
        XCTAssertEqual(LeadNumberAndType.searchPlaceholder(isSpark: false), "Search leads…")
        XCTAssertEqual(LeadNumberAndType.searchPlaceholder(isSpark: true), "Search leads or lead no…")
    }

    // MARK: Visibility

    func testIsShownNeedsSparkLoadedAndNotHidden() {
        XCTAssertTrue(LeadNumberAndType.isShown(isSpark: true, didLoad: true, hidden: false))
        XCTAssertFalse(LeadNumberAndType.isShown(isSpark: false, didLoad: true, hidden: false))
        XCTAssertFalse(LeadNumberAndType.isShown(isSpark: true, didLoad: false, hidden: false))
        XCTAssertFalse(LeadNumberAndType.isShown(isSpark: true, didLoad: true, hidden: true))
    }

    @MainActor
    func testFieldOverrideGateHidesLeadType() {
        let model = LeadFieldOverridesModel()
        XCTAssertFalse(model.didLoad)
        model.ingest(rawOverrides: [
            "lead.lead_type": FO(label: "Enquiry Type", required: true, hidden: nil),
        ])
        XCTAssertTrue(model.didLoad)
        XCTAssertFalse(model.isHidden("lead_type", isB2C: false))
        XCTAssertEqual(model.labelFor("lead_type", defaultLabel: LeadNumberAndType.defaultLabel, isB2C: false), "Enquiry Type")
        XCTAssertTrue(model.explicitlyRequired("lead_type", isB2C: false))

        model.ingest(rawOverrides: ["lead.lead_type": FO(label: nil, required: nil, hidden: true)])
        XCTAssertTrue(model.isHidden("lead_type", isB2C: false))
        let hidden = model.isHidden(LeadNumberAndType.fieldKey, isB2C: false)
        XCTAssertFalse(LeadNumberAndType.isShown(isSpark: true, didLoad: model.didLoad, hidden: hidden))
    }

    // MARK: Create body

    func testCreateFieldsSetsTheChosenType() {
        let f = LeadNumberAndType.createFields(selection: .discussion, shown: true)
        XCTAssertEqual(f["lead_type"] as? String, "discussion")
        XCTAssertEqual(f.count, 1)
    }

    func testCreateFieldsOmitsNoneAndHidden() {
        XCTAssertTrue(LeadNumberAndType.createFields(selection: nil, shown: true).isEmpty)
        XCTAssertTrue(LeadNumberAndType.createFields(selection: .requirement, shown: false).isEmpty)
    }

    // MARK: Edit body

    func testEditFieldsUntouchedSendsNothing() {
        XCTAssertTrue(LeadNumberAndType.editFields(original: "requirement", selection: .requirement, shown: true).isEmpty)
        XCTAssertTrue(LeadNumberAndType.editFields(original: nil, selection: nil, shown: true).isEmpty)
        // A value the app does not know cannot be edited, so leaving it alone sends nothing either.
        XCTAssertTrue(LeadNumberAndType.editFields(original: "legacy", selection: nil, shown: true).isEmpty)
    }

    func testEditFieldsChangeSendsTheNewValue() {
        let f = LeadNumberAndType.editFields(original: "requirement", selection: .discussion, shown: true)
        XCTAssertEqual(f["lead_type"] as? String, "discussion")
        let fromNone = LeadNumberAndType.editFields(original: nil, selection: .requirement, shown: true)
        XCTAssertEqual(fromNone["lead_type"] as? String, "requirement")
    }

    func testEditFieldsClearSendsExplicitNull() {
        let f = LeadNumberAndType.editFields(original: "discussion", selection: nil, shown: true)
        XCTAssertEqual(f.count, 1)
        XCTAssertTrue(f["lead_type"] is NSNull)
    }

    func testEditFieldsHiddenSendsNothingEvenWhenChanged() {
        XCTAssertTrue(LeadNumberAndType.editFields(original: "requirement", selection: nil, shown: false).isEmpty)
        XCTAssertTrue(LeadNumberAndType.editFields(original: nil, selection: .discussion, shown: false).isEmpty)
    }

    func testClearedBodySerialisesAsJSONNull() throws {
        let f = LeadNumberAndType.editFields(original: "discussion", selection: nil, shown: true)
        let data = try JSONSerialization.data(withJSONObject: f)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("null"), text)
        XCTAssertFalse(f.keys.contains("ref_no"), "the lead number is read-only and never sent")
    }

    // MARK: Required

    func testRequiredProblem() {
        XCTAssertEqual(
            LeadNumberAndType.requiredProblem(shown: true, required: true, label: "Lead Type", selection: nil),
            "Lead Type is required.")
        XCTAssertNil(LeadNumberAndType.requiredProblem(shown: true, required: true, label: "Lead Type", selection: .requirement))
        XCTAssertNil(LeadNumberAndType.requiredProblem(shown: true, required: false, label: "Lead Type", selection: nil))
        // A hidden field has nothing to fill in, so it never blocks.
        XCTAssertNil(LeadNumberAndType.requiredProblem(shown: false, required: true, label: "Lead Type", selection: nil))
    }

    // MARK: Custom lead stages

    func testPrettifyKeepsCustomStagesReadable() {
        XCTAssertEqual(LeadStatusDisplay.prettify("cold_call"), "Cold Call")
        XCTAssertEqual(LeadStatusDisplay.prettify("negotiation"), "Negotiation")
        XCTAssertEqual(LeadStatusDisplay.prettify("trash"), "Trash")
    }

    func testStatusLabelPrefersTheConfiguredLabel() {
        let opts = [LeadStatusOption(value: "cold_call", label: "Cold Calling", color: nil, isWon: false, isLost: false)]
        XCTAssertEqual(LeadStatusDisplay.label(for: "cold_call", options: opts), "Cold Calling")
        XCTAssertEqual(LeadStatusDisplay.label(for: "COLD_CALL", options: opts), "Cold Calling")
        XCTAssertEqual(LeadStatusDisplay.label(for: "finished", options: opts), "Finished")
        XCTAssertEqual(LeadStatusDisplay.label(for: "cold_call", options: []), "Cold Call")
    }

    func testResolvedStatusKeepsDefaultWithoutACustomSet() {
        XCTAssertEqual(LeadStatusDisplay.resolvedStatus(current: "new", options: []), "new")
    }

    func testResolvedStatusKeepsCurrentWhenOffered() {
        let opts = [option("new"), option("cold_call")]
        XCTAssertEqual(LeadStatusDisplay.resolvedStatus(current: "new", options: opts), "new")
    }

    func testResolvedStatusMovesToTheFirstOpenStage() {
        let opts = [option("finished", won: true), option("cold_call"), option("negotiation"), option("trash", lost: true)]
        XCTAssertEqual(LeadStatusDisplay.resolvedStatus(current: "new", options: opts), "cold_call")
    }

    func testResolvedStatusFallsBackToTheFirstWhenAllAreTerminal() {
        let opts = [option("finished", won: true), option("trash", lost: true)]
        XCTAssertEqual(LeadStatusDisplay.resolvedStatus(current: "new", options: opts), "finished")
    }
}
