//
//  AppUiConfigTests.swift
//  KinematicTests
//
//  The per-client app UI config (`app_ui_config`): the maps are free-form, so a key the app has not met
//  before survives decoding; the hide-only checks (`tabs[id] != false`) are untouched; and the new opt-in
//  checks need an EXPLICIT true. Also the dashboard's summary decoding, which gained an optional
//  per-lead-type split.
//

import XCTest
@testable import Kinematic

final class AppUiConfigTests: XCTestCase {

    private func config(_ json: String) throws -> AppUiConfig {
        try JSONDecoder().decode(AppUiConfig.self, from: Data(json.utf8))
    }

    private func user(_ appUiConfig: String?) throws -> User {
        let extra = appUiConfig.map { #","app_ui_config":\#($0)"# } ?? ""
        let json = #"{"id":"u1","name":"Asha","role":"executive"\#(extra)}"#
        return try JSONDecoder().decode(User.self, from: Data(json.utf8))
    }

    // MARK: - decoding

    func testKeysTheAppDoesNotKnowYetSurviveDecoding() throws {
        let c = try config(#"{"tabs":{"expenses":true,"new_form":false,"some_future_tab":true},"home":{"open_volume":false},"menu":{"x":true}}"#)
        XCTAssertEqual(c.tabs?["expenses"], true)
        XCTAssertEqual(c.tabs?["new_form"], false)
        XCTAssertEqual(c.tabs?["some_future_tab"], true)
        XCTAssertEqual(c.home?["open_volume"], false)
        XCTAssertEqual(c.menu?["x"], true)
    }

    func testAnEmptyConfigDecodesToNothing() throws {
        let c = try config("{}")
        XCTAssertNil(c.tabs)
        XCTAssertNil(c.home)
    }

    func testTheConfigSurvivesBeingStoredWithTheSession() throws {
        // The user is persisted as JSON between launches; the new keys must come back.
        let u = try user(#"{"tabs":{"expenses":true},"home":{"open_volume":false}}"#)
        let back = try JSONDecoder().decode(User.self, from: JSONEncoder().encode(u))
        XCTAssertTrue(back.tabExplicitlyOn("expenses"))
        XCTAssertFalse(back.homeVisible("open_volume"))
    }

    // MARK: - explicit-on vs hide-only

    func testAnOptInTabNeedsAnExplicitTrue() throws {
        XCTAssertTrue(try config(#"{"tabs":{"expenses":true}}"#).tabExplicitlyOn("expenses"))
        XCTAssertFalse(try config(#"{"tabs":{"expenses":false}}"#).tabExplicitlyOn("expenses"))
        XCTAssertFalse(try config(#"{"tabs":{"attendance":true}}"#).tabExplicitlyOn("expenses"))
        XCTAssertFalse(try config(#"{"tabs":{}}"#).tabExplicitlyOn("expenses"))
        XCTAssertFalse(try config("{}").tabExplicitlyOn("expenses"))
    }

    func testTheHideOnlyChecksAreUnchanged() throws {
        // No config, or a key that is absent / true: visible. Only an explicit false hides.
        let none = try user(nil)
        XCTAssertTrue(none.tabVisible("new_form"))
        XCTAssertTrue(none.homeVisible("open_volume"))
        XCTAssertFalse(none.tabExplicitlyOn("expenses"))

        let u = try user(#"{"tabs":{"expenses":true,"new_form":false},"home":{"open_volume":false}}"#)
        XCTAssertFalse(u.tabVisible("new_form"))      // "New" goes away when the client turns it off...
        XCTAssertTrue(u.tabVisible("attendance"))     // ...everything else keeps its default
        XCTAssertTrue(u.tabVisible("expenses"))       // and an explicit true is still "visible" to the old check
        XCTAssertFalse(u.homeVisible("open_volume"))
        XCTAssertTrue(u.homeVisible("stores"))
        XCTAssertTrue(u.tabExplicitlyOn("expenses"))
    }

    // MARK: - the Expenses tab

    func testTheExpensesTabNeedsTheModuleAndAnExplicitOptIn() throws {
        let on = try config(#"{"tabs":{"expenses":true}}"#)
        let off = try config(#"{"tabs":{"expenses":false}}"#)
        let absent = try config(#"{"tabs":{"new_form":false}}"#)
        XCTAssertTrue(ClientFeatures.expensesTabShown(showsExpenses: true, config: on))
        // Without the Expenses module the opt-in alone changes nothing.
        XCTAssertFalse(ClientFeatures.expensesTabShown(showsExpenses: false, config: on))
        // Without the opt-in the tab bar is exactly what it was.
        XCTAssertFalse(ClientFeatures.expensesTabShown(showsExpenses: true, config: off))
        XCTAssertFalse(ClientFeatures.expensesTabShown(showsExpenses: true, config: absent))
        XCTAssertFalse(ClientFeatures.expensesTabShown(showsExpenses: true, config: nil))
    }

    // MARK: - dashboard summary

    private func summary(_ json: String) throws -> CRMAnalyticsSummary {
        try JSONDecoder().decode(CRMAnalyticsSummary.self, from: Data(json.utf8))
    }

    func testTheLeadsSplitIsOptionalOnTheSummary() throws {
        let with = try summary(#"{"total_leads":42,"new_leads_30d":7,"open_deals":3,"leads_by_segment":{"b2b":12,"b2c":30}}"#)
        XCTAssertEqual(with.leadsBySegment, LeadsBySegment(b2b: 12, b2c: 30))
        XCTAssertEqual(with.totalLeads, 42)
        XCTAssertEqual(with.newLeadsThisWeek, 7)
        XCTAssertEqual(with.openDeals, 3)
        // Absent (every client without named lead types): nothing new.
        XCTAssertNil(try summary(#"{"total_leads":42}"#).leadsBySegment)
        XCTAssertNil(try summary("{}").leadsBySegment)
    }

    func testAMalformedSplitCostsOnlyThatTile() throws {
        let s = try summary(#"{"total_leads":42,"open_deals":3,"leads_by_segment":"oops"}"#)
        XCTAssertNil(s.leadsBySegment)
        XCTAssertEqual(s.totalLeads, 42)
        XCTAssertEqual(s.openDeals, 3)
        // A missing count reads as zero.
        XCTAssertEqual(try summary(#"{"leads_by_segment":{"b2b":5}}"#).leadsBySegment, LeadsBySegment(b2b: 5, b2c: 0))
    }

    func testTheSummaryStillDecodesEveryOtherNumber() throws {
        let s = try summary("""
        {"total_leads":10,"new_leads_30d":4,"open_deals":2,"open_deal_value":1500.5,"open_deal_volume":9000,
         "won_deals_30d":1,"won_revenue_30d":700,"win_rate_30d":0.25,"avg_deal_size":350,"activities_7d":12,"estimates_raised":88}
        """)
        XCTAssertEqual(s.openPipelineValue, 1500.5)
        XCTAssertEqual(s.openDealVolume, 9000)
        XCTAssertEqual(s.dealsWonThisMonth, 1)
        XCTAssertEqual(s.revenueWonThisMonth, 700)
        XCTAssertEqual(s.winRate, 0.25)
        XCTAssertEqual(s.averageDealSize, 350)
        XCTAssertEqual(s.activitiesToday, 12)
        XCTAssertEqual(s.estimatesRaised, 88)
        XCTAssertNil(s.tasksDue)
        XCTAssertNil(s.leadsBySegment)
        // And it round-trips (the summary is cached for the widgets).
        let back = try JSONDecoder().decode(CRMAnalyticsSummary.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }
}
