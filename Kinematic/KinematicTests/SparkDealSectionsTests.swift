//
//  SparkDealSectionsTests.swift
//  KinematicTests
//
//  Spark & Ray deal sections + account outcome: the live final price, the product-trial date rule, the
//  admin's `config.deal_sections` (enabled / label / position), the create / edit request bodies, the
//  account outcome rule, and decoding the new optional fields (which must stay nil for other tenants).
//

import XCTest
import Foundation
@testable import Kinematic

@MainActor
final class SparkDealSectionsTests: XCTestCase {

    // MARK: - helpers

    private func decodeDeal(_ json: String) throws -> Deal {
        try JSONDecoder().decode(Deal.self, from: Data(json.utf8))
    }

    private func settings(_ json: String) throws -> CRMService.CRMSettingsRaw {
        try JSONDecoder().decode(CRMService.CRMSettingsRaw.self, from: Data(json.utf8))
    }

    private func body(
        _ draft: SparkDealSectionsDraft,
        config: DealSectionsConfig = DealSectionsConfig(),
        hidden: Set<String> = [],
        previous: SparkDealSectionsDraft? = nil,
        includeQuotation: Bool = true
    ) -> [String: Any] {
        var out: [String: Any] = [:]
        draft.apply(to: &out, config: config, hidden: hidden, previous: previous, includeQuotation: includeQuotation)
        return out
    }

    // MARK: - final price

    func testFinalPriceAppliesTheDiscount() {
        XCTAssertEqual(SparkPricing.finalPrice(quoted: 1000, discountPct: 10), 900, accuracy: 0.0001)
        XCTAssertEqual(SparkPricing.finalPrice(quoted: 1000, discountPct: 0), 1000, accuracy: 0.0001)
        XCTAssertEqual(SparkPricing.finalPrice(quoted: 1000, discountPct: 100), 0, accuracy: 0.0001)
        XCTAssertEqual(SparkPricing.finalPrice(quoted: 999.99, discountPct: 12.5), 874.99, accuracy: 0.0001)
    }

    func testFinalPriceFromTypedText() {
        XCTAssertEqual(SparkPricing.finalPrice(quotedText: "1,00,000", discountText: "5"), 95000)
        // A blank discount means no discount.
        XCTAssertEqual(SparkPricing.finalPrice(quotedText: "2500", discountText: ""), 2500)
        XCTAssertEqual(SparkPricing.finalPrice(quotedText: " 2500 ", discountText: "  "), 2500)
    }

    func testFinalPriceIsNilWhileInputsAreUnusable() {
        XCTAssertNil(SparkPricing.finalPrice(quotedText: "", discountText: "10"))
        XCTAssertNil(SparkPricing.finalPrice(quotedText: "abc", discountText: ""))
        XCTAssertNil(SparkPricing.finalPrice(quotedText: "-5", discountText: ""))
        XCTAssertNil(SparkPricing.finalPrice(quotedText: "1000", discountText: "101"))
        XCTAssertNil(SparkPricing.finalPrice(quotedText: "1000", discountText: "-1"))
        XCTAssertNil(SparkPricing.finalPrice(quotedText: "1000", discountText: "ten"))
    }

    func testPricingValidation() {
        XCTAssertNil(SparkPricing.validate(quotedText: "", discountText: ""))
        XCTAssertNil(SparkPricing.validate(quotedText: "0", discountText: "100"))
        XCTAssertEqual(SparkPricing.validate(quotedText: "x", discountText: ""), SparkPricing.quotedMessage)
        XCTAssertEqual(SparkPricing.validate(quotedText: "10", discountText: "100.5"), SparkPricing.discountMessage)
    }

    // MARK: - dates + trial

    func testDatesRoundTripAndRejectNonsense() throws {
        let d = try XCTUnwrap(SparkDealDate.parse("2026-11-05"))
        XCTAssertEqual(SparkDealDate.format(d), "2026-11-05")
        // A timestamp is cut to its date part.
        XCTAssertEqual(SparkDealDate.format(try XCTUnwrap(SparkDealDate.parse("2026-11-05T00:00:00Z"))), "2026-11-05")
        XCTAssertNil(SparkDealDate.parse(""))
        XCTAssertNil(SparkDealDate.parse("2026-02-31"))
        XCTAssertNil(SparkDealDate.parse("05/11/2026"))
        XCTAssertEqual(SparkDealDate.normalized("2026-11-05T10:00:00Z"), "2026-11-05")
        XCTAssertEqual(SparkDealDate.normalized(nil), "")
        XCTAssertEqual(SparkDealDate.normalized("  "), "")
    }

