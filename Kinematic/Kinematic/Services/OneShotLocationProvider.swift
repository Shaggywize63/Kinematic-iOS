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
        coordinate = locations.last?.coordinate
        isLocating = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        errorMessage = "Couldn't get your location. Enter coordinates manually."
    }
}
