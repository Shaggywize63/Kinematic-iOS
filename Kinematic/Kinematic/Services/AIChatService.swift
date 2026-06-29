//
//  AIChatService.swift
//  Kinematic CRM — KINI assistant client.
//

import Foundation

final class AIChatService {
    static let shared = AIChatService()

    private let baseHost: URL = URL(string: "https://api.kinematicapp.com")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// POST /api/v1/kini/v2/chat — agentic KINI assistant (cross-module
    /// tools, context block, planning loop).
    /// Backend expects `{messages: [{role, content}], system?, context?}` and
    /// responds with `{text, cards, tool_calls}` (v2 adds an ignorable
    /// `thread_id`; the response shape is otherwise identical to v1, so the
    /// existing `AIChatResponse` decode is unchanged). Pass the full
    /// conversation history each turn — the request stays stateless (no
    /// thread_id sent) and Claude replays the message log.
    ///
    /// If the tenant's v2 flag is off the backend returns **403**
    /// (`KINI_V2_DISABLED`); we transparently retry the identical request
    /// against the legacy `/api/v1/crm/ai/chat`. The same `context` object
    /// carries both v1 and v2 fields, so either endpoint reads what it needs.
    func chat(messages: [ChatTurn], system: String? = nil, context: [String: Any]? = nil) async throws -> AIChatResponse {
        var body: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if let system { body["system"] = system }
        if let context { body["context"] = context }

        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let v2Req = try makeRequest(path: "/api/v1/kini/v2/chat", method: "POST", body: data)
        do {
            return try await perform(v2Req)
        } catch CRMServiceError.badResponse(403), CRMServiceError.serverStatus(403, _) {
            // Tenant flag off — replay the identical request on the legacy path.
            let v1Req = try makeRequest(path: "/api/v1/crm/ai/chat", method: "POST", body: data)
            return try await perform(v1Req)
        }
    }

    /// GET /api/v1/crm/ai/usage — current month's AI quota for the caller.
    /// Best-effort: returns nil on any failure so the FAB chip can quietly hide
    /// instead of surfacing a transient error.
    func fetchUsage() async -> KiniUsage? {
        do {
            let req = try makeRequest(path: "/api/v1/crm/ai/usage", method: "GET", body: nil)
            let usage: KiniUsage = try await perform(req)
            return usage
        } catch {
            return nil
        }
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
        // Scope KINI tool calls to the active client so the assistant only
        // searches leads/deals belonging to the rep's tenant. Mirrors the
        // same X-Client-Id header that CRMService sends on every CRM call.
        if let cid = CRMClientScope.selectedClientId(), !cid.isEmpty {
            req.setValue(cid, forHTTPHeaderField: "X-Client-Id")
        }
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
            // Surface the status code alongside any server message so the
            // chat() 403-fallback can detect KINI_V2_DISABLED regardless of
            // whether the backend included an error envelope.
            if let env = try? decoder.decode(APIEnvelope<EmptyAck>.self, from: data),
               let msg = env.error ?? env.message {
                throw CRMServiceError.serverStatus(http.statusCode, msg)
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