    func testTrialEndMayNotBeBeforeStart() {
        XCTAssertEqual(SparkTrial.validate(start: "2026-11-10", end: "2026-11-09"), SparkTrial.orderMessage)
        XCTAssertNil(SparkTrial.validate(start: "2026-11-10", end: "2026-11-10"))
        XCTAssertNil(SparkTrial.validate(start: "2026-11-10", end: "2026-12-01"))
        // Month / year boundaries compare as dates, not strings.
        XCTAssertEqual(SparkTrial.validate(start: "2027-01-01", end: "2026-12-31"), SparkTrial.orderMessage)
    }

    func testTrialWithAMissingDateIsFine() {
        XCTAssertNil(SparkTrial.validate(start: "", end: "2026-11-09"))
        XCTAssertNil(SparkTrial.validate(start: "2026-11-09", end: ""))
        XCTAssertNil(SparkTrial.validate(start: "", end: ""))
    }

    func testDraftValidationOnlyChecksTheTrialWhileItIsOn() {
        var d = SparkDealSectionsDraft()
        d.trialStart = "2026-11-10"
        d.trialEnd = "2026-11-01"
        let config = DealSectionsConfig()
        XCTAssertNil(d.validationError(config: config))                    // trial not answered
        d.trialRequired = false
        XCTAssertNil(d.validationError(config: config))
        d.trialRequired = true
        XCTAssertEqual(d.validationError(config: config), SparkTrial.orderMessage)
        // A disabled section is not checked.
        let off = DealSectionsConfig(entries: [.productTrial: .init(enabled: false)])
        XCTAssertNil(d.validationError(config: off))
    }

    func testDraftValidationChecksPricing() {
        var d = SparkDealSectionsDraft()
        d.quotedText = "1000"
        d.discountText = "150"
        XCTAssertEqual(d.validationError(config: DealSectionsConfig()), SparkPricing.discountMessage)
        d.discountText = "15"
        XCTAssertNil(d.validationError(config: DealSectionsConfig()))
        XCTAssertEqual(d.finalPrice, 850)
    }

    // MARK: - deal_sections config

    func testNoConfigMeansEverythingInTheDefaultOrder() {
        for cfg in [DealSectionsConfig.parse(nil), DealSectionsConfig.parse([:]),
                    DealSectionsConfig.parse(["deal_sections": .string("junk")]),
                    DealSectionsConfig.parse(settings: nil)] {
            XCTAssertEqual(cfg.ordered, [.quotation, .pricing, .productTrial, .approvals])
            XCTAssertEqual(cfg.label(.productTrial), "Product trial")
            XCTAssertEqual(cfg.label(.approvals), "Approvals")
            XCTAssertTrue(cfg.isEnabled(.quotation))
        }
    }

    func testParsesEnabledLabelAndPosition() throws {
        let raw = try settings("""
        {"business_type":"b2b","config":{"deal_sections":{
          "pricing":{"enabled":false},
          "product_trial":{"label":"  Site trial  ","position":0},
          "approvals":{"label":"Sign-off","position":9},
          "quotation":{"enabled":true,"position":1}
        }}}
        """)
        let cfg = DealSectionsConfig.parse(settings: raw)
        XCTAssertFalse(cfg.isEnabled(.pricing))
        XCTAssertTrue(cfg.isEnabled(.quotation))
        XCTAssertEqual(cfg.label(.productTrial), "Site trial")
        XCTAssertEqual(cfg.label(.approvals), "Sign-off")
        XCTAssertEqual(cfg.label(.pricing), "Pricing")
        // Disabled sections drop out; the rest sort by position (trial 0, quotation 1, approvals 9).
        XCTAssertEqual(cfg.ordered, [.productTrial, .quotation, .approvals])
    }

    func testBlankOrOverlongLabelsAreHandled() {
        let long = String(repeating: "x", count: 90)
        let cfg = DealSectionsConfig.parse([
            "deal_sections": .object([
                "pricing": .object(["label": .string("   ")]),
                "quotation": .object(["label": .string(long)]),
            ]),
        ])
        XCTAssertEqual(cfg.label(.pricing), "Pricing")
        XCTAssertEqual(cfg.label(.quotation).count, DealSectionsConfig.maxLabelLength)
    }

