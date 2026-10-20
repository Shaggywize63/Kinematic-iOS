//
//  AppLayoutTests.swift
//  KinematicTests
//
//  Client Management's module ticks and drag-and-drop layout reaching the app (contract: the backend's
//  docs/APP_LAYOUT_CONTRACT.md):
//    - `entitlements_strict` on the user: with it, `enabled_modules` / `enabled_packages` are the COMPLETE list (empty means
//      nothing); without it (older servers, platform users, Tata) the old "empty list = full access" reading is untouched
//    - `app_ui_config.layout`: decoding, the order of each container, the field-force bottom bar, the Home / Settings /
//      CRM More arrangements
//    - the CRM shell's main tabs and the gates that the bar's action tabs share with the side menu
//

import XCTest
@testable import Kinematic

final class AppLayoutTests: XCTestCase {

    // MARK: - helpers

    private func config(_ json: String) throws -> AppUiConfig {
        try JSONDecoder().decode(AppUiConfig.self, from: Data(json.utf8))
    }

    /// A user; `extra` is more JSON members, each starting with a comma.
    private func user(_ extra: String = "") throws -> User {
        let json = #"{"id":"u1","name":"Asha","role":"executive"\#(extra)}"#
        return try JSONDecoder().decode(User.self, from: Data(json.utf8))
    }

    private let userKey = "current_user"

