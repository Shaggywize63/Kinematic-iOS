//
//  LocationRequiredGate.swift
//  Kinematic CRM
//
//  Mandatory location. The post-login app is a field-force / CRM product whose
//  core actions (attendance, visit verification, geo-stamped leads) are
//  meaningless without a location fix, so the authenticated shell is blocked
//  behind a full-screen gate whenever location is NOT usable — i.e. the
//  authorization is `.notDetermined` / `.denied` / `.restricted`, OR the device
//  Location Services master switch is off.
//
//  The gate:
//    • `.notDetermined` — requests When-In-Use authorization (the app's
//      existing tier) and re-prompts on demand.
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
        case needsPermission   // .notDetermined — we can still ask
        case permissionBlocked // .denied / .restricted — Settings only
        case servicesOff       // authorized, but the master switch is off
    }

    private var reason: Reason {
        switch location.authorizationStatus {
        case .notDetermined:
            return .needsPermission
        case .denied, .restricted:
            return .permissionBlocked
        case .authorizedAlways, .authorizedWhenInUse:
            // Authorized, so the only remaining blocker is the master switch.
            return .servicesOff
        @unknown default:
            return .permissionBlocked
        }
    }

    private var title: String {
        switch reason {
        case .needsPermission:   return "Location Required"
        case .permissionBlocked: return "Location Required"
        case .servicesOff:       return "Turn On Location Services"
        }
    }

    private var message: String {
        switch reason {
        case .needsPermission:
            return "Kinematic needs your location to verify store visits and attendance. Allow location access to continue."
        case .permissionBlocked:
            return "Location access is required to use Kinematic. Open Settings and allow location for Kinematic to continue."
        case .servicesOff:
            return "Location Services are turned off for this device. Open Settings and turn them on to continue using Kinematic."
        }
    }

    private var primaryButtonTitle: String {
        switch reason {
        case .needsPermission: return "Allow Location"
        default:               return "Open Settings"
        }
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
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        // First paint with authorization still undecided: surface the system
        // permission prompt straight away so the common first-launch path is a
        // single tap. iOS no-ops a repeat request while one is already pending.
        .task {
            if case .needsPermission = reason {
                location.requestPermissions()
            }
        }
    }

    private func primaryAction() {
        switch reason {
        case .needsPermission:
            // Re-raise the system prompt. If the user had already dismissed it,
            // the status stays .notDetermined and this shows it again.
            location.requestPermissions()
        case .permissionBlocked, .servicesOff:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
}
