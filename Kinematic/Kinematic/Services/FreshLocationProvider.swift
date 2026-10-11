//
//  FreshLocationProvider.swift
//  Kinematic
//
//  One FRESH GPS fix for a GPS-only check-in / check-out (attendance rule `selfie_required: false`): there is no camera
//  step to give the location time to settle, so the punch asks for a new fix instead of trusting an old one. Shaped like
//  CurrentLocationProvider, but it hands back the whole CLLocation (the punch needs the accuracy and the mock-location
//  check), and it never prompts for permission — the location-honesty gate has already run.
//
//  Returns nil (never throws) when permission is missing or no fix arrives within `timeout`; the caller then tells the
//  rep to try again. A location is never invented.
//

import Foundation
import CoreLocation

final class FreshLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// One new fix, or nil if permission is missing or nothing arrives within `timeout` seconds.
    static func fix(timeout: TimeInterval = AttendancePunch.fixTimeout) async -> CLLocation? {
        await FreshLocationProvider().fetch(timeout: timeout)
    }

    private func fetch(timeout: TimeInterval) async -> CLLocation? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = c
            self.manager.requestLocation()
            // Strong self-capture keeps this provider alive for the whole wait (the delegate callbacks resume earlier
            // when a fix or an error lands).
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                self.resume(nil)
            }
        }
    }

    private func resume(_ location: CLLocation?) {
        guard let c = continuation else { return } // resume at most once
        continuation = nil
        c.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        resume(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resume(nil)
    }
}
