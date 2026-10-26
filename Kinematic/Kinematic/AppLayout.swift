import Foundation

// App layout — the result of drag and drop in Client Management (`app_ui_config.layout`).
//
// Everything in this file is pure (no session, no SwiftUI) so it can be unit-tested on its own; the views feed it the
// screens they would show anyway and draw what comes back. The wire contract is the backend's
// docs/APP_LAYOUT_CONTRACT.md §2:
//
//   "layout": { "tabs": [...], "menu": [...], "settings": [...], "crm_more": [...], "home": [...] }
//
// Every list holds the same ids as the matching hide flags (`menu` / `tabs` / `settings` / `crm_more` / `home`). The layout
// is additive: an older server sends none and every container keeps its built-in order and the built-in bottom bar.

// MARK: - The layout itself (decoding)

struct AppLayout: Codable, Equatable {
    /// Screens in the field-force bottom bar after Home, in order. Absent or empty = the built-in bar.
    let tabs: [String]?
    let menu: [String]?
    let settings: [String]?
    let crmMore: [String]?
    let home: [String]?

    enum CodingKeys: String, CodingKey { case tabs, menu, settings, home; case crmMore = "crm_more" }

    init(tabs: [String]? = nil, menu: [String]? = nil, settings: [String]? = nil, crmMore: [String]? = nil, home: [String]? = nil) {
        self.tabs = tabs
        self.menu = menu
        self.settings = settings
        self.crmMore = crmMore
        self.home = home
    }

    /// Each list is read forgivingly: an entry that is not a string is skipped, blanks and repeats are dropped (the first
    /// mention counts), and a list that is not an array reads as absent — so whatever a container holds, it can never make
    /// the rest of the config (and so every hide flag) fail to load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tabs = AppLayout.readIds(c, .tabs)
        menu = AppLayout.readIds(c, .menu)
        settings = AppLayout.readIds(c, .settings)
        crmMore = AppLayout.readIds(c, .crmMore)
        home = AppLayout.readIds(c, .home)
    }

    /// One list entry: a string, or nothing.
    private struct LenientId: Decodable {
        let value: String?
        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            value = try? single.decode(String.self)
        }
    }

    private static func readIds(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String]? {
        guard let raw = try? c.decode([LenientId].self, forKey: key) else { return nil }
        return cleaned(raw.compactMap { $0.value })
    }

    /// Trimmed, no blanks, no repeats (the first mention wins).
    static func cleaned(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in ids {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty || seen.contains(id) { continue }
            seen.insert(id)
            out.append(id)
        }
        return out
    }

    /// The listed ids of one container (`tabs`, `menu`, `settings`, `crm_more`, `home`); empty when the admin never touched it.
    func order(for section: String) -> [String] {
        switch section {
        case "tabs":     return tabs ?? []
        case "menu":     return menu ?? []
        case "settings": return settings ?? []
        case "crm_more": return crmMore ?? []
        case "home":     return home ?? []
        default:         return []
        }
    }
}

// MARK: - Order (every container)

enum AppLayoutOrder {
    /// Where each listed id sits (the first mention counts).
    static func ranks(_ listed: [String]) -> [String: Int] {
        var out: [String: Int] = [:]
        for (index, id) in listed.enumerated() where out[id] == nil { out[id] = index }
        return out
    }

    /// Stable sort: the listed ids first, in the listed order; everything not listed keeps its default relative order after
    /// them. Ids listed but not present are ignored, so a hidden or unknown id changes nothing for the rest.
    static func sorted<T>(_ items: [T], listed: [String], id: (T) -> String) -> [T] {
        sortedGroups(items, listed: listed, ids: { [id($0)] })
    }

    /// The same rule for items that stand for several ids (a Settings block holding two rows, a CRM More section): an item
    /// sits where its earliest listed id sits and an item with no listed id counts as unlisted. Pass only the ids that are
    /// actually shown — a hidden member must not pull its group up.
    static func sortedGroups<T>(_ items: [T], listed: [String], ids: (T) -> [String]) -> [T] {
        if listed.isEmpty || items.count < 2 { return items }
        let rank = ranks(listed)
        var keyed: [(offset: Int, rank: Int, item: T)] = []
        for (offset, item) in items.enumerated() {
            let best = ids(item).compactMap { rank[$0] }.min() ?? Int.max
            keyed.append((offset: offset, rank: best, item: item))
        }
        keyed.sort { a, b in a.rank != b.rank ? a.rank < b.rank : a.offset < b.offset }
        return keyed.map { $0.item }
    }
}

