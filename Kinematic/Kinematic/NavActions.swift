import SwiftUI

/// A screen that can be opened from the side menu AND — as an "action tab" — from the field-force bottom bar
/// (`app_ui_config.layout.tabs`). One table, so both places open the same destination with the same SF Symbol and the same
/// label, including an admin's rename (`labels.menu.<id>`).
///
/// Attendance, Route, Activity, New and Expenses are not here: they are the bar's own tabs (see MainTabView).
struct NavAction {
    enum Target {
        /// Presented through `KiniAppState.activeSecondaryRoute`, like every other side-menu sheet.
        case route(SecondaryRoute)
        /// The CRM module, presented full screen (`CRMTabView`).
        case crm
    }

    let id: String
    let icon: String
    let defaultTitle: String
    let color: Color
    let target: Target

    /// The label everywhere this screen is named: the admin's rename, else the built-in name.
    var title: String { ClientFeatures.labelFor("menu", id, default: defaultTitle) }
}

enum NavActions {
    static let all: [NavAction] = [
        NavAction(id: "crm",             icon: "person.2.crop.square.stack.fill", defaultTitle: "CRM",             color: Brand.red, target: .crm),
        NavAction(id: "book_order",      icon: "cart.badge.plus",                 defaultTitle: "Book Order",      color: .indigo,   target: .route(.orderCart)),
        NavAction(id: "collect_payment", icon: "indianrupeesign.circle.fill",     defaultTitle: "Collect Payment", color: .green,    target: .route(.paymentCollect)),
        NavAction(id: "my_orders",       icon: "cart.fill",                       defaultTitle: "My Orders",       color: .indigo,   target: .route(.orderHistory)),
        NavAction(id: "leave",           icon: "calendar.badge.clock",            defaultTitle: "Leave",           color: .teal,     target: .route(.leave)),
        NavAction(id: "timeline",        icon: "clock.arrow.circlepath",          defaultTitle: "Timeline",        color: .blue,     target: .route(.timeline)),
        NavAction(id: "broadcast",       icon: "megaphone.fill",                  defaultTitle: "Broadcasts",      color: .red,      target: .route(.broadcast)),
        NavAction(id: "notifications",   icon: "bell.fill",                       defaultTitle: "Notifications",   color: Brand.red, target: .route(.notifications)),
        NavAction(id: "log_visit",       icon: "list.bullet.rectangle",           defaultTitle: "Visit Log",       color: .green,    target: .route(.visitlog)),
    ]

    static func action(_ id: String) -> NavAction? { all.first { $0.id == id } }
}

/// What the bottom bar draws for one laid-out id.
struct BarTabSpec {
    let title: String
    let icon: String
}

extension BottomBarPlan {
    /// The title and symbol of a bar tab: the bar's own tabs as they have always been named, an action tab exactly as its
    /// side-menu entry (same symbol, same label incl. renames). Nil for an id the bar cannot host.
    static func spec(for id: String) -> BarTabSpec? {
        switch id {
        case "attendance": return BarTabSpec(title: ClientFeatures.labelFor("tabs", "attendance", default: "Attendance"), icon: "person.text.rectangle")
        case "route_plan": return BarTabSpec(title: ClientFeatures.labelFor("tabs", "route_plan", default: "Route"), icon: "map")
        case "activity":   return BarTabSpec(title: ClientFeatures.labelFor("tabs", "activity", default: "Activity"), icon: "square.grid.2x2")
        case "new_form":   return BarTabSpec(title: ClientFeatures.labelFor("tabs", "new_form", default: "New"), icon: "plus.circle.fill")
        case "expenses":   return BarTabSpec(title: ClientFeatures.labelFor("tabs", "expenses", default: "Expenses"), icon: "receipt")
        default:
            guard let action = NavActions.action(id) else { return nil }
            return BarTabSpec(title: action.title, icon: action.icon)
        }
    }
}