    func testTiesAndMissingPositionsFallBackToTheDefaultOrder() {
        let cfg = DealSectionsConfig.parse([
            "deal_sections": .object([
                "approvals": .object(["position": .number(1)]),
                "pricing": .object(["position": .number(1)]),
            ]),
        ])
        // approvals + pricing tie at 1 -> default order (pricing first); quotation (default 0) leads,
        // product_trial keeps its default index 2 and so follows.
        XCTAssertEqual(cfg.ordered, [.quotation, .pricing, .approvals, .productTrial])
    }

    func testWrongTypesAreIgnored() {
        let cfg = DealSectionsConfig.parse([
            "deal_sections": .object([
                "pricing": .object(["enabled": .string("no"), "label": .number(3), "position": .string("2")]),
                "approvals": .string("x"),
            ]),
        ])
        XCTAssertTrue(cfg.isEnabled(.pricing))
        XCTAssertEqual(cfg.label(.pricing), "Pricing")
        XCTAssertEqual(cfg.ordered, [.quotation, .pricing, .productTrial, .approvals])
    }

    // MARK: - create body

    private func fullDraft() -> SparkDealSectionsDraft {
        var d = SparkDealSectionsDraft()
        d.quotationNo = "  Q-2026-07 "
        d.quotedText = "1,000"
        d.discountText = "10"
        d.validTill = "2026-12-31"
        d.trialRequired = true
        d.trialStart = "2026-11-01"
        d.trialEnd = "2026-11-15"
        d.trialResult = "successful"
        d.trialNotes = " ran fine "
        d.technicalApprovalBy = "u1"
        d.preparedBy = "u2"
        d.checkedBy = "u3"
        d.supervisorId = "u4"
        return d
    }

    func testCreateBodySendsEveryFilledField() {
        let b = body(fullDraft())
        XCTAssertEqual(b["quotation_no"] as? String, "Q-2026-07")
        XCTAssertEqual(b["pricing_quoted"] as? Double, 1000)
        XCTAssertEqual(b["pricing_discount_pct"] as? Double, 10)
        XCTAssertEqual(b["pricing_final"] as? Double, 900)
        XCTAssertEqual(b["pricing_valid_till"] as? String, "2026-12-31")
        XCTAssertEqual(b["trial_required"] as? Bool, true)
        XCTAssertEqual(b["trial_start"] as? String, "2026-11-01")
        XCTAssertEqual(b["trial_end"] as? String, "2026-11-15")
        XCTAssertEqual(b["trial_result"] as? String, "successful")
        XCTAssertEqual(b["trial_notes"] as? String, "ran fine")
        XCTAssertEqual(b["technical_approval_by"] as? String, "u1")
        XCTAssertEqual(b["prepared_by"] as? String, "u2")
        XCTAssertEqual(b["checked_by"] as? String, "u3")
        XCTAssertEqual(b["supervisor_id"] as? String, "u4")
    }

    func testAnEmptyDraftSendsNothingOnCreate() {
        XCTAssertTrue(body(SparkDealSectionsDraft()).isEmpty)
    }

    func testCreateOmitsBlankAndNullValues() {
        var d = SparkDealSectionsDraft()
        d.quotedText = "500"
        let b = body(d)
        XCTAssertEqual(b["pricing_quoted"] as? Double, 500)
        XCTAssertEqual(b["pricing_final"] as? Double, 500)      // no discount = same as quoted
        XCTAssertNil(b["pricing_discount_pct"])
        XCTAssertNil(b["pricing_valid_till"])
        XCTAssertNil(b["quotation_no"])
        XCTAssertNil(b["prepared_by"])
        XCTAssertFalse(b.values.contains { $0 is NSNull })
    }

    func testTrialNotNeededSendsOnlyThatAnswer() {
        var d = fullDraft()
        d.trialRequired = false
        let b = body(d)
        XCTAssertEqual(b["trial_required"] as? Bool, false)
        for k in ["trial_start", "trial_end", "trial_result", "trial_notes"] { XCTAssertNil(b[k], k) }
    }