// MARK: - Bottom bar (field-force shell)

enum BottomBarPlan {
    /// Screens that may sit in the bar after Home (contract §2). `attendance` / `route_plan` / `activity` / `new_form` /
    /// `expenses` are the bar's own tabs; every other id is an action tab that opens the same screen as its side-menu entry.
    static let capableIds: [String] = [
        "attendance", "route_plan", "activity", "new_form", "expenses", "leave", "timeline", "log_visit",
        "broadcast", "notifications", "crm", "my_orders", "book_order", "collect_payment",
    ]
    /// Bar ids whose hide flag lives in `app_ui_config.tabs` (the bar's own tabs); the others use their `menu` flag.
    static let ownTabIds: Set<String> = ["attendance", "route_plan", "activity", "new_form", "expenses"]
    /// Home plus this many more (the bar fits five).
    static let maxExtraTabs = 4

    /// The hide-flag section that governs a bar id.
    static func flagSection(for id: String) -> String { ownTabIds.contains(id) ? "tabs" : "menu" }

    /// True for the ids that open a screen instead of switching to a tab of their own.
    static func isActionTab(_ id: String) -> Bool { capableIds.contains(id) && !ownTabIds.contains(id) }

    /// The bar the admin laid out: Home + `layoutTabs`, in order, keeping only bar-capable ids whose own gate (`isAllowed`:
    /// module, package, tenant rules and hide flag) is open, no repeats, at most `maxExtraTabs`. Returns nil when no bar was
    /// laid out (absent or empty list) — the built-in bar then applies unchanged. A laid-out bar that filters down to nothing
    /// is `[]` (Home only), not nil.
    static func compose(layoutTabs: [String]?, isAllowed: (String) -> Bool) -> [String]? {
        guard let listed = layoutTabs, !listed.isEmpty else { return nil }
        var out: [String] = []
        for id in AppLayout.cleaned(listed) where capableIds.contains(id) && isAllowed(id) {
            out.append(id)
            if out.count == maxExtraTabs { break }
        }
        return out
    }

    /// The `TabView` selection value of a bar id (Home is 0). The five own tabs keep the numbers the rest of the app already
    /// uses (Attendance 1, Route 2, New 3, Expenses 4); the action tabs and Activity get numbers of their own.
    static func tabValue(for id: String) -> Int {
        switch id {
        case "attendance": return 1
        case "route_plan": return 2
        case "new_form":   return 3
        case "expenses":   return 4
        case "activity":   return 5
        default:
            let index = capableIds.firstIndex(of: id) ?? 0
            return 10 + index
        }
    }

    /// What a change of the selected tab means for a laid-out bar.
    enum SelectionOutcome: Equatable {
        /// A tab of the bar (or Home): leave it selected.
        case keep
        /// An action tab: open this screen and put the previous tab back.
        case runAction(String)
        /// A value no tab of this bar has (e.g. `selectedTab = 2` for Route when Route is not in the bar): go Home.
        case goHome
    }

    static func outcome(selected: Int, bar: [String]) -> SelectionOutcome {
        if selected == 0 { return .keep }
        guard let id = bar.first(where: { tabValue(for: $0) == selected }) else { return .goHome }
        return isActionTab(id) ? .runAction(id) : .keep
    }

    /// The side-menu id of the entry a bar tab replaces (a screen in the bar is not repeated in the menu). Almost always the
    /// same id; the Activity tab shows the Activity Feed.
    static func menuId(replacedBy barId: String) -> String { barId == "activity" ? "activity_feed" : barId }

    /// Side-menu ids to leave out because the bar already shows them.
    static func menuIdsInBar(_ bar: [String]?) -> Set<String> {
        Set((bar ?? []).map { menuId(replacedBy: $0) })
    }
}

// MARK: - Field-force Home cards

