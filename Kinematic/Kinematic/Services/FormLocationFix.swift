//
//  FormLocationFix.swift
//  Kinematic
//
//  A position for the things a rep does on a form: the location question ("Capture location") and the start of a
//  visit (check-in on a form). It takes the live-tracking fix when that is recent, otherwise asks for one fresh fix,
//  and only then falls back to the last known one. Never invents a position: no fix = nil, and the caller says so.
//  Does not ask for permission (the screens run `LocationGate.promptIfBlocked` first, which names the problem).
//

import Foundation
import CoreLocation

enum FormLocationFix {

    /// A fix this young (either side of now, to allow a little clock skew) is used as it is.
    static let freshFor: TimeInterval = 120

    /// Is a fix taken at `timestamp` recent enough to use without asking for another?
    static func isFresh(_ timestamp: Date, now: Date) -> Bool {
        abs(now.timeIntervalSince(timestamp)) <= freshFor
    }

    /// The best position available right now, or nil when there is none.
    static func current() async -> (lat: Double, lng: Double)? {
        if let loc = LocationTrackingService.shared.lastLocation, isFresh(loc.timestamp, now: Date()) {
            return (loc.coordinate.latitude, loc.coordinate.longitude)
        }
        if let fix = await CurrentLocationProvider.oneShot() {
            return (fix.lat, fix.lng)
        }
        if let loc = LocationTrackingService.shared.lastLocation {
            return (loc.coordinate.latitude, loc.coordinate.longitude)
        }
        return nil
    }
}