    func testTrialNeededWithoutAResultSendsPending() {
        var d = SparkDealSectionsDraft()
        d.trialRequired = true
        let b = body(d)
        XCTAssertEqual(b["trial_required"] as? Bool, true)
        XCTAssertEqual(b["trial_result"] as? String, "pending")
        XCTAssertNil(b["trial_start"])
    }

    func testUnansweredTrialSendsNothing() {
        var d = fullDraft()
        d.trialRequired = nil
        let b = body(d)
        for k in SparkDealSectionsDraft.trialKeys { XCTAssertNil(b[k], k) }
    }

    func testADisabledSectionIsNotSent() {
        let config = DealSectionsConfig(entries: [.pricing: .init(enabled: false), .approvals: .init(enabled: false)])
        let b = body(fullDraft(), config: config)
        for k in SparkDealSectionsDraft.pricingKeys + SparkDealSectionsDraft.peopleKeys { XCTAssertNil(b[k], k) }
        XCTAssertEqual(b["trial_required"] as? Bool, true)
        XCTAssertEqual(b["quotation_no"] as? String, "Q-2026-07")
        let noQuote = DealSectionsConfig(entries: [.quotation: .init(enabled: false)])
        XCTAssertNil(body(fullDraft(), config: noQuote)["quotation_no"])
    }

    func testAHiddenFieldIsNotSent() {
        let b = body(fullDraft(), hidden: ["pricing_discount_pct", "supervisor_id", "trial_notes"])
        XCTAssertNil(b["pricing_discount_pct"])
        XCTAssertNil(b["supervisor_id"])
        XCTAssertNil(b["trial_notes"])
        XCTAssertEqual(b["prepared_by"] as? String, "u2")
        XCTAssertEqual(b["pricing_quoted"] as? Double, 1000)
    }

    func testHiddenKeysCollectsWhatTheOverridesHide() {
        let hidden = SparkDealSectionsDraft.hiddenKeys { $0 == "prepared_by" || $0 == "trial_end" || $0 == "name" }
        XCTAssertEqual(hidden, ["prepared_by", "trial_end"])
        XCTAssertTrue(SparkDealSectionsDraft.allKeys.contains("quotation_no"))
        XCTAssertEqual(SparkDealSectionsDraft.allKeys.count, 1 + 4 + 5 + 4)
    }

    // MARK: - edit body

    func testAnUntouchedEditSendsNothing() {
        let d = fullDraft()
        XCTAssertTrue(body(d, previous: d).isEmpty)
        XCTAssertTrue(body(SparkDealSectionsDraft(), previous: SparkDealSectionsDraft()).isEmpty)
    }

    func testEditSendsOnlyWhatChanged() {
        let before = fullDraft()
        var after = before
        after.preparedBy = "u9"
        after.trialNotes = "second round"
        let b = body(after, previous: before)
        XCTAssertEqual(Set(b.keys), ["prepared_by", "trial_notes"])
        XCTAssertEqual(b["prepared_by"] as? String, "u9")
        XCTAssertEqual(b["trial_notes"] as? String, "second round")
    }

    func testEditRecomputesTheFinalPriceWhenThePricingChanges() {
        let before = fullDraft()
        var after = before
        after.discountText = "20"
        let b = body(after, previous: before)
        XCTAssertEqual(b["pricing_discount_pct"] as? Double, 20)
        XCTAssertEqual(b["pricing_final"] as? Double, 800)
        XCTAssertNil(b["pricing_quoted"])
    }

    func testEditClearsAValueWithNull() {
        let before = fullDraft()
        var after = before
        after.supervisorId = ""
        after.validTill = ""
        after.quotedText = ""
        let b = body(after, previous: before)
        XCTAssertTrue(b["supervisor_id"] is NSNull)
        XCTAssertTrue(b["pricing_valid_till"] is NSNull)
        XCTAssertTrue(b["pricing_quoted"] is NSNull)
        XCTAssertTrue(b["pricing_final"] is NSNull)      // no quoted price -> no final price
    }

    func testEditNeverSendsTheQuotationWhenItIsNotEditable() {
        let before = fullDraft()
        var after = before
        after.quotationNo = "Q-NEW"
        XCTAssertNil(body(after, previous: before, includeQuotation: false)["quotation_no"])
        XCTAssertEqual(body(after, previous: before, includeQuotation: true)["quotation_no"] as? String, "Q-NEW")
    }

