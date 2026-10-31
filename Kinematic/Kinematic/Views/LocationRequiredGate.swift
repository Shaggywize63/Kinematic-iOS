//
//  LocationRequiredGate.swift
//  Kinematic CRM
//
//  Mandatory location. The post-login app is a field-force / CRM product whose
//  core actions (attendance, visit verification, geo-stamped leads) are
//  meaningless without a location fix, so the authenticated shell is blocked
//  behind a full-screen gate whenever location is NOT usable — i.e. the
//  authorization is anything other than `.authorizedAlways`, OR the device
//  Location Services master switch is off.
//
//  "Always" (Allow all the time) is COMPULSORY: "While Using the App" is not
//  enough, because visits and attendance must keep tracking in the background.
//
//  The gate:
//    • `.notDetermined` — requests When-In-Use authorization (Apple's required
//      first step) and re-prompts on demand.
//    • `.authorizedWhenInUse` — raises the system "Change to Always Allow?"
//      upgrade prompt, and offers a Settings deep-link as the fallback (iOS
//      only shows that system prompt once per install).
//    • `.denied` / `.restricted` — explains location is required and deep-links
//      to the app's Settings page.
//    • master switch off — tells the user to turn Location Services on, with
//      the same Settings deep-link.
//
//  It re-checks continuously: it binds to the SINGLE shared location manager
//  (`LocationTrackingService`), whose authorization-change delegate callback
//  republishes the gate state, AND it re-reads on every app foreground
//  (`scenePhase == .active`) to catch a master-switch toggle made while
//  backgrounded. It auto-dismisses the instant location becomes usable — no
//  restart needed — because the overlay is driven by `isLocationUsablePublished`.
//
//  Wired in `ContentView`: wraps `MainTabView()` (the authenticated shell),
//  so it never covers the login or set-password screens.
//

import SwiftUI
import UIKit
import CoreLocation

// MARK: - Gate modifier

/// Overlays the full-screen `LocationRequiredView` over the authenticated app
/// shell whenever location is unusable, and keeps the decision fresh across the
/// delegate callback (handled on the service) and every app foreground.
private struct LocationRequiredGate: ViewModifier {
    // Same shared instance KinematicApp injects into ContentView's environment.
    @EnvironmentObject private var location: LocationTrackingService
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if !location.isLocationUsablePublished {
                    LocationRequiredView()
                        .transition(.opacity)
                        .zIndex(40)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: location.isLocationUsablePublished)
            // Catch a master-switch toggle (or a Settings change) made while we
            // were backgrounded — no authorization delegate callback fires then.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { location.refreshLocationGateState() }
            }
            .onAppear { location.refreshLocationGateState() }
    }
}

extension View {
    /// Block this (authenticated) content behind the mandatory-location gate.
    func locationRequiredGate() -> some View {
        modifier(LocationRequiredGate())
    }
}

// MARK: - Full-screen gate

struct LocationRequiredView: View {
    @EnvironmentObject private var location: LocationTrackingService

    /// What's wrong right now — chosen from the live, published gate state.
    private enum Reason {
        case needsPermission   // .notDetermined — we can still ask (When-In-Use first)
        case needsAlways       // .authorizedWhenInUse — must upgrade to Always
        case permissionBlocked // .denied / .restricted — Settings only
        case servicesOff       // authorized, but the master switch is off
    }

    private var reason: Reason {
        switch location.authorizationStatus {
        case .notDetermined:
            return .needsPermission
        case .denied, .restricted:
            return .permissionBlocked
        case .authorizedWhenInUse:
            // Granted only "While Using the App". Location must be "Always" (Allow
            // all the time) to continue — unless the master switch is also off,
            // which is the more fundamental fix to surface first.
            return location.locationServicesOn ? .needsAlways : .servicesOff
        case .authorizedAlways:
            // Always-authorized, so the only remaining blocker is the master switch.
            return .servicesOff
        @unknown default:
            return .permissionBlocked
        }
    }

    private var title: String {
        switch reason {
        case .needsPermission:   return "Location Required"
        case .needsAlways:       return "Allow Location Always"
        case .permissionBlocked: return "Location Required"
        case .servicesOff:       return "Turn On Location Services"
        }
    }

    private var message: String {
        switch reason {
        case .needsPermission:
            return "Kinematic needs your location to verify store visits and attendance. Allow location access to continue."
        case .needsAlways:
            return "Kinematic needs location set to “Always” (Allow all the time), not just “While Using the App”, so your visits and attendance keep tracking in the background. Please change location access to Always to continue."
        case .permissionBlocked:
            return "Location access is required to use Kinematic. Open Settings and allow location for Kinematic to continue."
        case .servicesOff:
            return "Location Services are turned off for this device. Open Settings and turn them on to continue using Kinematic."
        }
    }

    private var primaryButtonTitle: String {
        switch reason {
        case .needsPermission: return "Allow Location"
        case .needsAlways:     return "Allow All the Time"
        default:               return "Open Settings"
        }
    }

    /// A second, quieter action — only the Always step needs one, because iOS
    /// shows the system "Change to Always Allow?" prompt at most once: after that
    /// the only way to Always is the Settings deep-link.
    private var secondaryButtonTitle: String? {
        reason == .needsAlways ? "Open Settings" : nil
    }

    var body: some View {
        ZStack {
            // Opaque brand backdrop so no app content shows through the gate.
            Brand.navy.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 132, height: 132)
                    Image(systemName: "location.slash.fill")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundColor(.white)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(Brand.Display.bold(24))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(Brand.Body.regular(15))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }

                Spacer()

                VStack(spacing: 14) {
                    Button(action: primaryAction) {
                        Text(primaryButtonTitle)
                            .font(Brand.Body.semiBold(16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Brand.red)
                            .cornerRadius(16)
                    }
                    if let secondary = secondaryButtonTitle {
                        Button(action: openSettings) {
                            Text(secondary)
                                .font(Brand.Body.semiBold(16))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        // First paint: surface the matching system prompt straight away so the
        // common path is a single tap — the When-In-Use prompt when undecided,
        // or the "Change to Always Allow?" upgrade prompt when we're one step
        // short. iOS no-ops a repeat request while one is already pending, and
        // only ever shows the Always upgrade prompt once per install.
        .task {
            switch reason {
            case .needsPermission: location.requestPermissions()
            case .needsAlways:     location.upgradeToAlwaysIfPossible()
            default:               break
            }
        }
    }

    private func primaryAction() {
        switch reason {
        case .needsPermission:
            // Re-raise the system prompt. If the user had already dismissed it,
            // the status stays .notDetermined and this shows it again.
            location.requestPermissions()
        case .needsAlways:
            // Raise the system "Change to Always Allow?" upgrade prompt. iOS only
            // presents it once; after that the Open Settings button is the path.
            location.upgradeToAlwaysIfPossible()
        case .permissionBlocked, .servicesOff:
            openSettings()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