/// One piece of the field-force Home screen below the fixed header cards, in the order it is drawn.
enum HomeBlock: Hashable {
    /// Stat tiles (`stores`, `visited`, `forms`) that sit next to each other: the first two share a row, any third is full width.
    case tiles([String])
    case myTargets
    /// The cards that are not admin-ordered (session timer, travel prompt, broadcast) — they keep their place after My targets.
    case session
    case route
}

enum HomeLayout {
    /// The Home cards in the order they are drawn today. `session` stands for the fixed cards between My targets and Today's
    /// route; it is never listed by a layout, so it simply stays behind whatever is listed.
    static let defaultOrder: [String] = ["stores", "visited", "forms", "my_targets", "session", "todays_route"]

    static func blocks(listed: [String]) -> [HomeBlock] {
        let ordered = AppLayoutOrder.sorted(defaultOrder, listed: listed, id: { $0 })
        var out: [HomeBlock] = []
        var run: [String] = []
        func flush() {
            if !run.isEmpty { out.append(.tiles(run)); run = [] }
        }
        for id in ordered {
            switch id {
            case "stores", "visited", "forms": run.append(id)
            case "my_targets":                 flush(); out.append(.myTargets)
            case "session":                    flush(); out.append(.session)
            default:                           flush(); out.append(.route)
            }
        }
        flush()
        return out
    }
}

// MARK: - Settings blocks

enum SettingsLayout {
    /// The Settings screen's blocks in the order they are drawn today. `account` is essential and never listed, so it stays
    /// behind whatever is listed.
    static let defaultBlocks: [String] = ["appearance", "modules", "security", "account", "rate_app", "about"]

    /// The row ids a block stands for.
    static func members(of block: String) -> [String] {
        switch block {
        case "modules":  return ["crm_only_mode", "face_enrollment"]
        case "security": return ["app_lock"]
        case "account":  return []
        default:         return [block]   // appearance, rate_app, about
        }
    }

    /// The blocks in layout order. `isShown` says whether a row id is shown to this client, so a hidden row cannot pull its
    /// block up the screen.
    static func blocks(listed: [String], isShown: (String) -> Bool) -> [String] {
        AppLayoutOrder.sortedGroups(defaultBlocks, listed: listed, ids: { members(of: $0).filter(isShown) })
    }
}

// MARK: - CRM More

enum CRMMoreLayout {
    struct MoreSection: Equatable {
        let id: String
        let rows: [String]
        /// Records and Insights have always drawn their header, even with every row hidden; that is kept.
        var keepsEmptyHeader: Bool = false
    }

    /// The orderable sections of the CRM More tab, in the order they are drawn today. (Account, Work, Learn, Appearance,
    /// Switch to Field Force and Sign Out stay where they are.)
    static let defaultSections: [MoreSection] = [
        MoreSection(id: "records", rows: ["accounts", "pipeline", "products", "custom_objects"], keepsEmptyHeader: true),
        MoreSection(id: "field_visits", rows: ["marketing_visit"]),
        MoreSection(id: "field", rows: ["nearest_leads"]),
        MoreSection(id: "workplace", rows: ["leave"]),
        MoreSection(id: "expenses", rows: ["expenses", "expense_approvals"]),
        MoreSection(id: "insights", rows: ["dashboard", "reports", "lead_analytics"], keepsEmptyHeader: true),
    ]

    /// The sections that have something to show, in layout order, each with only its shown rows, in layout order. A section
    /// moves as a unit to where its earliest listed row sits; the rows inside it follow the list too.
    static func ordered(listed: [String], isShown: (String) -> Bool) -> [MoreSection] {
        let visible: [MoreSection] = defaultSections.compactMap { (section: MoreSection) -> MoreSection? in
            let rows = section.rows.filter(isShown)
            if rows.isEmpty && !section.keepsEmptyHeader { return nil }
            return MoreSection(id: section.id, rows: rows, keepsEmptyHeader: section.keepsEmptyHeader)
        }
        let sections = AppLayoutOrder.sortedGroups(visible, listed: listed, ids: { $0.rows })
        return sections.map { section in
            MoreSection(id: section.id,
                    rows: AppLayoutOrder.sorted(section.rows, listed: listed, id: { $0 }),
                    keepsEmptyHeader: section.keepsEmptyHeader)
        }
    }
}
