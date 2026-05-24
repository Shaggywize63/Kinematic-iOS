//
//  CRMService+FormConfig.swift
//  Kinematic CRM
//
//  Endpoints powering the per-org Lead form customization the web
//  uses (field overrides, custom fields) plus the photo upload helper
//  consumed by the Lead create / edit sheets.
//
//  Kept in a dedicated file so the main CRMService surface stays focused
//  on entity CRUD.
//

import Foundation
import UIKit

extension CRMService {
    /// Fetch the org's CRM settings record. The full object is large; the
    /// only thing we currently care about on iOS is `config.field_overrides`.
    /// Returned as a parsed dictionary keyed by `<entity>.<field_key>`.
    func leadFieldOverrides() async throws -> [String: FieldOverride] {
        let url = try FormConfigHelpers.buildURL(path: "/api/v1/crm/settings", query: [:])
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        FormConfigHelpers.applyHeaders(to: &req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try FormConfigHelpers.validate(resp, data: data)

        // The shape is `{ success, data: { config: { field_overrides: {...} } } }`.
        // We decode loosely with JSONSerialization since `config` is org-defined
        // free-form JSON we don't want to type fully on the client.
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        let payload = (root["data"] as? [String: Any]) ?? root
        let config = (payload["config"] as? [String: Any]) ?? [:]
        guard let raw = config["field_overrides"] as? [String: Any] else { return [:] }

        var out: [String: FieldOverride] = [:]
        for (key, value) in raw {
            guard let dict = value as? [String: Any] else { continue }
            out[key] = FieldOverride(
                label: dict["label"] as? String,
                required: dict["required"] as? Bool,
                hidden: dict["hidden"] as? Bool,
                position: dict["position"] as? Int
            )
        }
        return out
    }

    /// Custom-field definitions for an entity (lead, contact, deal, account).
    func listCustomFields(entityType: String) async throws -> [CRMCustomField] {
        let url = try FormConfigHelpers.buildURL(
            path: "/api/v1/crm/custom-fields",
            query: ["entity_type": entityType]
        )
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        FormConfigHelpers.applyHeaders(to: &req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try FormConfigHelpers.validate(resp, data: data)

        let decoder = JSONDecoder()
        if let env = try? decoder.decode(APIEnvelope<[CRMCustomField]>.self, from: data),
           let list = env.data { return list }
        if let raw = try? decoder.decode([CRMCustomField].self, from: data) { return raw }
        return []
    }

    /// Upload a UIImage as JPEG to /api/v1/upload/photo and return the
    /// hosted URL. JPEG compression caps the payload at ~8MB (the backend's
    /// stated limit); we step quality down until we fit.
    ///
    /// The endpoint is entity-agnostic: leads, contacts, and accounts all
    /// hit the same `/api/v1/upload/photo` and the resulting URL is stored
    /// on the entity row by the caller.
    func uploadPhoto(_ image: UIImage) async throws -> String {
        guard let data = Self.jpegUnder8MB(image) else {
            throw CRMServiceError.server("Could not encode image")
        }

        let url = try FormConfigHelpers.buildURL(path: "/api/v1/upload/photo", query: [:])
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        FormConfigHelpers.applyHeaders(to: &req)
        // applyHeaders set application/json; override for multipart.
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (respData, resp) = try await URLSession.shared.data(for: req)
        try FormConfigHelpers.validate(resp, data: respData)

        // Accept either `{ data: { url } }` envelope or top-level `{ url }`.
        if let root = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] {
            if let nested = root["data"] as? [String: Any], let url = nested["url"] as? String {
                return url
            }
            if let url = root["url"] as? String { return url }
        }
        throw CRMServiceError.decodeFailed("Upload did not return a url")
    }

    /// JPEG-encode while staying under 8MB. Starts at 0.9 quality and steps
    /// down. Most phone shots end up well under the cap on the first try.
    private static func jpegUnder8MB(_ image: UIImage) -> Data? {
        let cap = 8 * 1024 * 1024
        var quality: CGFloat = 0.9
        var data = image.jpegData(compressionQuality: quality)
        while let d = data, d.count > cap, quality > 0.3 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
        }
        // Last-ditch resize if even 0.3 quality is too big (rare).
        if (data?.count ?? 0) > cap {
            let scale: CGFloat = 0.7
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
            data = resized.jpegData(compressionQuality: 0.7)
        }
        return data
    }
}

// MARK: - Private helpers (mirrors the pattern used in CRMService+Phase2)
private enum FormConfigHelpers {
    static let baseHostURL: URL = URL(string: "https://kinematic-production.up.railway.app")!

    static func buildURL(path: String, query: [String: String]) throws -> URL {
        var components = URLComponents(
            url: baseHostURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw CRMServiceError.server("Bad URL") }
        return url
    }

    static func applyHeaders(to req: inout URLRequest) {
        let token = Session.sharedToken.isEmpty
            ? (UserDefaults.standard.string(forKey: "auth_token") ?? "")
            : Session.sharedToken
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }
        if let cid = CRMClientScope.selectedClientId() {
            req.setValue(cid, forHTTPHeaderField: "X-Client-Id")
        }
    }

    static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw CRMServiceError.badResponse(0) }
        if !(200..<300).contains(http.statusCode) {
            if let env = try? JSONDecoder().decode(APIEnvelope<EmptyAck>.self, from: data),
               let msg = env.error ?? env.message {
                throw CRMServiceError.server(msg)
            }
            throw CRMServiceError.badResponse(http.statusCode)
        }
    }
}
