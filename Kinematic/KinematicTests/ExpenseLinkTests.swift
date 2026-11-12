//
//  ExpenseLinkTests.swift
//  KinematicTests
//
//  Linking an expense claim to a CRM lead and deal (connected-B2B) and showing the cost on a lead / deal:
//  the claim body fields (omit when untouched, explicit null to clear), the editor's lead/deal consistency
//  rules, the deal picker's narrowing, the wire models and the wording of the Expenses card.
//

import XCTest
import Foundation
@testable import Kinematic

final class ExpenseLinkTests: XCTestCase {

    private let rupee = "\u{20B9}"

    private func claim(_ extra: String = "") throws -> ExpenseClaim {
        let json = #"{"id":"c1","currency":"INR","total_amount":100"# + extra + "}"
        return try JSONDecoder().decode(ExpenseClaim.self, from: Data(json.utf8))
    }

    private func deal(_ json: String) throws -> Deal {
        try JSONDecoder().decode(Deal.self, from: Data(json.utf8))
    }

    private func rollup(_ json: String) throws -> ExpenseRollup {
        try JSONDecoder().decode(ExpenseRollup.self, from: Data(json.utf8))
    }

    private func encode(_ input: ExpenseClaimInput) throws -> [String: Any] {
        let data = try JSONEncoder().encode(input)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func isNull(_ value: Any?) -> Bool { value is NSNull }

    // MARK: - Claim JSON

    func testClaimDecodesLeadAndDealFields() throws {
        let c = try claim(#","lead_id":"L1","deal_id":"D1","lead_name":"Acme Plant","deal_name":"Boiler retrofit""#)
        XCTAssertEqual(c.lead_id, "L1")
        XCTAssertEqual(c.deal_id, "D1")
        XCTAssertEqual(c.lead_name, "Acme Plant")
        XCTAssertEqual(c.deal_name, "Boiler retrofit")
    }

    func testClaimWithoutLinksDecodesAsNil() throws {
        let c = try claim()
        XCTAssertNil(c.lead_id)
        XCTAssertNil(c.deal_id)
        XCTAssertNil(c.lead_name)
        XCTAssertNil(c.deal_name)
    }

    // MARK: - Request body encoding

    func testBodyOmitsLeadAndDealWhenUntouched() throws {
        let body = try encode(ExpenseClaimInput(title: "T", items: []))
        XCTAssertNil(body["lead_id"])
        XCTAssertNil(body["deal_id"])
    }

    func testBodySendsPickedIds() throws {
        let body = try encode(ExpenseClaimInput(title: nil, lead_id: "L1", deal_id: "D1", items: []))
        XCTAssertEqual(body["lead_id"] as? String, "L1")
        XCTAssertEqual(body["deal_id"] as? String, "D1")
    }

    func testBodySendsExplicitNullToClear() throws {
        let body = try encode(ExpenseClaimInput(title: nil, clearLead: true, clearDeal: true, items: []))
        XCTAssertTrue(body.keys.contains("lead_id"))
        XCTAssertTrue(body.keys.contains("deal_id"))
        XCTAssertTrue(isNull(body["lead_id"]))
        XCTAssertTrue(isNull(body["deal_id"]))
    }

    func testAnIdWinsOverAClearFlag() throws {
        let body = try encode(ExpenseClaimInput(title: nil, lead_id: "L1", clearLead: true, items: []))
        XCTAssertEqual(body["lead_id"] as? String, "L1")
    }

    // MARK: - Body fields (pure)

    func testNotSparkSendsNothing() {
        let f = ExpenseLinkLogic.bodyFields(isSpark: false, isEditing: true,
                                            current: ExpenseLinkSelection(leadId: "L1", dealId: "D1"),
                                            baseline: ExpenseLinkSelection())
        XCTAssertEqual(f, .untouched)
    }

    func testNewClaimSendsWhatIsPickedAndNeverClears() {
        let both = ExpenseLinkLogic.bodyFields(isSpark: true, isEditing: false,
                                               current: ExpenseLinkSelection(leadId: "L1", dealId: "D1"),
                                               baseline: ExpenseLinkSelection())
        XCTAssertEqual(both, ExpenseLinkBodyFields(leadId: "L1", dealId: "D1", clearLead: false, clearDeal: false))
        let none = ExpenseLinkLogic.bodyFields(isSpark: true, isEditing: false,
                                               current: ExpenseLinkSelection(), baseline: ExpenseLinkSelection())
        XCTAssertEqual(none, .untouched)
    }

    func testEditOmitsAnUntouchedLink() {
        let same = ExpenseLinkSelection(leadId: "L1", dealId: "D1")
        XCTAssertEqual(ExpenseLinkLogic.bodyFields(isSpark: true, isEditing: true, current: same, baseline: same), .untouched)
    }

    func testEditSendsAChangedLinkAndOnlyThat() {
        let f = ExpenseLinkLogic.bodyFields(isSpark: true, isEditing: true,
                                            current: ExpenseLinkSelection(leadId: "L1", dealId: "D2"),
                                            baseline: ExpenseLinkSelection(leadId: "L1", dealId: "D1"))
        XCTAssertEqual(f, ExpenseLinkBodyFields(leadId: nil, dealId: "D2", clearLead: false, clearDeal: false))
    }

    func testEditClearingALinkSendsNull() {
        let f = ExpenseLinkLogic.bodyFields(isSpark: true, isEditing: true,
                                            current: ExpenseLinkSelection(leadId: "L1", dealId: nil),
                                            baseline: ExpenseLinkSelection(leadId: "L1", dealId: "D1"))
        XCTAssertEqual(f, ExpenseLinkBodyFields(leadId: nil, dealId: nil, clearLead: false, clearDeal: true))
        let both = ExpenseLinkLogic.bodyFields(isSpark: true, isEditing: true,
                                               current: ExpenseLinkSelection(),
                                               baseline: ExpenseLinkSelection(leadId: "L1", dealId: "D1"))
        XCTAssertEqual(both, ExpenseLinkBodyFields(leadId: nil, dealId: nil, clearLead: true, clearDeal: true))
    }

    func testBlankIdsCountAsNoLink() {
        XCTAssertNil(ExpenseLinkSelection(leadId: "  ", dealId: "").leadId)
        XCTAssertNil(ExpenseLinkSelection(leadId: "  ", dealId: "").dealId)
        // A blank baseline equals no baseline: nothing to clear.
        let f = ExpenseLinkLogic.bodyFields(isSpark: true, isEditing: true,
                                            current: ExpenseLinkSelection(),
                                            baseline: ExpenseLinkSelection(leadId: " ", dealId: nil))
        XCTAssertEqual(f, .untouched)
    }

    // MARK: - Editor state (lead / deal consistency)

    func testStateIsPrefilledFromTheClaim() throws {
        let c = try claim(#","lead_id":"L1","deal_id":"D1","lead_name":"Acme Plant","deal_name":"Boiler retrofit""#)
        let s = ExpenseLinkState(claim: c)
        XCTAssertEqual(s.leadDisplay, "Acme Plant")
        XCTAssertEqual(s.dealDisplay, "Boiler retrofit")
        XCTAssertEqual(s.selection, ExpenseLinkSelection(leadId: "L1", dealId: "D1"))
        XCTAssertNil(ExpenseLinkState(claim: nil).leadDisplay)
        XCTAssertNil(ExpenseLinkState(claim: try claim()).dealDisplay)
    }

    func testAnIdWithoutANameStillShowsARow() throws {
        let s = ExpenseLinkState(claim: try claim(#","lead_id":"L1","deal_id":"D1""#))
        XCTAssertEqual(s.leadDisplay, "Selected lead")
        XCTAssertEqual(s.dealDisplay, "Selected deal")
    }

    func testPickingADealSelectsItsLead() {
        var s = ExpenseLinkState()
        s.pickDeal(id: "D1", name: "Boiler retrofit", ownerLeadId: "L1", ownerLeadName: "Acme Plant")
        XCTAssertEqual(s.selection, ExpenseLinkSelection(leadId: "L1", dealId: "D1"))
        XCTAssertEqual(s.leadDisplay, "Acme Plant")
    }

    func testPickingADealReplacesAnotherLead() {
        var s = ExpenseLinkState()
        s.pickLead(id: "L9", name: "Other")
        s.pickDeal(id: "D1", name: "Boiler retrofit", ownerLeadId: "L1", ownerLeadName: "Acme Plant")
        XCTAssertEqual(s.leadId, "L1")
        XCTAssertEqual(s.leadDisplay, "Acme Plant")
    }

    func testPickingADealWithoutALeadKeepsTheChosenLead() {
        var s = ExpenseLinkState()
        s.pickLead(id: "L1", name: "Acme Plant")
        s.pickDeal(id: "D1", name: "Loose deal", ownerLeadId: nil, ownerLeadName: nil)
        XCTAssertEqual(s.selection, ExpenseLinkSelection(leadId: "L1", dealId: "D1"))
    }

    func testPickingADifferentLeadDropsADealOfAnotherLead() {
        var s = ExpenseLinkState()
        s.pickDeal(id: "D1", name: "Boiler retrofit", ownerLeadId: "L1", ownerLeadName: "Acme Plant")
        s.pickLead(id: "L2", name: "Beta Mills")
        XCTAssertEqual(s.selection, ExpenseLinkSelection(leadId: "L2", dealId: nil))
        XCTAssertNil(s.dealDisplay)
    }

    func testPickingTheSameLeadKeepsItsDeal() {
        var s = ExpenseLinkState()
        s.pickDeal(id: "D1", name: "Boiler retrofit", ownerLeadId: "L1", ownerLeadName: "Acme Plant")
        s.pickLead(id: "L1", name: "Acme Plant")
        XCTAssertEqual(s.selection, ExpenseLinkSelection(leadId: "L1", dealId: "D1"))
    }

    func testClearingTheLeadDropsTheDealThatBelongedToIt() {
        var s = ExpenseLinkState()
        s.pickDeal(id: "D1", name: "Boiler retrofit", ownerLeadId: "L1", ownerLeadName: "Acme Plant")
        s.clearLead()
        XCTAssertEqual(s.selection, ExpenseLinkSelection())
    }

    func testClearingTheDealKeepsTheLead() {
        var s = ExpenseLinkState()
        s.pickDeal(id: "D1", name: "Boiler retrofit", ownerLeadId: "L1", ownerLeadName: "Acme Plant")
        s.clearDeal()
        XCTAssertEqual(s.selection, ExpenseLinkSelection(leadId: "L1", dealId: nil))
    }

    func testAPrefilledClaimClearsBothWhenTheLeadIsCleared() throws {
        var s = ExpenseLinkState(claim: try claim(#","lead_id":"L1","deal_id":"D1","lead_name":"A","deal_name":"B""#))
        s.clearLead()
        XCTAssertEqual(s.selection, ExpenseLinkSelection())
    }

    // MARK: - Deal picker

    func testDealOptionsNarrowToTheChosenLeadAndSearchByName() throws {
        let deals = [
            try deal(#"{"id":"d1","name":"Boiler retrofit","lead_id":"L1"}"#),
            try deal(#"{"id":"d2","name":"Boiler service","lead_id":"L2"}"#),
            try deal(#"{"id":"d3","name":"Chiller","lead_id":"L1"}"#),
            try deal(#"{"id":"d4","name":"Loose deal"}"#),
        ]
        XCTAssertEqual(ExpenseLinkLogic.dealOptions(deals, leadId: nil, query: "").map { $0.id }, ["d1", "d2", "d3", "d4"])
        XCTAssertEqual(ExpenseLinkLogic.dealOptions(deals, leadId: "L1", query: "").map { $0.id }, ["d1", "d3"])
        XCTAssertEqual(ExpenseLinkLogic.dealOptions(deals, leadId: "L1", query: "BOILER").map { $0.id }, ["d1"])
        XCTAssertEqual(ExpenseLinkLogic.dealOptions(deals, leadId: nil, query: "boiler").map { $0.id }, ["d1", "d2"])
        XCTAssertEqual(ExpenseLinkLogic.dealOptions(deals, leadId: "  ", query: "").count, 4)
    }

    // MARK: - Captions

    func testLinkCaption() {
        XCTAssertEqual(ExpenseLinkLogic.linkCaption(leadName: "Acme", dealName: "Boiler"), "Lead: Acme · Deal: Boiler")
        XCTAssertEqual(ExpenseLinkLogic.linkCaption(leadName: "Acme", dealName: nil), "Lead: Acme")
        XCTAssertEqual(ExpenseLinkLogic.linkCaption(leadName: nil, dealName: "Boiler"), "Deal: Boiler")
        XCTAssertNil(ExpenseLinkLogic.linkCaption(leadName: " ", dealName: nil))
    }

    // MARK: - Roll-up JSON

    private let fullRollup = """
    {"currency":"INR",
     "totals":{"claim_count":2,"spent_amount":3000,"pending_amount":500,"draft_amount":0,"rejected_amount":200},
     "visit_count":3,"opportunity_value":10000,"spent_pct_of_value":30,
     "claims":[{"id":"c1","claim_no":"EXP-0001","title":"Site visit","status":"approved","total_amount":3000,"currency":"INR",
                "created_at":"2026-10-01T09:00:00Z","user_id":"u1","user_name":"Meera Rao","lead_id":"L1","deal_id":"D1","deal_name":"Boiler retrofit"},
               {"id":"c2","claim_no":"EXP-0002","title":null,"status":"submitted","total_amount":500,"currency":"INR",
                "created_at":"2026-10-03T09:00:00Z","user_id":"u1","user_name":null,"lead_id":"L1","deal_id":null,"deal_name":null}]}
    """

    func testRollupDecodes() throws {
        let r = try rollup(fullRollup)
        XCTAssertEqual(r.totals.claim_count, 2)
        XCTAssertEqual(r.totals.spent_amount, 3000)
        XCTAssertEqual(r.totals.pending_amount, 500)
        XCTAssertEqual(r.totals.rejected_amount, 200)
        XCTAssertEqual(r.visit_count, 3)
        XCTAssertEqual(r.opportunity_value, 10000)
        XCTAssertEqual(r.spent_pct_of_value, 30)
        XCTAssertEqual(r.claims.count, 2)
        XCTAssertEqual(r.claims[0].deal_name, "Boiler retrofit")
        XCTAssertNil(r.claims[1].deal_id)
    }

    func testRollupWithNullValueAndSparseTotalsDecodes() throws {
        let r = try rollup(#"{"currency":"INR","totals":{"claim_count":1},"visit_count":0,"opportunity_value":null,"spent_pct_of_value":null,"claims":[]}"#)
        XCTAssertNil(r.opportunity_value)
        XCTAssertNil(r.spent_pct_of_value)
        XCTAssertEqual(r.totals.spent_amount, 0)
        XCTAssertEqual(try rollup("{}").visit_count, 0)
    }

    // MARK: - Card wording

    func testHeadlineShowsSpendAndShareOfValue() throws {
        XCTAssertEqual(ExpenseRollupText.headline(try rollup(fullRollup)), "\(rupee)3,000 spent · 30% of \(rupee)10,000")
    }

    func testHeadlineHasNoShareWithoutAValue() throws {
        let r = try rollup(#"{"currency":"INR","totals":{"claim_count":1,"spent_amount":3000},"visit_count":1,"opportunity_value":null,"spent_pct_of_value":null,"claims":[]}"#)
        XCTAssertEqual(ExpenseRollupText.headline(r), "\(rupee)3,000 spent")
    }

    func testZeroSpendReadsRupeeZeroSpent() throws {
        let r = try rollup(#"{"currency":"INR","totals":{"claim_count":1,"spent_amount":0,"draft_amount":400},"visit_count":0,"opportunity_value":10000,"spent_pct_of_value":0,"claims":[]}"#)
        XCTAssertEqual(ExpenseRollupText.headline(r), "\(rupee)0 spent")
    }

    func testPercentKeepsOneDecimalOnlyWhenNeeded() {
        XCTAssertEqual(ExpenseRollupText.percent(30), "30%")
        XCTAssertEqual(ExpenseRollupText.percent(12.5), "12.5%")
        XCTAssertEqual(ExpenseRollupText.percent(0.04), "0%")
    }

    func testCountsUseSingularForOne() throws {
        XCTAssertEqual(ExpenseRollupText.counts(try rollup(fullRollup)), "2 claims · 3 visits")
        let one = try rollup(#"{"totals":{"claim_count":1},"visit_count":1}"#)
        XCTAssertEqual(ExpenseRollupText.counts(one), "1 claim · 1 visit")
    }

    func testBreakdownListsOnlyNonZeroPendingDraftRejected() throws {
        XCTAssertEqual(ExpenseRollupText.breakdown(try rollup(fullRollup)), "Pending \(rupee)500 · Rejected \(rupee)200")
        let none = try rollup(#"{"totals":{"claim_count":1,"spent_amount":100},"visit_count":0}"#)
        XCTAssertNil(ExpenseRollupText.breakdown(none))
        let all = try rollup(#"{"totals":{"claim_count":3,"pending_amount":1,"draft_amount":2,"rejected_amount":3}}"#)
        XCTAssertEqual(ExpenseRollupText.breakdown(all), "Pending \(rupee)1 · Draft \(rupee)2 · Rejected \(rupee)3")
    }

    func testEmptyMeansNoClaimsAndNoVisits() throws {
        XCTAssertTrue(ExpenseRollupText.isEmpty(try rollup(#"{"totals":{"claim_count":0},"visit_count":0,"claims":[]}"#)))
        XCTAssertTrue(ExpenseRollupText.isEmpty(try rollup("{}")))
        XCTAssertFalse(ExpenseRollupText.isEmpty(try rollup(fullRollup)))
        XCTAssertFalse(ExpenseRollupText.isEmpty(try rollup(#"{"totals":{"claim_count":0},"visit_count":2}"#)))
    }

    func testClaimRowText() throws {
        let r = try rollup(fullRollup)
        XCTAssertEqual(ExpenseRollupText.claimTitle(r.claims[0]), "Site visit")
        XCTAssertEqual(ExpenseRollupText.claimSubtitle(r.claims[0]), "EXP-0001 · Approved · Meera Rao · 2026-10-01")
        XCTAssertEqual(ExpenseRollupText.claimAmount(r.claims[0], in: r), "\(rupee)3,000")
        // No title: the number is the title and is not repeated; a missing name is skipped.
        XCTAssertEqual(ExpenseRollupText.claimTitle(r.claims[1]), "EXP-0002")
        XCTAssertEqual(ExpenseRollupText.claimSubtitle(r.claims[1]), "Submitted · 2026-10-03")
    }
}
