//
//  AIChatService.swift
//  Kinematic CRM — KINI assistant client.
//

import Foundation

/// Reason codes the backend emits on 429. UI maps them to copy / state.
enum KiniLimitCode: String {
    case orgLimit  = "ORG_KINI_LIMIT_REACHED"
    case userLimit = "USER_KINI_LIMIT_REACHED"
}

/// Surfaced when the backend rejects the chat with HTTP 429. Carries the
/// machine-readable `code` so the view layer can switch copy between
/// per-user and org-wide caps.
struct KiniQuotaError: LocalizedError {
    let code: KiniLimitCode
    let message: String
    var errorDescription: String? { message }
}

final class AIChatService {
    static let shared = AIChatService()

    private let baseHost: URL = URL(string: "https://kinematic-production.up.railway.app")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// POST /api/v1/crm/ai/chat — KINI assistant.
    /// Backend expects `{messages: [{role, content}], system?, context?}` and
    /// responds with `{text, cards, tool_calls}` (matches the dashboard's
    /// KinematicAI client). Pass the full conversation history each turn —
    /// the backend is stateless and replays the message log to Claude.
    func chat(messages: [ChatTurn], system: String? = nil, context: [String: Any]? = nil) async throws -> AIChatResponse {
        var body: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if let system { body["system"] = system }
        if let context { body["context"] = context }

        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let req = try makeRequest(path: "/api/v1/crm/ai/chat", method: "POST", body: data)
        return try await perform(req)
    }

    /// GET /api/v1/crm/ai/credits — org-wide monthly credits + breakdown.
    func getCredits() async throws -> KiniCredits {
        let req = try makeRequest(path: "/api/v1/crm/ai/credits", method: "GET", body: nil)
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
        // Per-platform attribution for org-wide credit reporting on the backend.
        req.setValue("ios", forHTTPHeaderField: "X-Kinematic-Platform")
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
            // KINI 429 returns a structured {code,message} error so the
            // mobile UI can distinguish org-cap from user-cap. Parse first.
            if http.statusCode == 429,
               let env = try? decoder.decode(APIEnvelope<KiniLimitPayload>.self, from: data) {
                let codeStr = env.errorObject?.code
                    ?? env.data?.usage?.reason
                    ?? KiniLimitCode.userLimit.rawValue
                let code = KiniLimitCode(rawValue: codeStr) ?? .userLimit
                let msg = env.errorObject?.message ?? env.error ?? env.message ?? "Monthly KINI limit reached."
                throw KiniQuotaError(code: code, message: msg)
            }
            if let env = try? decoder.decode(APIEnvelope<EmptyAck>.self, from: data),
               let msg = env.errorObject?.message ?? env.error ?? env.message {
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

// MARK: - Models

/// Response payload for /api/v1/crm/ai/credits.
struct KiniCredits: Codable {
    let used: Int
    let limit: Int
    let periodEnd: String
    let platformBreakdown: PlatformBreakdown

    enum CodingKeys: String, CodingKey {
        case used, limit
        case periodEnd = "period_end"
        case platformBreakdown = "platform_breakdown"
    }

    struct PlatformBreakdown: Codable {
        let web: Int
        let ios: Int
        let android: Int
    }
}

/// Shape of the {data: {usage: {...}}} object the backend returns on 429.
struct KiniLimitPayload: Codable {
    struct Usage: Codable {
        let used: Int?
        let cap: Int?
        let remaining: Int?
        let month: String?
        let exempt: Bool?
        let limitReached: Bool?
        let reason: String?
        let orgUsed: Int?
        let orgCap: Int?
        enum CodingKeys: String, CodingKey {
            case used, cap, remaining, month, exempt, reason
            case limitReached = "limit_reached"
            case orgUsed = "org_used"
            case orgCap  = "org_cap"
        }
    }
    let usage: Usage?
}
