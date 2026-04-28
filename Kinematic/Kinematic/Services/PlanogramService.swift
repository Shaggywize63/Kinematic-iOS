//
//  PlanogramService.swift
//  Kinematic
//
//  Networking layer for the AI Planogram Engine. Reads the bearer token
//  + base URL from the same UserDefaults keys the rest of the app uses.
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

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: Config

    private var baseURL: URL {
        let raw = UserDefaults.standard.string(forKey: "kinematic.baseURL")
            ?? Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "https://api.kinematic.app"
        return URL(string: raw)!
    }

    private var authToken: String? {
        UserDefaults.standard.string(forKey: "kinematic.authToken")
    }

    private var orgId: String? {
        UserDefaults.standard.string(forKey: "kinematic.orgId")
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
        let body: [String: Any] = [
            "image_url":         imageURL,
            "image_base64":      jpeg.base64EncodedString(),
            "image_media_type":  "image/jpeg",
            "store_id":          storeId as Any,
            "visit_id":          visitId as Any,
            "planogram_id":      planogramId as Any,
            "capture_lat":       location?.lat as Any,
            "capture_lng":       location?.lng as Any,
            "device_meta": [
                "platform": "ios",
                "model":    UIDevice.current.model,
                "system":   UIDevice.current.systemVersion
            ] as [String: String]
        ].compactMapValues { $0 is NSNull ? nil : $0 }
        return try await postJSON("/api/v1/planograms/captures", body: body)
    }

    // MARK: Internals

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
        let url = baseURL.appendingPathComponent(path)
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
