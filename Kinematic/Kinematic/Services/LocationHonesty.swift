//
//  LocationHonesty.swift
//  Kinematic CRM
//
//  Field-force location honesty — the iOS half of the shared apps↔backend
//  contract. The premise: once the rep turns location off the OS blocks GPS
//  and we do NOT try to defeat it. Instead we (1) report the honest device
//  location state, (2) tag every heartbeat with whether the fix was precise,
//  and (3) gate the geo-stamped actions (attendance check-in, the attendance
//  selfie flow, form submit) behind a "turn on location" prompt.
//
//  This file holds the wire model, the gate decision + prompt, and the
//  reusable blocking alert. The CLLocationManager reads themselves live on
//  `LocationTrackingService` (the app's single location manager) so we never
//  spin up a second manager.
//

import SwiftUI
import UIKit
import CoreLocation

// MARK: - Feature 1 payload — PATCH /api/v1/users/location-status

/// Honest snapshot of the device's location state. Sent fire-and-forget so
/// the live-tracking dashboard can render a "location off since {time}" badge
/// instead of silently going stale.
struct LocationStatusUpdate: Codable {
    /// "granted" | "denied" | "restricted" | "not_determined"
    let permission: String
    /// Device-level Location Services master switch.
    let servicesEnabled: Bool
    /// Full/precise (`.fullAccuracy`) vs reduced accuracy.
    let precise: Bool

    enum CodingKeys: String, CodingKey {
        case permission
        case servicesEnabled = "services_enabled"
        case precise
    }
}

// MARK: - Feature 3 — the blocking "turn on location" prompt

/// Drives the blocking alert shown when a geo-stamped action is attempted
/// while location is unavailable. `verb` is the sentence fragment shown to the
/// user, e.g. "check in" or "submit".
struct LocationGatePrompt: Identifiable {
    let id = UUID()
    let verb: String
}

/// Outcome of a form submission. Distinguishes the server-side geo-stamp
/// backstop (`.locationRequired`) so the form can show the same "turn on
/// location" gate; `.success` also covers the optimistic offline-queued case.
enum FormSubmitOutcome: Equatable {
    case success
    case locationRequired
    case failed
}

/// Gate decision for a geo-stamped action. Deliberately NOT actor-isolated so
/// it can be called both from synchronous SwiftUI button actions (main) and
/// from the attendance view model's async flow.
enum LocationGate {
    /// Returns a prompt to present when location is unusable (permission not
    /// granted OR the Location Services switch is off), and fires the honest
    /// state report so the dashboard reflects it immediately. Returns nil when
    /// the action may proceed with a live fix.
    static func promptIfBlocked(verb: String) -> LocationGatePrompt? {
        if LocationTrackingService.shared.isLocationUsable {
            return nil
        }
        // Feature 1: report the off-state that just blocked the action.
        LocationTrackingService.shared.reportLocationStatus()
        return LocationGatePrompt(verb: verb)
    }
}

// MARK: - Reusable blocking alert

extension View {
    /// Blocking "Turn on location to <verb>" alert with an Open Settings
    /// deep-link (`UIApplication.openSettingsURLString`). Attach at a stable
    /// host and bind it to the prompt state; setting the binding non-nil
    /// presents it.
    func locationGateAlert(_ prompt: Binding<LocationGatePrompt?>) -> some View {
        alert(
            "Turn on location to \(prompt.wrappedValue?.verb ?? "continue")",
            isPresented: Binding(
                get: { prompt.wrappedValue != nil },
                set: { if !$0 { prompt.wrappedValue = nil } }
            ),
            presenting: prompt.wrappedValue
        ) { _ in
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                prompt.wrappedValue = nil
            }
            Button("Not now", role: .cancel) { prompt.wrappedValue = nil }
        } message: { p in
            Text("Location is off. Turn it on in Settings to \(p.verb).")
        }
    }
}
