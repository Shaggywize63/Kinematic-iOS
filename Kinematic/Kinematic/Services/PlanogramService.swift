//
//  PlanogramService.swift
//  Kinematic
//
//  Networking layer for the AI Planogram Engine. Reads the bearer token
//  + org_id from the same Session/UserDefaults the rest of the app uses
//  (see KinematicApp.swift → Session.sharedToken / Session.currentUser?.orgId).
//

import Foundation
import UIKit

enum PlanogramServiceError: LocalizedError {
    case missingAuth
    case badResponse(Int)
    case decodeFailed
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAuth:        return "Please sign in again."
        case .badResponse(let s): return "Server returned status \(s)."
        case .decodeFailed:       return "Could not read server response."
        case .server(let msg):    return msg
        }
    }
}

final class PlanogramService {
    static let shared = PlanogramService()

    /// Match the rest of the app — see `KinematicRepository.baseURL` in
    /// `KinematicApp.swift`. Path strings in this file include `/api/v1/...`,
    /// so the host alone is the base.
    private let baseHost: URL = URL(string: "https://kinematic-production.up.railway.app")!

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: Public API

    /// Returns the list of planograms visible to the current user.
    func listPlanograms() async throws -> [Planogram] {
        try await get("/api/v1/planograms")
    }

    /// Returns one planogram (with its expected_skus + layout).
    func getPlanogram(id: String) async throws -> Planogram {
        try await get("/api/v1/planograms/\(id)")
    }

    /// Submits a shelf capture and returns the compliance result.
    /// `imageData` should be a JPEG.
    func submitCapture(
        image: UIImage,
        storeId: String?,
        visitId: String?,
        planogramId: String?,
        imageURL: String,
        location: (lat: Double, lng: Double)?
    ) async throws -> CaptureResponse {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw PlanogramServiceError.server("Could not encode image.")
        }
        var body: [String: Any] = [
            "image_url":         imageURL,
            "image_base64":      jpeg.base64EncodedString(),
            "image_media_type":  "image/jpeg",
            "device_meta": [
                "platform": "ios",
                "model":    UIDevice.current.model,
                "system":   UIDevice.current.systemVersion
            ]
        ]
        
        if let storeId = storeId { body["store_id"] = storeId }
        if let visitId = visitId { body["visit_id"] = visitId }
        if let planogramId = planogramId { body["planogram_id"] = planogramId }
        
        if let location = location {
            body["capture_lat"] = location.lat
            body["capture_lng"] = location.lng
        }
        
        return try await postJSON("/api/v1/planograms/captures", body: body)
    }

    // MARK: Internals

    /// Bearer token shared with `KinematicRepository` via `Session.sharedToken`.
    /// Falls back to the same `UserDefaults` key (`auth_token`) so we still
    /// work even if `Session` is re-namespaced in the future.
    private var authToken: String? {
        let token = Session.sharedToken
        if !token.isEmpty { return token }
        let raw = UserDefaults.standard.string(forKey: "auth_token") ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var orgId: String? {
        Session.currentUser?.orgId
    }

    private func get<T: Codable>(_ path: String) async throws -> T {
        let req = try makeRequest(path: path, method: "GET", body: nil)
        return try await perform(req)
    }

    private func postJSON<T: Codable>(_ path: String, body: [String: Any]) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted])
        let req = try makeRequest(path: path, method: "POST", body: data)
        return try await perform(req)
    }

    private func makeRequest(path: String, method: String, body: Data?) throws -> URLRequest {
        guard let token = authToken else { throw PlanogramServiceError.missingAuth }
        let url = baseHost.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let orgId { req.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        req.httpBody = body
        // Capture upload can be large — give it a generous timeout.
        req.timeoutInterval = body == nil ? 30 : 90
        return req
    }

    private func perform<T: Codable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw PlanogramServiceError.badResponse(0)
        }
        if !(200..<300).contains(http.statusCode) {
            // Try to extract a friendly error from the envelope.
            if let env = try? decoder.decode(APIEnvelope<EmptyData>.self, from: data),
               let msg = env.error ?? env.message {
                throw PlanogramServiceError.server(msg)
            }
            throw PlanogramServiceError.badResponse(http.statusCode)
        }
        do {
            let env = try decoder.decode(APIEnvelope<T>.self, from: data)
            guard let payload = env.data else { throw PlanogramServiceError.decodeFailed }
            return payload
        } catch {
            throw PlanogramServiceError.decodeFailed
        }
    }

    private struct EmptyData: Codable {}
}
