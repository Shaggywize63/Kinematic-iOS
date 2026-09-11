//
//  CurrentLocationProvider.swift
//  Kinematic CRM
//
//  A minimal async single-fix location helper for NON-sensitive uses — the
//  start point when optimizing the rep's own route. Unlike OneShotLocation
//  Provider it runs no SecurityCheck preflight: a spoofed start only reorders
//  the rep's own beat, so it isn't worth an anti-spoof gate or a manager alert.
//
//  Returns nil (never throws / never prompts) when location permission isn't
//  already granted or a fix doesn't arrive within `timeout`; callers fall back
//  to the server-side last known location.
//

import Foundation
import CoreLocation

final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// One-shot current coordinate as a plain (lat, lng), or nil if permission
    /// is missing or no fix arrives within `timeout` seconds. Does not request
    /// permission. Returns a tuple so callers need no CoreLocation import.
    static func oneShot(timeout: TimeInterval = 6) async -> (lat: Double, lng: Double)? {
        guard let coord = await CurrentLocationProvider().fetch(timeout: timeout) else { return nil }
        return (coord.latitude, coord.longitude)
    }

    private func fetch(timeout: TimeInterval) async -> CLLocationCoordinate2D? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            self.continuation = c
            self.manager.requestLocation()
            // Strong self-capture keeps this provider alive for the whole wait
            // (the delegate callbacks resume earlier when a fix/error lands).
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                self.resume(nil)
            }
        }
    }

    private func resume(_ coordinate: CLLocationCoordinate2D?) {
        guard let c = continuation else { return } // resume at most once
        continuation = nil
        c.resume(returning: coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        resume(locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resume(nil)
    }
}
