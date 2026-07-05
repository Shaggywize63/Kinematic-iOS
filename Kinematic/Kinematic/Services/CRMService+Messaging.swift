//
//  CRMService+Messaging.swift
//  Kinematic
//
//  Inbox + DMs + team chat + scope-filtered user search over
//  /api/v1/messaging/*. Mirrors the dashboard ChatLauncher behaviour.
//

import Foundation

extension CRMService {
    // MARK: Mention picker / new-conversation search
    func searchMessagingUsers(q: String = "") async throws -> [MessagingScopedUser] {
        try await msgGetList("/api/v1/messaging/mentions/search", query: ["q": q])
    }

    // MARK: Threads (inbox)
    func listMessagingThreads() async throws -> [MessagingThread] {
        try await msgGetList("/api/v1/messaging/threads")
    }

    func createMessagingDm(otherUserId: String) async throws -> String {
        let created: MessagingThreadCreated = try await msgPost(
            "/api/v1/messaging/threads/dm",
            body: ["other_user_id": otherUserId]
        )
        return created.id
    }

    func createMessagingTeam(name: String, memberIds: [String]) async throws -> String {
        let created: MessagingThreadCreated = try await msgPost(
            "/api/v1/messaging/threads/team",
            body: ["name": name, "member_ids": memberIds]
        )
        return created.id
    }

    // MARK: Messages
    func listMessagingMessages(threadId: String, limit: Int = 100) async throws -> [MessagingMessage] {
        try await msgGetList(
            "/api/v1/messaging/threads/\(threadId)/messages",
            query: ["limit": String(limit)]
        )
    }

    func sendMessagingMessage(threadId: String, body: String, language: String? = nil) async throws -> MessagingMessage {
        var payload: [String: Any] = ["body": body]
        if let l = language { payload["language"] = l }
        return try await msgPost(
            "/api/v1/messaging/threads/\(threadId)/messages",
            body: payload
        )
    }

    func markMessagingThreadRead(threadId: String) async {
        // Fire-and-forget; if the backend hiccups the unread badge just
        // takes another poll cycle to clear, which is fine.
        try? await msgPostVoid("/api/v1/messaging/threads/\(threadId)/read", body: [:])
    }
}

// MARK: - File-scoped HTTP helpers
//
// Self-contained so we don't have to widen the visibility of CRMService's
// private get/post helpers. Uses the same CRMHTTP.send so 401 → silent
// token refresh still works for messaging calls.
private extension CRMService {
    func msgGetList<T: Codable>(_ path: String, query: [String: String] = [:]) async throws -> [T] {
        let req = try msgRequest(path: path, method: "GET", body: nil, query: query)
        let (data, resp) = try await CRMHTTP.send(req)
        try msgValidate(resp)
        return try msgDecodeList(T.self, from: data)
    }

    func msgPost<T: Codable>(_ path: String, body: [String: Any]) async throws -> T {
        let raw = body.isEmpty
            ? Data("{}".utf8)
            : try JSONSerialization.data(withJSONObject: body, options: [])
        let req = try msgRequest(path: path, method: "POST", body: raw)
        let (data, resp) = try await CRMHTTP.send(req)
        try msgValidate(resp)
        return try msgDecodeOne(T.self, from: data)
    }

    func msgPostVoid(_ path: String, body: [String: Any]) async throws {
        let data = body.isEmpty
            ? Data("{}".utf8)
            : try JSONSerialization.data(withJSONObject: body, options: [])
        let req = try msgRequest(path: path, method: "POST", body: data)
        let (_, resp) = try await CRMHTTP.send(req)
        try msgValidate(resp)
    }

    func msgRequest(path: String, method: String, body: Data?, query: [String: String] = [:]) throws -> URLRequest {
        let baseURL = URL(string: "https://kinematic-production.up.railway.app")!
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw CRMServiceError.server("Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = Session.sharedToken.isEmpty
            ? (UserDefaults.standard.string(forKey: "auth_token") ?? "")
            : Session.sharedToken
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let proj = Session.project, !proj.isEmpty { req.setValue(proj, forHTTPHeaderField: "X-Kinematic-Project") }
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }
        req.httpBody = body
        req.timeoutInterval = 30
        return req
    }

    func msgValidate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw CRMServiceError.badResponse(0) }
        if !(200..<300).contains(http.statusCode) {
            throw CRMServiceError.badResponse(http.statusCode)
        }
    }

    func msgDecodeList<T: Codable>(_ type: T.Type, from data: Data) throws -> [T] {
        let dec = JSONDecoder()
        if let env = try? dec.decode(APIEnvelope<[T]>.self, from: data), let p = env.data { return p }
        if let raw = try? dec.decode([T].self, from: data) { return raw }
        throw CRMServiceError.decodeFailed("Expected list of \(T.self)")
    }

    func msgDecodeOne<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let dec = JSONDecoder()
        if let env = try? dec.decode(APIEnvelope<T>.self, from: data), let p = env.data { return p }
        if let raw = try? dec.decode(T.self, from: data) { return raw }
        throw CRMServiceError.decodeFailed("Expected \(T.self)")
    }
}
