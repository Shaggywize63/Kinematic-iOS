//
//  SecurityCheck.swift
//  Kinematic CRM
//
//  Pre-flight integrity check shared by every action that needs a
//  trustworthy location stamp or network identity. Today: mobile
//  attendance check-in/out, lead capture geo-pin, form submission,
//  and a one-shot check at app launch.
//
//  The contract: any action that wants to be defensible against
//  fraud calls SecurityCheck.preflight(action:location:) BEFORE
//  hitting the backend. On detection:
//    1. POST the violation to /api/v1/misc/security/alert so the
//       dashboard surfaces it and the rep's hierarchy managers get
//       a push (handled server-side).
//    2. Return .blocked(reason) so the caller refuses to save the
//       action. The rep sees the reason inline.
//
//  Detection vectors:
//    - VPN: read CFNetworkCopySystemProxySettings's __SCOPED__ dict
//      for utun/tap/ppp/ipsec interface keys. This is the only
//      non-private API that catches every consumer VPN app on iOS
//      (NordVPN, ExpressVPN, ProtonVPN, the system VPN entitlement).
//    - Mock GPS: CLLocation.sourceInformation.isSimulatedBySoftware
//      on iOS 15+ (the only first-party signal). On older devices
//      we fall through to the horizontal-accuracy < 0 sentinel that
//      the legacy AttendanceViewModel relied on.
//

import Foundation
import CoreLocation

enum SecurityViolation: String {
    case vpn         = "VPN_DETECTED"
    case mockGPS     = "MOCK_LOCATION"

    var friendly: String {
        switch self {
        case .vpn:     return "VPN connection"
        case .mockGPS: return "mock GPS location"
        }
    }

    /// Human-readable message shown to the rep in the block UI.
    /// Calm, factual, instruction-first per the brand voice guide.
    var blockMessage: String {
        switch self {
        case .vpn:
            return "A VPN connection was detected. Turn off the VPN app and try again. Your supervisor has been notified."
        case .mockGPS:
            return "Your phone is reporting a simulated GPS position. Turn off Fake GPS / Developer-mode location and try again. Your supervisor has been notified."
        }
    }
}

enum SecurityResult {
    case ok
    case blocked(SecurityViolation)
}

struct SecurityCheck {

    /// Run every integrity check that's applicable for the caller.
    /// `location` is optional because the launch-time check fires
    /// before any GPS fix is available — in that case we only run
    /// the VPN check.
    ///
    /// On any violation: POST the alert to the backend (so the
    /// supervisor's push fires) and return .blocked. The audit
    /// row is the source of truth — a network blip on the POST is
    /// logged but never converts the result back to .ok.
    @MainActor
    static func preflight(action: String, location: CLLocation? = nil) async -> SecurityResult {
        // VPN check is cheap (one Core Foundation call) — run it
        // first so the rep doesn't burn a GPS fix when the network
        // is the problem.
        if isVPNActive() {
            await report(.vpn, action: action, location: location)
            return .blocked(.vpn)
        }
        if let loc = location, isMockLocation(loc) {
            await report(.mockGPS, action: action, location: loc)
            return .blocked(.mockGPS)
        }
        return .ok
    }

    /// Pure helpers — exposed so call sites that need only one
    /// signal (e.g. OneShotLocationProvider checking the GPS fix
    /// it just received) can short-circuit without rebuilding the
    /// whole preflight pipeline.

    static func isVPNActive() -> Bool {
        // CFNetworkCopySystemProxySettings returns a dict whose
        // __SCOPED__ child maps each active network interface name
        // to its proxy settings. On a clean device that's just
        // en0/wifi/cellular. With a VPN active, you also see
        // tap, tun, utun, ppp, ipsec — the kernel pseudo-interfaces
        // every consumer VPN app installs to ferry packets.
        guard
            let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue()
                as? [String: Any],
            let scoped = settings["__SCOPED__"] as? [String: Any]
        else { return false }

        let vpnPrefixes = ["tap", "tun", "utun", "ppp", "ipsec"]
        for key in scoped.keys {
            let lower = key.lowercased()
            if vpnPrefixes.contains(where: { lower.hasPrefix($0) }) {
                return true
            }
        }
        return false
    }

    static func isMockLocation(_ location: CLLocation) -> Bool {
        // iOS 15+: first-party signal via sourceInformation.
        if #available(iOS 15.0, *), let src = location.sourceInformation {
            if src.isSimulatedBySoftware { return true }
            // isProducedByAccessory means a paired GPS dongle. Not
            // a violation today (Tata reps don't use them) but a
            // strong signal worth keeping wired.
        }
        // Legacy fallback — the heuristic the prior checkSecurity
        // used. Negative horizontalAccuracy on a real fix is
        // physically impossible; some mock-GPS apps trip it.
        if location.horizontalAccuracy < 0 { return true }
        return false
    }

    @MainActor
    private static func report(_ violation: SecurityViolation,
                               action: String,
                               location: CLLocation?) async {
        await KinematicRepository.shared.logSecurityViolation(
            type: violation.rawValue,
            action: action,
            lat: location?.coordinate.latitude,
            lng: location?.coordinate.longitude
        )
    }
}
