//
//  CRMService+Edit.swift
//  Kinematic CRM
//
//  PATCH endpoints for editing the four core CRM entities. The original
//  CRMService used PUT which the backend doesn't expose; this extension
//  routes through the correct verb so edits actually land.
//

import Foundation

extension CRMService {
    func patchLead(id: String, body: [String: Any]) async throws -> Lead {
        try await patch("/api/v1/crm/leads/\(id)", body: body)
    }
    func patchContact(id: String, body: [String: Any]) async throws -> Contact {
        try await patch("/api/v1/crm/contacts/\(id)", body: body)
    }
    func patchAccount(id: String, body: [String: Any]) async throws -> CRMAccount {
        try await patch("/api/v1/crm/accounts/\(id)", body: body)
    }
    func patchDeal(id: String, body: [String: Any]) async throws -> Deal {
        try await patch("/api/v1/crm/deals/\(id)", body: body)
    }
}

private extension CRMService {
    func patch<T: Codable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = try EditHelpers.buildURL(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.timeoutInterval = 30
        EditHelpers.applyHeaders(to: &req)
        let payload = body.isEmpty
            ? Data("{}".utf8)
            : try JSONSerialization.data(withJSONObject: body, options: [])
        req.httpBody = payload

        let (data, resp) = try await URLSession.shared.data(for: req)
        try EditHelpers.validate(resp, data: data)
        return try EditHelpers.decodeEnvelope(T.self, from: data)
    }
}

private enum EditHelpers {
    static let baseHostURL: URL = URL(string: "https://kinematic-production.up.railway.app")!

    static func buildURL(path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseHostURL)?.absoluteURL else {
            throw CRMServiceError.server("Bad URL")
        }
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

    static func decodeEnvelope<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        if let env = try? decoder.decode(APIEnvelope<T>.self, from: data), let p = env.data { return p }
        if let raw = try? decoder.decode(T.self, from: data) { return raw }
        throw CRMServiceError.decodeFailed("Expected \(T.self)")
    }
}
