//
//  AIChatService.swift
//  Kinematic CRM — KINI assistant client.
//

import Foundation

final class AIChatService {
    static let shared = AIChatService()

    private let baseHost: URL = URL(string: "https://kinematic-production.up.railway.app")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// POST /api/v1/crm/ai/chat — KINI assistant.
    func chat(message: String, conversationId: String?, context: [String: Any]? = nil) async throws -> AIChatResponse {
        var body: [String: Any] = ["message": message]
        if let conversationId { body["conversation_id"] = conversationId }
        if let context { body["context"] = context }

        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let req = try makeRequest(path: "/api/v1/crm/ai/chat", method: "POST", body: data)
        return try await perform(req)
    }

    private var authToken: String? {
        let token = Session.sharedToken
        if !token.isEmpty { return token }
        let raw = UserDefaults.standard.string(forKey: "auth_token") ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var orgId: String? { Session.currentUser?.orgId }

    private func makeRequest(path: String, method: String, body: Data?) throws -> URLRequest {
        guard let token = authToken else { throw CRMServiceError.missingAuth }
        let url = baseHost.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let orgId { req.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        req.httpBody = body
        req.timeoutInterval = 60
        return req
    }

    private func perform<T: Codable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CRMServiceError.badResponse(0)
        }
        if !(200..<300).contains(http.statusCode) {
            if let env = try? decoder.decode(APIEnvelope<EmptyAck>.self, from: data),
               let msg = env.error ?? env.message {
                throw CRMServiceError.server(msg)
            }
            throw CRMServiceError.badResponse(http.statusCode)
        }
        if let env = try? decoder.decode(APIEnvelope<T>.self, from: data), let payload = env.data {
            return payload
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CRMServiceError.decodeFailed(String(describing: error))
        }
    }
}