    /// Runs `body` with `extra` as the signed-in user (put back exactly as it was afterwards — the session is a global).
    private func signedIn(_ extra: String, _ body: () throws -> Void) throws {
        let saved = UserDefaults.standard.data(forKey: userKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: userKey) }
            else { UserDefaults.standard.removeObject(forKey: userKey) }
        }
        Session.currentUser = try user(extra)
        try body()
    }

    // MARK: - entitlements_strict

    func testTheStrictFlagIsDecodedAndDefaultsToFalse() throws {
        XCTAssertFalse(try user().entitlementsStrict)
        XCTAssertTrue(try user(#","entitlements_strict":true"#).entitlementsStrict)
        XCTAssertFalse(try user(#","entitlements_strict":false"#).entitlementsStrict)
        // anything that is not a boolean reads as "not strict" and never costs the rest of the user
        let odd = try user(#","entitlements_strict":"yes","enabled_modules":["leave"]"#)
        XCTAssertFalse(odd.entitlementsStrict)
        XCTAssertEqual(odd.enabledModules, ["leave"])
        XCTAssertFalse(try user(#","entitlements_strict":null"#).entitlementsStrict)
    }

    func testTheStrictFlagSurvivesTheUserBeingStoredWithTheSession() throws {
        let u = try user(#","entitlements_strict":true,"enabled_modules":["leave"],"enabled_packages":["field_force"]"#)
        let back = try JSONDecoder().decode(User.self, from: JSONEncoder().encode(u))
        XCTAssertTrue(back.entitlementsStrict)
        XCTAssertEqual(back.enabledModules, ["leave"])
        // a session stored by an older build has no flag at all and reads as lenient
        XCTAssertFalse(try JSONDecoder().decode(User.self, from: JSONEncoder().encode(try user())).entitlementsStrict)
    }

    func testWithoutTheFlagAnEmptyListStillMeansFullAccess() throws {
        let legacy = try user()
        XCTAssertTrue(legacy.isLegacySession)
        XCTAssertTrue(legacy.hasModule("anything"))
        XCTAssertTrue(legacy.hasPackage("crm"))
        XCTAssertTrue(legacy.hasFieldForce)
        XCTAssertFalse(legacy.isCrmOnly)
        // an explicit false is the same as absent
        let notStrict = try user(#","entitlements_strict":false,"enabled_modules":[],"enabled_packages":[]"#)
        XCTAssertTrue(notStrict.isLegacySession)
        XCTAssertTrue(notStrict.hasModule("leave"))
    }

    func testWithTheFlagAnEmptyListMeansNothing() throws {
        let none = try user(#","entitlements_strict":true,"enabled_modules":[],"enabled_packages":[]"#)
        XCTAssertFalse(none.isLegacySession)
        XCTAssertFalse(none.hasModule("leave"))
        XCTAssertFalse(none.hasPackage("crm"))
        XCTAssertFalse(none.hasCrm)
        XCTAssertFalse(none.hasFieldForce)
        XCTAssertFalse(none.hasDistribution)
        // lists missing altogether are empty lists
        let missing = try user(#","entitlements_strict":true"#)
        XCTAssertFalse(missing.hasModule("leave"))
        XCTAssertFalse(missing.hasFieldForce)
    }

    func testWithTheFlagOnlyTheListedModulesAndPackagesCount() throws {
        let u = try user(#","entitlements_strict":true,"enabled_modules":["leave","broadcast"],"enabled_packages":["field_force"]"#)
        XCTAssertTrue(u.hasModule("leave"))
        XCTAssertTrue(u.hasModule("broadcast"))
        XCTAssertFalse(u.hasModule("timeline"))
        XCTAssertTrue(u.hasFieldForce)
        XCTAssertFalse(u.hasCrm)
        XCTAssertFalse(u.hasDistribution)
    }

    func testAListedClientReadsTheSameWithOrWithoutTheFlag() throws {
        // A non-empty list was never lenient, so the flag changes nothing for it.
        let body = #","enabled_modules":["leave"],"enabled_packages":["crm"]"#
        let lenient = try user(body)
        let strict = try user(#","entitlements_strict":true"# + body)
        for id in ["leave", "broadcast", "timeline"] { XCTAssertEqual(lenient.hasModule(id), strict.hasModule(id)) }
        for pkg in ["crm", "field_force", "distribution"] { XCTAssertEqual(lenient.hasPackage(pkg), strict.hasPackage(pkg)) }
        XCTAssertEqual(lenient.isCrmOnly, strict.isCrmOnly)
        XCTAssertTrue(strict.isCrmOnly)
    }

    func testAStrictClientWithNoPackagesIsNotMistakenForCrmOnly() throws {
        XCTAssertFalse(try user(#","entitlements_strict":true"#).isCrmOnly)
    }

    func testStrictAllowsOnlyBitesUnderTheFlag() throws {
        // For a screen that had no module check: lenient (or no flag) = shown, strict = needs its module.
        XCTAssertTrue(try user().strictAllows("crm_leads"))
        XCTAssertTrue(try user(#","enabled_modules":["leave"]"#).strictAllows("crm_leads"))
        XCTAssertTrue(try user(#","entitlements_strict":false,"enabled_modules":[]"#).strictAllows("crm_leads"))
        XCTAssertFalse(try user(#","entitlements_strict":true"#).strictAllows("crm_leads"))
        XCTAssertFalse(try user(#","entitlements_strict":true,"enabled_modules":["crm_deals"]"#).strictAllows("crm_leads"))
        XCTAssertTrue(try user(#","entitlements_strict":true,"enabled_modules":["crm_leads"]"#).strictAllows("crm_leads"))
    }

    func testTheSheetGateFollowsTheStrictReading() throws {
        // .broadcast needs the field_force package; a legacy session opens it, a strict empty one does not.
        XCTAssertTrue(SecondaryRoute.broadcast.isAvailable(for: try user()))
        XCTAssertFalse(SecondaryRoute.broadcast.isAvailable(for: try user(#","entitlements_strict":true"#)))
        XCTAssertTrue(SecondaryRoute.broadcast.isAvailable(for: try user(#","entitlements_strict":true,"enabled_packages":["field_force"]"#)))
        // .vanLoad needs its module
        XCTAssertTrue(SecondaryRoute.vanLoad.isAvailable(for: try user()))
        XCTAssertFalse(SecondaryRoute.vanLoad.isAvailable(for: try user(#","entitlements_strict":true"#)))
        XCTAssertTrue(SecondaryRoute.vanLoad.isAvailable(for: try user(#","entitlements_strict":true,"enabled_modules":["distribution_van"]"#)))
    }

    // MARK: - decoding app_ui_config.layout

    func testAConfigWithoutALayoutHasNone() throws {
        let c = try config(#"{"tabs":{"new_form":false}}"#)
        XCTAssertNil(c.layout)
        XCTAssertEqual(c.layoutOrder("menu"), [])
        XCTAssertEqual(try user().layoutOrder("tabs"), [])
        XCTAssertEqual(try user(#","app_ui_config":{}"#).layoutOrder("tabs"), [])
    }

    func testEveryContainerOfTheLayoutIsRead() throws {
        let c = try config("""
        {"layout":{"tabs":["attendance","route_plan","leave","activity"],"menu":["profile","broadcast","log_visit"],
                   "settings":["appearance","app_lock"],"crm_more":["pipeline","accounts"],"home":["stores","visited"]}}
        """)
        XCTAssertEqual(c.layoutOrder("tabs"), ["attendance", "route_plan", "leave", "activity"])
        XCTAssertEqual(c.layoutOrder("menu"), ["profile", "broadcast", "log_visit"])
        XCTAssertEqual(c.layoutOrder("settings"), ["appearance", "app_lock"])
        XCTAssertEqual(c.layoutOrder("crm_more"), ["pipeline", "accounts"])
        XCTAssertEqual(c.layoutOrder("home"), ["stores", "visited"])
        XCTAssertEqual(c.layoutOrder("nonsense"), [])
    }

    func testAContainerTheAdminNeverTouchedIsAbsent() throws {
        let c = try config(#"{"layout":{"menu":["broadcast"]}}"#)
        XCTAssertEqual(c.layout?.menu, ["broadcast"])
        XCTAssertNil(c.layout?.tabs)
        XCTAssertNil(c.layout?.crmMore)
        XCTAssertEqual(c.layoutOrder("tabs"), [])
    }

    func testTheLayoutIsReadForgivingly() throws {
        // non-strings skipped, blanks and repeats dropped (first mention wins), ids trimmed
        let c = try config(#"{"layout":{"menu":["a",3,null," b ","a","",{"x":1},"c"],"tabs":"attendance","home":null}}"#)
        XCTAssertEqual(c.layoutOrder("menu"), ["a", "b", "c"])
        // a container that is not a list reads as absent
        XCTAssertNil(c.layout?.tabs)
        XCTAssertNil(c.layout?.home)
    }

    func testAMalformedLayoutNeverCostsTheRestOfTheConfig() throws {
        let notAnObject = try config(#"{"tabs":{"new_form":false},"menu":{"leave":false},"layout":"attendance"}"#)
        XCTAssertNil(notAnObject.layout)
        XCTAssertEqual(notAnObject.tabs?["new_form"], false)
        XCTAssertEqual(notAnObject.menu?["leave"], false)

        let asList = try config(#"{"menu":{"leave":false},"layout":["attendance"]}"#)
        XCTAssertNil(asList.layout)
        XCTAssertEqual(asList.menu?["leave"], false)

        let u = try user(#","app_ui_config":{"settings":{"app_lock":false},"layout":42}"#)
        XCTAssertFalse(u.settingsVisible("app_lock"))
        XCTAssertEqual(u.layoutOrder("menu"), [])
    }

    func testTheLayoutDoesNotDisturbTheHideFlagsBesideIt() throws {
        let u = try user(#","app_ui_config":{"tabs":{"new_form":false},"labels":{"menu":{"leave":"Time off"}},"layout":{"menu":["leave"]}}"#)
        XCTAssertFalse(u.tabVisible("new_form"))
        XCTAssertEqual(u.label("menu", "leave", default: "Leave"), "Time off")
        XCTAssertEqual(u.layoutOrder("menu"), ["leave"])
    }

    func testTheLayoutSurvivesTheUserBeingStoredWithTheSession() throws {
        let u = try user(#","app_ui_config":{"layout":{"tabs":["leave","crm"],"crm_more":["reports"]}}"#)
        let back = try JSONDecoder().decode(User.self, from: JSONEncoder().encode(u))
        XCTAssertEqual(back.layoutOrder("tabs"), ["leave", "crm"])
        XCTAssertEqual(back.layoutOrder("crm_more"), ["reports"])
        XCTAssertEqual(back.layoutOrder("menu"), [])
    }

    // MARK: - order (every container)

    private func order(_ items: [String], _ listed: [String]) -> [String] {
        AppLayoutOrder.sorted(items, listed: listed, id: { $0 })
    }

    func testListedIdsComeFirstInTheListedOrderTheRestKeepTheirOrder() {
        XCTAssertEqual(order(["a", "b", "c", "d", "e"], ["d", "b"]), ["d", "b", "a", "c", "e"])
        XCTAssertEqual(order(["a", "b", "c"], ["c"]), ["c", "a", "b"])
        XCTAssertEqual(order(["a", "b", "c"], ["a", "b", "c"]), ["a", "b", "c"])
        XCTAssertEqual(order(["a", "b", "c"], ["c", "b", "a"]), ["c", "b", "a"])
    }

    func testNothingListedChangesNothing() {
        XCTAssertEqual(order(["a", "b", "c"], []), ["a", "b", "c"])
        XCTAssertEqual(order([], ["a"]), [])
        XCTAssertEqual(order(["a"], ["a"]), ["a"])
    }

    func testIdsListedButNotPresentAreIgnored() {
        // a hidden screen is simply not among the items; listing it moves nothing else
        XCTAssertEqual(order(["a", "b", "c"], ["zzz", "c"]), ["c", "a", "b"])
        XCTAssertEqual(order(["a", "b", "c"], ["zzz"]), ["a", "b", "c"])
    }

    func testARepeatedListedIdCountsOnceAtItsFirstMention() {
        XCTAssertEqual(order(["a", "b", "c"], ["c", "a", "c"]), ["c", "a", "b"])
        XCTAssertEqual(AppLayoutOrder.ranks(["x", "y", "x"]), ["x": 0, "y": 1])
    }

    func testTheSortIsStableForItemsThatAreNotListed() {
        let items = ["m", "n", "o", "p", "q", "r"]
        XCTAssertEqual(order(items, ["r", "p"]), ["r", "p", "m", "n", "o", "q"])
    }

    func testAGroupSitsWhereItsEarliestShownMemberSits() {
        let groups = [["a", "b"], ["c"], ["d", "e"]]
        let sorted = AppLayoutOrder.sortedGroups(groups, listed: ["e", "a"], ids: { $0 })
        XCTAssertEqual(sorted, [["d", "e"], ["a", "b"], ["c"]])
        // a group with no listed member is unlisted and keeps its place behind the listed ones
        XCTAssertEqual(AppLayoutOrder.sortedGroups(groups, listed: ["c"], ids: { $0 }), [["c"], ["a", "b"], ["d", "e"]])
        // a group with no members at all (an essential block) is unlisted too
        XCTAssertEqual(AppLayoutOrder.sortedGroups([["a"], [], ["b"]], listed: ["b"], ids: { $0 }), [["b"], ["a"], []])
    }

    func testTheClientFeaturesOrderReadsTheSignedInClientsList() throws {
        try signedIn(#","app_ui_config":{"layout":{"menu":["stock","leave"]}}"#) {
            XCTAssertEqual(ClientFeatures.layoutOrder("menu"), ["stock", "leave"])
            XCTAssertEqual(ClientFeatures.ordered(["leave", "profile", "stock"], section: "menu", id: { $0 }), ["stock", "leave", "profile"])
            // another container is untouched
            XCTAssertEqual(ClientFeatures.ordered(["leave", "profile", "stock"], section: "settings", id: { $0 }), ["leave", "profile", "stock"])
        }
        try signedIn("") {
            XCTAssertEqual(ClientFeatures.ordered(["leave", "profile", "stock"], section: "menu", id: { $0 }), ["leave", "profile", "stock"])
        }
    }

    // MARK: - bottom bar composition

    private func bar(_ listed: [String]?, allowing allowed: Set<String>? = nil) -> [String]? {
        BottomBarPlan.compose(layoutTabs: listed, isAllowed: { allowed?.contains($0) ?? true })
    }

    func testWithoutALayoutThereIsNoLaidOutBar() {
        XCTAssertNil(bar(nil))
        XCTAssertNil(bar([]))
    }

    func testTheBarIsTheListedTabsInTheirOrder() {
        XCTAssertEqual(bar(["attendance", "route_plan", "leave", "activity"]), ["attendance", "route_plan", "leave", "activity"])
        XCTAssertEqual(bar(["leave", "attendance"]), ["leave", "attendance"])
        XCTAssertEqual(bar(["crm"]), ["crm"])
    }

    func testATabWhoseGateIsClosedIsDropped() {
        let allowed: Set<String> = ["attendance", "leave", "crm"]
        XCTAssertEqual(bar(["attendance", "route_plan", "leave", "timeline", "crm"], allowing: allowed), ["attendance", "leave", "crm"])
    }

    func testAnEmptiedBarIsHomeOnlyNotTheBuiltInBar() {
        // A layout was made (non-empty list), every tab in it is closed: Home alone, not the old bar.
        XCTAssertEqual(bar(["route_plan", "timeline"], allowing: []), [])
        XCTAssertEqual(bar(["not_a_screen"]), [])
    }

    func testAtMostFourTabsFollowHome() {
        let many = ["attendance", "route_plan", "activity", "new_form", "expenses", "leave"]
        XCTAssertEqual(bar(many), ["attendance", "route_plan", "activity", "new_form"])
        // the limit counts what is left after the gates, not what was listed
        XCTAssertEqual(bar(many, allowing: ["route_plan", "activity", "new_form", "expenses", "leave"]),
                       ["route_plan", "activity", "new_form", "expenses"])
    }

    func testUnknownAndRepeatedIdsNeverReachTheBar() {
        XCTAssertEqual(bar(["leave", "leave", "bogus", "profile", "timeline"]), ["leave", "timeline"])
        // ids that are fine in the menu but cannot sit in the bar
        XCTAssertEqual(bar(["profile", "stock", "van_load"]), [])
    }

    func testEveryBarCapableIdIsKnown() {
        XCTAssertEqual(BottomBarPlan.capableIds.count, 14)
        XCTAssertEqual(Set(BottomBarPlan.capableIds).count, 14)
        for id in ["attendance", "route_plan", "activity", "new_form", "expenses", "leave", "timeline", "log_visit",
                   "broadcast", "notifications", "crm", "my_orders", "book_order", "collect_payment"] {
            XCTAssertTrue(BottomBarPlan.capableIds.contains(id), id)
        }
    }

    func testTheBarsOwnTabsAreNotActionTabs() {
        for id in ["attendance", "route_plan", "activity", "new_form", "expenses"] {
            XCTAssertFalse(BottomBarPlan.isActionTab(id), id)
            XCTAssertEqual(BottomBarPlan.flagSection(for: id), "tabs", id)
        }
        for id in ["leave", "timeline", "log_visit", "broadcast", "notifications", "crm", "my_orders", "book_order", "collect_payment"] {
            XCTAssertTrue(BottomBarPlan.isActionTab(id), id)
            XCTAssertEqual(BottomBarPlan.flagSection(for: id), "menu", id)
        }
        XCTAssertFalse(BottomBarPlan.isActionTab("profile"))
    }

    func testTabValuesAreUniqueAndTheOldOnesAreKept() {
        XCTAssertEqual(BottomBarPlan.tabValue(for: "attendance"), 1)
        XCTAssertEqual(BottomBarPlan.tabValue(for: "route_plan"), 2)
        XCTAssertEqual(BottomBarPlan.tabValue(for: "new_form"), 3)
        XCTAssertEqual(BottomBarPlan.tabValue(for: "expenses"), 4)
        let values = BottomBarPlan.capableIds.map { BottomBarPlan.tabValue(for: $0) }
        XCTAssertEqual(Set(values).count, values.count)
        XCTAssertFalse(values.contains(0))   // 0 is Home
    }

    func testChangingTheSelectedTab() {
        let bar = ["attendance", "leave", "crm"]
        XCTAssertEqual(BottomBarPlan.outcome(selected: 0, bar: bar), .keep)
        XCTAssertEqual(BottomBarPlan.outcome(selected: BottomBarPlan.tabValue(for: "attendance"), bar: bar), .keep)
        // an action tab opens its screen
        XCTAssertEqual(BottomBarPlan.outcome(selected: BottomBarPlan.tabValue(for: "leave"), bar: bar), .runAction("leave"))
        XCTAssertEqual(BottomBarPlan.outcome(selected: BottomBarPlan.tabValue(for: "crm"), bar: bar), .runAction("crm"))
        // a value no tab of this bar has: Route is not in it, so Home's "view all" lands on Home
        XCTAssertEqual(BottomBarPlan.outcome(selected: 2, bar: bar), .goHome)
        XCTAssertEqual(BottomBarPlan.outcome(selected: 99, bar: bar), .goHome)
        // Home only
        XCTAssertEqual(BottomBarPlan.outcome(selected: 1, bar: []), .goHome)
        XCTAssertEqual(BottomBarPlan.outcome(selected: 0, bar: []), .keep)
    }

    func testAScreenInTheBarLeavesTheSideMenu() {
        XCTAssertEqual(BottomBarPlan.menuIdsInBar(["leave", "crm", "attendance"]), ["leave", "crm", "attendance"])
        // the Activity tab shows the Activity Feed, so that menu entry goes
        XCTAssertEqual(BottomBarPlan.menuIdsInBar(["activity"]), ["activity_feed"])
        XCTAssertEqual(BottomBarPlan.menuIdsInBar(nil), [])
        XCTAssertEqual(BottomBarPlan.menuIdsInBar([]), [])
    }

    // MARK: - the bar through the signed-in client's gates

    func testNoLayoutLeavesTheBuiltInBarAlone() throws {
        try signedIn(#","enabled_modules":["attendance"],"enabled_packages":["field_force"],"app_ui_config":{"tabs":{"new_form":false}}"#) {
            XCTAssertNil(ClientFeatures.layoutBarTabs())
        }
        try signedIn(#","app_ui_config":{"layout":{"menu":["leave"]}}"#) {
            XCTAssertNil(ClientFeatures.layoutBarTabs(), "a menu-only layout does not lay out a bar")
        }
        try signedIn(#","app_ui_config":{"layout":{"tabs":[]}}"#) {
            XCTAssertNil(ClientFeatures.layoutBarTabs(), "an empty tabs list is no bar")
        }
        try signedIn("") {
            XCTAssertNil(ClientFeatures.layoutBarTabs())
        }
    }

    func testEachTabIsFilteredByItsOwnGateAndHideFlag() throws {
        let json = """
        ,"entitlements_strict":true,"enabled_modules":["attendance","leave","broadcast"],"enabled_packages":["field_force"],
         "app_ui_config":{"tabs":{"route_plan":false},"menu":{"log_visit":false},
         "layout":{"tabs":["attendance","route_plan","leave","timeline","log_visit","broadcast","crm"]}}
        """
        try signedIn(json) {
            // route_plan: hide flag. timeline: no module. log_visit: hide flag. crm: no CRM package.
            XCTAssertEqual(ClientFeatures.layoutBarTabs(), ["attendance", "leave", "broadcast"])
            XCTAssertTrue(ClientFeatures.barItemAllowed("attendance"))
            XCTAssertFalse(ClientFeatures.barItemAllowed("route_plan"))
            XCTAssertFalse(ClientFeatures.barItemAllowed("timeline"))
            XCTAssertFalse(ClientFeatures.barItemAllowed("log_visit"))
            XCTAssertFalse(ClientFeatures.barItemAllowed("crm"))
            XCTAssertFalse(ClientFeatures.barItemAllowed("not_a_tab"))
        }
    }

    func testAnActionTabHasExactlyItsSideMenuEntrysGate() throws {
        let json = #","entitlements_strict":true,"enabled_modules":["broadcast","timeline"],"enabled_packages":["field_force","crm"],"app_ui_config":{"layout":{"tabs":["broadcast","timeline","crm","leave","notifications","book_order","my_orders","collect_payment","log_visit"]}}"#
        try signedIn(json) {
            for id in ["broadcast", "timeline", "crm", "leave", "notifications", "book_order", "my_orders", "collect_payment", "log_visit"] {
                XCTAssertEqual(ClientFeatures.barItemAllowed(id), ClientFeatures.menuEntryAllowed(id), id)
            }
            // distribution is not owned: its three screens are closed in both places
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("book_order"))
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("my_orders"))
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("collect_payment"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("broadcast"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("timeline"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("crm"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("notifications"))
            XCTAssertEqual(ClientFeatures.layoutBarTabs(), ["broadcast", "timeline", "crm", "leave"])
        }
    }

    func testALegacySessionKeepsItsLenientGatesInTheBar() throws {
        // No entitlement data at all (older server): packages and `hasModule` are open; the strict-only modules
        // (timeline) still need the module in the list.
        try signedIn(#","app_ui_config":{"layout":{"tabs":["crm","timeline","leave","book_order","attendance"]}}"#) {
            XCTAssertEqual(ClientFeatures.layoutBarTabs(), ["crm", "leave", "book_order", "attendance"])
        }
    }

    func testAHiddenEntryStaysOutOfTheBarAndTheMenu() throws {
        try signedIn(#","app_ui_config":{"menu":{"leave":false},"layout":{"tabs":["leave","crm"],"menu":["leave"]}}"#) {
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("leave"))
            XCTAssertEqual(ClientFeatures.layoutBarTabs(), ["crm"])
        }
    }

    func testExpensesInTheBarNeedsTheModuleNotTheOptInSwitch() throws {
        // The layout is the opt-in (`tabs.expenses == true` is not needed); the module still is.
        try signedIn(#","enabled_modules":["field_expenses"],"enabled_packages":["field_force"],"app_ui_config":{"layout":{"tabs":["expenses"]}}"#) {
            XCTAssertEqual(ClientFeatures.layoutBarTabs(), ["expenses"])
        }
        try signedIn(#","enabled_modules":["attendance"],"enabled_packages":["field_force"],"app_ui_config":{"layout":{"tabs":["expenses"]}}"#) {
            XCTAssertEqual(ClientFeatures.layoutBarTabs(), [])
        }
        // the hide flag still wins
        try signedIn(#","enabled_modules":["field_expenses"],"enabled_packages":["field_force"],"app_ui_config":{"tabs":{"expenses":false},"layout":{"tabs":["expenses"]}}"#) {
            XCTAssertEqual(ClientFeatures.layoutBarTabs(), [])
        }
    }

    func testTheBuiltInExpensesTabRuleIsUnchanged() throws {
        let on = try config(#"{"tabs":{"expenses":true}}"#)
        XCTAssertTrue(ClientFeatures.expensesTabShown(showsExpenses: true, config: on))
        XCTAssertFalse(ClientFeatures.expensesTabShown(showsExpenses: true, config: try config("{}")))
    }

    // MARK: - what the bar draws

    func testEveryBarCapableIdHasATitleAndASymbol() throws {
        try signedIn("") {
            for id in BottomBarPlan.capableIds {
                let spec = BottomBarPlan.spec(for: id)
                XCTAssertNotNil(spec, id)
                XCTAssertFalse(spec?.title.isEmpty ?? true, id)
                XCTAssertFalse(spec?.icon.isEmpty ?? true, id)
            }
            XCTAssertNil(BottomBarPlan.spec(for: "profile"))
        }
    }

    func testEveryActionTabIsInTheSharedActionTable() {
        let actionIds = BottomBarPlan.capableIds.filter { BottomBarPlan.isActionTab($0) }
        XCTAssertEqual(Set(NavActions.all.map { $0.id }), Set(actionIds))
        XCTAssertEqual(NavActions.all.count, Set(NavActions.all.map { $0.id }).count)
    }

    func testAnActionTabIsNamedAndDrawnLikeItsMenuEntry() throws {
        try signedIn(#","app_ui_config":{"labels":{"menu":{"leave":"Time off","crm":"Sales"}}}"#) {
            // a rename (labels.menu.<id>) reaches the bar
            XCTAssertEqual(BottomBarPlan.spec(for: "leave")?.title, "Time off")
            XCTAssertEqual(BottomBarPlan.spec(for: "crm")?.title, "Sales")
            XCTAssertEqual(BottomBarPlan.spec(for: "leave")?.icon, "calendar.badge.clock")
            XCTAssertEqual(BottomBarPlan.spec(for: "crm")?.icon, "person.2.crop.square.stack.fill")
            // unrenamed: the menu's own wording
            XCTAssertEqual(BottomBarPlan.spec(for: "log_visit")?.title, "Visit Log")
            XCTAssertEqual(BottomBarPlan.spec(for: "broadcast")?.title, "Broadcasts")
            XCTAssertEqual(BottomBarPlan.spec(for: "my_orders")?.icon, "cart.fill")
        }
    }

    func testTheBarsOwnTabsKeepTheirTabLabelsAndRenames() throws {
        try signedIn("") {
            XCTAssertEqual(BottomBarPlan.spec(for: "attendance")?.title, "Attendance")
            XCTAssertEqual(BottomBarPlan.spec(for: "route_plan")?.title, "Route")
            XCTAssertEqual(BottomBarPlan.spec(for: "new_form")?.title, "New")
            XCTAssertEqual(BottomBarPlan.spec(for: "expenses")?.icon, "receipt")
        }
        try signedIn(#","app_ui_config":{"labels":{"tabs":{"route_plan":"Beat"}}}"#) {
            XCTAssertEqual(BottomBarPlan.spec(for: "route_plan")?.title, "Beat")
        }
    }

    func testEachActionOpensItsMenuEntrysDestination() {
        func route(_ id: String) -> SecondaryRoute? {
            if case .route(let r)? = NavActions.action(id)?.target { return r }
            return nil
        }
        XCTAssertEqual(route("book_order"), .orderCart)
        XCTAssertEqual(route("collect_payment"), .paymentCollect)
        XCTAssertEqual(route("my_orders"), .orderHistory)
        XCTAssertEqual(route("leave"), .leave)
        XCTAssertEqual(route("timeline"), .timeline)
        XCTAssertEqual(route("broadcast"), .broadcast)
        XCTAssertEqual(route("notifications"), .notifications)
        XCTAssertEqual(route("log_visit"), .visitlog)
        if case .crm? = NavActions.action("crm")?.target {} else { XCTFail("CRM opens the CRM module") }
    }

    // MARK: - the side menu's gates

    func testTheMenuEntriesKeepTheirGatesAndHideFlags() throws {
        try signedIn("") {
            // a legacy session: everything with only a hide flag is open; the strict-only modules need the module
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("profile"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("notifications"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("leaderboard"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("book_order"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("van_load"))
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("timeline"))
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("expenses"))
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("stock_batches"))
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("planogram"))
        }
        try signedIn(#","app_ui_config":{"menu":{"notifications":false,"profile":false}}"#) {
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("notifications"))
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("profile"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("learning_hub"))
        }
    }

    func testStrictClientsLoseTheEntriesTheirPackagesAndModulesDoNotCover() throws {
        try signedIn(#","entitlements_strict":true,"enabled_modules":["grievances"],"enabled_packages":["field_force"]"#) {
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("grievance"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("leaderboard"))      // field_force
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("broadcast"))       // module not ticked
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("crm"))             // package not owned
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("book_order"))      // distribution not owned
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("van_load"))
        }
        try signedIn(#","entitlements_strict":true"#) {
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("leaderboard"))
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("grievance"))
            XCTAssertFalse(ClientFeatures.menuEntryAllowed("crm"))
            // the essentials and the hide-flag-only entries are still there; the server's flags take the rest
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("profile"))
            XCTAssertTrue(ClientFeatures.menuEntryAllowed("notifications"))
        }
    }

    // MARK: - the CRM shell's main tabs

    func testTheCrmTabsAreAlwaysShownWithoutTheStrictFlag() throws {
        for extra in ["", #","enabled_modules":[],"enabled_packages":["crm"]"#, #","enabled_modules":["crm_leads"],"enabled_packages":["crm"]"#,
                      #","entitlements_strict":false,"enabled_modules":["leave"]"#] {
            try signedIn(extra) {
                XCTAssertTrue(ClientFeatures.showsCrmLeadsTab, extra)
                XCTAssertTrue(ClientFeatures.showsCrmDealsTab, extra)
                XCTAssertTrue(ClientFeatures.showsCrmDashboardTab, extra)
                XCTAssertTrue(ClientFeatures.showsCrmActivities, extra)
            }
        }
    }

    func testUnderTheStrictFlagEachCrmTabNeedsItsModule() throws {
        try signedIn(#","entitlements_strict":true,"enabled_modules":["crm_leads","crm_activities"],"enabled_packages":["crm"]"#) {
            XCTAssertTrue(ClientFeatures.showsCrmLeadsTab)
            XCTAssertTrue(ClientFeatures.showsCrmActivities)
            XCTAssertFalse(ClientFeatures.showsCrmDealsTab)
            XCTAssertFalse(ClientFeatures.showsCrmDashboardTab)
        }
        try signedIn(#","entitlements_strict":true,"enabled_modules":["crm_deals","crm_dashboard"],"enabled_packages":["crm"]"#) {
            XCTAssertFalse(ClientFeatures.showsCrmLeadsTab)
            XCTAssertFalse(ClientFeatures.showsCrmActivities)
            XCTAssertTrue(ClientFeatures.showsCrmDealsTab)
            XCTAssertTrue(ClientFeatures.showsCrmDashboardTab)
        }
        // strict and nothing ticked: no module tab at all (Home and More are essential and not gated here)
        try signedIn(#","entitlements_strict":true,"enabled_packages":["crm"]"#) {
            XCTAssertFalse(ClientFeatures.showsCrmLeadsTab)
            XCTAssertFalse(ClientFeatures.showsCrmDealsTab)
            XCTAssertFalse(ClientFeatures.showsCrmDashboardTab)
            XCTAssertFalse(ClientFeatures.showsCrmActivities)
        }
    }

    func testNoSessionShowsTheCrmTabs() {
        // No user at all (a logged-out preview): nothing is taken away, as for every other gate.
        let saved = UserDefaults.standard.data(forKey: userKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: userKey) }
            else { UserDefaults.standard.removeObject(forKey: userKey) }
        }
        UserDefaults.standard.removeObject(forKey: userKey)
        XCTAssertTrue(ClientFeatures.showsCrmLeadsTab)
        XCTAssertTrue(ClientFeatures.strictAllows("anything"))
    }

    // MARK: - Home cards

    func testHomeIsUnchangedWithoutALayout() {
        XCTAssertEqual(HomeLayout.blocks(listed: []), [.tiles(["stores", "visited", "forms"]), .myTargets, .session, .route])
        // cards the layout does not know (open_volume lives on the CRM dashboard) change nothing
        XCTAssertEqual(HomeLayout.blocks(listed: ["open_volume"]), HomeLayout.blocks(listed: []))
    }

    func testHomeCardsFollowTheLayout() {
        XCTAssertEqual(HomeLayout.blocks(listed: ["todays_route"]),
                       [.route, .tiles(["stores", "visited", "forms"]), .myTargets, .session])
        XCTAssertEqual(HomeLayout.blocks(listed: ["forms", "stores"]),
                       [.tiles(["forms", "stores", "visited"]), .myTargets, .session, .route])
        XCTAssertEqual(HomeLayout.blocks(listed: ["my_targets", "visited"]),
                       [.myTargets, .tiles(["visited", "stores", "forms"]), .session, .route])
    }

    func testTilesSeparatedByAnotherCardFormTheirOwnRuns() {
        XCTAssertEqual(HomeLayout.blocks(listed: ["stores", "my_targets", "visited"]),
                       [.tiles(["stores"]), .myTargets, .tiles(["visited", "forms"]), .session, .route])
    }

    func testTheFixedCardsStayBehindEverythingListed() {
        // `session` is never listed, so it is behind every listed card and keeps its place among the unlisted ones
        XCTAssertEqual(HomeLayout.blocks(listed: ["todays_route", "my_targets"]),
                       [.route, .myTargets, .tiles(["stores", "visited", "forms"]), .session])
        XCTAssertEqual(HomeLayout.defaultOrder, ["stores", "visited", "forms", "my_targets", "session", "todays_route"])
    }

    // MARK: - Settings blocks

    func testSettingsIsUnchangedWithoutALayout() {
        XCTAssertEqual(SettingsLayout.blocks(listed: [], isShown: { _ in true }),
                       ["appearance", "modules", "security", "account", "rate_app", "about"])
    }

    func testSettingsBlocksFollowTheLayout() {
        XCTAssertEqual(SettingsLayout.blocks(listed: ["about", "app_lock"], isShown: { _ in true }),
                       ["about", "security", "appearance", "modules", "account", "rate_app"])
        // either row of the MODULES block moves the block
        XCTAssertEqual(SettingsLayout.blocks(listed: ["face_enrollment"], isShown: { _ in true }).first, "modules")
        XCTAssertEqual(SettingsLayout.blocks(listed: ["crm_only_mode"], isShown: { _ in true }).first, "modules")
        XCTAssertEqual(SettingsLayout.blocks(listed: ["rate_app"], isShown: { _ in true }).first, "rate_app")
    }

    func testAHiddenSettingsRowDoesNotPullItsBlockUp() {
        // face_enrollment is listed first but not shown (no module); the MODULES block still has crm_only_mode, which is not listed
        let shown: (String) -> Bool = { $0 != "face_enrollment" }
        XCTAssertEqual(SettingsLayout.blocks(listed: ["face_enrollment", "about"], isShown: shown),
                       ["about", "appearance", "modules", "security", "account", "rate_app"])
    }

    func testTheAccountBlockStaysBehindWhatIsListed() {
        XCTAssertEqual(SettingsLayout.blocks(listed: ["about"], isShown: { _ in true }).last, "rate_app")
        XCTAssertEqual(SettingsLayout.members(of: "account"), [])
        XCTAssertEqual(SettingsLayout.members(of: "security"), ["app_lock"])
        XCTAssertEqual(SettingsLayout.members(of: "modules"), ["crm_only_mode", "face_enrollment"])
    }

    // MARK: - CRM More

    private func moreIds(_ sections: [CRMMoreLayout.MoreSection]) -> [String] { sections.map { $0.id } }

    func testCrmMoreIsUnchangedWithoutALayout() {
        let all = CRMMoreLayout.ordered(listed: [], isShown: { _ in true })
        XCTAssertEqual(all, CRMMoreLayout.defaultSections)
        XCTAssertEqual(moreIds(all), ["records", "field_visits", "field", "workplace", "expenses", "insights"])
    }

    func testRecordsAndInsightsKeepTheirHeaderWhenEmptyTheOthersGo() {
        let none = CRMMoreLayout.ordered(listed: [], isShown: { _ in false })
        XCTAssertEqual(moreIds(none), ["records", "insights"])
        XCTAssertEqual(none.map { $0.rows }, [[], []])
    }

    func testOnlyShownRowsAreKeptAndEmptyOptionalSectionsDrop() {
        let shown: Set<String> = ["pipeline", "reports", "leave"]
        let s = CRMMoreLayout.ordered(listed: [], isShown: { shown.contains($0) })
        XCTAssertEqual(moreIds(s), ["records", "workplace", "insights"])
        XCTAssertEqual(s[0].rows, ["pipeline"])
        XCTAssertEqual(s[2].rows, ["reports"])
    }

    func testASectionMovesAsAUnitToItsEarliestListedRow() {
        let s = CRMMoreLayout.ordered(listed: ["reports", "pipeline"], isShown: { _ in true })
        XCTAssertEqual(moreIds(s), ["insights", "records", "field_visits", "field", "workplace", "expenses"])
        // rows inside follow the list too, the rest keep their order
        XCTAssertEqual(s[0].rows, ["reports", "dashboard", "lead_analytics"])
        XCTAssertEqual(s[1].rows, ["pipeline", "accounts", "products", "custom_objects"])
    }

    func testAnApprovalsRowStaysBehindItsExpensesRow() {
        let s = CRMMoreLayout.ordered(listed: ["expenses"], isShown: { _ in true })
        XCTAssertEqual(moreIds(s).first, "expenses")
        XCTAssertEqual(s[0].rows, ["expenses", "expense_approvals"])
    }

    func testAHiddenListedRowDoesNotPullItsSectionUp() {
        // `nearest_leads` is listed first but hidden; its section is gone and nothing else moves
        let s = CRMMoreLayout.ordered(listed: ["nearest_leads", "reports"], isShown: { $0 != "nearest_leads" })
        XCTAssertEqual(moreIds(s), ["insights", "records", "field_visits", "workplace", "expenses"])
        // a hidden member does not pull a section that still has other shown rows
        let t = CRMMoreLayout.ordered(listed: ["accounts", "reports"], isShown: { $0 != "accounts" })
        XCTAssertEqual(moreIds(t).first, "insights")
    }
}
