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

    /// Shelf photos queued for this audit. The rep can add several (camera or
    /// photo library, multi-select) and submit them all in one go — no single
    /// "frame the shelf" step is required. Each photo becomes its own capture.
    @Published var images: [UIImage] = []
    /// Progress across a multi-photo submit: how many of `batchTotal` are done.
    @Published var batchDone: Int = 0
    @Published var batchTotal: Int = 0

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

    var canSubmit: Bool {
        if images.isEmpty { return false }
        if case .uploading = phase { return false }
        return true
    }

    /// Add one or more shelf photos to the audit queue.
    func addImages(_ newImages: [UIImage]) {
        guard !newImages.isEmpty else { return }
        images.append(contentsOf: newImages)
        if case .failed = phase { phase = .idle }
    }

    func removeImage(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
    }

    /// Upload + analyze every queued photo sequentially (each is its own
    /// capture, same pipeline as a single shot). Navigates to the first
    /// successful capture's report; the rest persist and show in the dashboard.
    func submitAll() async {
        guard !images.isEmpty else {
            phase = .failed("Add at least one shelf photo first.")
            return
        }
        phase = .uploading
        batchTotal = images.count
        batchDone = 0

        var coords: (Double, Double)? = nil
        if let loc = location.location {
            coords = (loc.coordinate.latitude, loc.coordinate.longitude)
        }

        var firstResponse: CaptureResponse? = nil
        var failures = 0
        for image in images {
            guard let uploadedURL = await KinematicRepository.shared.uploadImage(image: image, type: "photo") else {
                failures += 1
                batchDone += 1
                continue
            }
            do {
                let response = try await service.submitCapture(
                    image: image,
                    storeId: storeId,
                    visitId: visitId,
                    planogramId: planogramId,
                    imageURL: uploadedURL,
                    location: coords
                )
                if firstResponse == nil {
                    firstResponse = response
                    capturedImage = image
                }
            } catch {
                failures += 1
            }
            batchDone += 1
        }

        if let response = firstResponse {
            phase = .complete(response)
        } else {
            phase = .failed("None of the \(images.count) photo(s) could be analyzed. Please try again.")
        }
    }

    func submit(imageURL: String) async {
        guard let image = capturedImage else {
            phase = .failed("Please capture a shelf photo first.")
            return
        }
        phase = .uploading

        var finalURL = imageURL
        if finalURL.isEmpty {
            // Planogram captures need to be persisted in storage before AI analysis
            if let uploadedURL = await KinematicRepository.shared.uploadImage(image: image, type: "photo") {
                finalURL = uploadedURL
            } else {
                phase = .failed("Failed to upload shelf capture to storage.")
                return
            }
        }

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
                imageURL: finalURL,
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
        images = []
        batchDone = 0
        batchTotal = 0
        phase = .idle
    }
}
