//
//  OneShotLocationProvider.swift
//  Kinematic CRM
//
//  A single-fix GPS helper for tagging a lead's location at capture time.
//  Wraps CLLocationManager: asks for when-in-use permission, requests one
//  location, and publishes the coordinate (or a friendly error). Field reps
//  adding a lead on-site get an exact pin; the form always allows manual
//  entry as a fallback.
//

import Foundation
import CoreLocation
import Combine

final class OneShotLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isLocating = false
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Kick off a one-shot location request. Handles the permission prompt
    /// on first use; if already denied, surfaces a manual-entry hint.
    func requestLocation() {
        errorMessage = nil
        isLocating = true
        switch manager.authorizationStatus {
        case .notDetermined:
            // The actual request fires from the authorization callback once
            // the user responds to the system prompt.
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isLocating = false
            errorMessage = "Location access is off. Enable it in Settings, or enter coordinates manually."
        default:
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate (delivered on the main thread)

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLocating else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            isLocating = false
            errorMessage = "Location access is off. Enter coordinates manually."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else {
            isLocating = false
            return
        }
        // Integrity gate. If the rep has Fake GPS / a mock-location
        // app running, refuse to publish the coordinate so the form
        // can't save a spoofed pin. Same pre-flight the attendance
        // flow runs, plus a VPN sniff: the user identity that maps
        // a lead back to the rep matters as much as the lat/lng.
        // The pre-flight POSTs the alert to /security/alert which
        // fans out the manager push.
        Task { @MainActor in
            let result = await SecurityCheck.preflight(action: "LEAD_CREATE_GEO", location: last)
            switch result {
            case .ok:
                self.coordinate = last.coordinate
            case .blocked(let violation):
                self.coordinate = nil
                self.errorMessage = violation.blockMessage
            }
            self.isLocating = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        errorMessage = "Couldn't get your location. Enter coordinates manually."
    }
}