    func testSwitchingTheTrialOnSendsItsDetails() {
        var before = SparkDealSectionsDraft()
        before.trialRequired = false
        var after = before
        after.trialRequired = true
        after.trialStart = "2026-11-01"
        let b = body(after, previous: before)
        XCTAssertEqual(b["trial_required"] as? Bool, true)
        XCTAssertEqual(b["trial_start"] as? String, "2026-11-01")
        XCTAssertEqual(b["trial_result"] as? String, "pending")
    }

    func testSwitchingTheTrialOffSendsOnlyTheAnswer() {
        let before = fullDraft()
        var after = before
        after.trialRequired = false
        let b = body(after, previous: before)
        XCTAssertEqual(Set(b.keys), ["trial_required"])
        XCTAssertEqual(b["trial_required"] as? Bool, false)
    }

    // MARK: - decoding

    func testDealDecodesTheNewFieldsAndNames() throws {
        let d = try decodeDeal("""
        {"id":"d1","name":"Plant A","quotation_no":"Q-1",
         "pricing_quoted":1000,"pricing_discount_pct":12.5,"pricing_final":875,"pricing_valid_till":"2026-12-31",
         "trial_required":true,"trial_start":"2026-11-01","trial_end":"2026-11-15","trial_result":"failed","trial_notes":"n",
         "technical_approval_by":"u1","prepared_by":"u2","checked_by":"u3","supervisor_id":"u4",
         "technical_approval_by_name":"Asha","prepared_by_name":"Bala","checked_by_name":"Chitra","supervisor_id_name":"Dev"}
        """)
        XCTAssertEqual(d.pricingQuoted, 1000)
        XCTAssertEqual(d.pricingDiscountPct, 12.5)
        XCTAssertEqual(d.pricingFinal, 875)
        XCTAssertEqual(d.pricingValidTill, "2026-12-31")
        XCTAssertEqual(d.trialRequired, true)
        XCTAssertEqual(d.trialResult, "failed")
        XCTAssertEqual(d.technicalApprovalByName, "Asha")
        XCTAssertEqual(d.supervisorIdName, "Dev")
        XCTAssertEqual(SparkDealSectionsDraft.knownNames(deal: d), ["u1": "Asha", "u2": "Bala", "u3": "Chitra", "u4": "Dev"])

        let draft = SparkDealSectionsDraft(deal: d)
        XCTAssertEqual(draft.quotedText, "1000")
        XCTAssertEqual(draft.discountText, "12.50")
        XCTAssertEqual(draft.trialRequired, true)
        XCTAssertEqual(draft.trialResult, "failed")
        XCTAssertEqual(draft.supervisorId, "u4")
        XCTAssertEqual(draft.finalPrice, 875)
    }

    func testOtherTenantsDealsDecodeWithNoSections() throws {
        let d = try decodeDeal(#"{"id":"d2","name":"Other"}"#)
        XCTAssertNil(d.pricingQuoted)
        XCTAssertNil(d.trialRequired)
        XCTAssertNil(d.technicalApprovalByName)
        let draft = SparkDealSectionsDraft(deal: d)
        XCTAssertEqual(draft, SparkDealSectionsDraft())
        XCTAssertTrue(SparkDealSectionsDraft.knownNames(deal: d).isEmpty)
    }

    func testTimestampedDatesAreTrimmedWhenSeedingTheDraft() throws {
        let d = try decodeDeal(#"{"id":"d3","name":"X","pricing_valid_till":"2026-12-31T00:00:00.000Z","trial_start":"2026-11-01T00:00:00Z"}"#)
        let draft = SparkDealSectionsDraft(deal: d)
        XCTAssertEqual(draft.validTill, "2026-12-31")
        XCTAssertEqual(draft.trialStart, "2026-11-01")
    }

    // MARK: - account outcome (read-only legacy value; no longer entered on accounts)

    func testAccountDecodesTheOutcome() throws {
        let with = try JSONDecoder().decode(CRMAccount.self, from: Data(#"{"id":"a1","name":"Acme","outcome":"Rate contract"}"#.utf8))
        XCTAssertEqual(with.outcome, "Rate contract")
        let without = try JSONDecoder().decode(CRMAccount.self, from: Data(#"{"id":"a2","name":"Other"}"#.utf8))
        XCTAssertNil(without.outcome)
    }
}
