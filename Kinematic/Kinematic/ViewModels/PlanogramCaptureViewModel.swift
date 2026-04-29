//
//  PlanogramCaptureViewModel.swift
//  Kinematic
//
//  Drives the field-rep planogram capture flow.
//  States: idle → capturing → uploading → result (with retry support).
//

import SwiftUI
import Combine
import CoreLocation

@MainActor
final class PlanogramCaptureViewModel: ObservableObject {

    enum Phase {
        case idle
        case capturing
        case uploading
        case complete(CaptureResponse)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var capturedImage: UIImage? = nil
    @Published var planogramId: String? = nil
    @Published var storeId: String? = nil
    @Published var visitId: String? = nil

    /// 0..1 — drives the AR alignment overlay color.
    @Published var alignmentScore: Double = 0

    private let service: PlanogramService
    private let location: CLLocationManager

    init(
        service: PlanogramService? = nil,
        location: CLLocationManager? = nil
    ) {
        // Defaults are resolved here so we don't reference main-actor-isolated
        // values from a nonisolated default-argument position.
        self.service = service ?? PlanogramService.shared
        self.location = location ?? CLLocationManager()
    }

    /// Heuristic alignment quality from device motion (called from the camera
    /// preview every few frames). Closer to 1 = better aligned.
    func updateAlignment(roll: Double, pitch: Double) {
        // Reps should hold the phone roughly perpendicular to the shelf.
        // Penalize roll & extreme pitch.
        let rollPenalty = min(1, abs(roll) / 0.4)
        let pitchPenalty = min(1, max(0, abs(pitch) - 0.1) / 0.5)
        alignmentScore = max(0, 1 - (0.6 * rollPenalty + 0.4 * pitchPenalty))
    }

    var canSubmit: Bool {
        if capturedImage == nil { return false }
        if case .uploading = phase { return false }
        return true
    }

    func submit(imageURL: String) async {
        guard let image = capturedImage else {
            phase = .failed("Please capture a shelf photo first.")
            return
        }
        phase = .uploading

        var coords: (Double, Double)? = nil
        if let loc = location.location {
            coords = (loc.coordinate.latitude, loc.coordinate.longitude)
        }

        do {
            let response = try await service.submitCapture(
                image: image,
                storeId: storeId,
                visitId: visitId,
                planogramId: planogramId,
                imageURL: imageURL,
                location: coords
            )
            phase = .complete(response)
        } catch let error as PlanogramServiceError {
            phase = .failed(error.localizedDescription)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func reset() {
        capturedImage = nil
        phase = .idle
    }
}
