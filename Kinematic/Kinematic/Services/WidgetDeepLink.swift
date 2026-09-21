//
//  WidgetDeepLink.swift
//  Kinematic
//
//  Bridges a home-screen widget tap into the app's navigation. The
//  widgets open `kinematic://<host>` URLs (leads, new-lead, lead?id=…,
//  my-day, checkin, team); `KinematicApp.onOpenURL` parses the host and
//  publishes it here, and `CRMTabView` observes `pendingRoute` to select
//  the matching tab. Opening the app already works via the registered
//  URL scheme — this just steers to the right screen once inside.
//

import Foundation
import Combine

enum WidgetRoute: Equatable {
    case leads
    case newLead
    case lead(id: String)
    case myDay
    case checkIn
    case team

    /// Parse a `kinematic://` widget URL into a route. Returns nil for
    /// non-widget hosts (e.g. reset-password, handled elsewhere).
    init?(url: URL) {
        guard url.scheme?.lowercased() == "kinematic" else { return nil }
        switch (url.host ?? "").lowercased() {
        case "leads":     self = .leads
        case "new-lead":  self = .newLead
        case "lead":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value ?? ""
            self = .lead(id: id)
        case "my-day":    self = .myDay
        case "checkin":   self = .checkIn
        case "team":      self = .team
        default:          return nil
        }
    }
}

/// Process-wide bus for widget-originated navigation intents.
@MainActor
final class WidgetDeepLink: ObservableObject {
    static let shared = WidgetDeepLink()
    private init() {}

    /// Set by `onOpenURL`, consumed (and cleared) by the observing view.
    @Published var pendingRoute: WidgetRoute?

    func handle(_ url: URL) {
        guard let route = WidgetRoute(url: url) else { return }
        pendingRoute = route
    }

    func consume() -> WidgetRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}
