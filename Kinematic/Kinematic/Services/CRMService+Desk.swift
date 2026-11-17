//
//  CRMService+Desk.swift
//  Kinematic CRM
//
//  Networking for the pharma "Calling Desk" (/api/v1/crm/desk/*) — a daily
//  tele-calling worklist for Maa Mansha Pharma. Mirrors the already-deployed
//  backend + web dashboard.
//
//  Pattern mirrors CRMService+Analytics / CRMService+Phase2: a thin extension
//  with its own file-scoped auth + envelope helpers so we never touch the main
//  service file. Auth / tenant headers (Authorization, X-Org-Id, X-Client-Id,
//  X-Kinematic-Project) are attached by `DeskHelpers.applyHeaders` exactly like
//  the main `CRMService.makeRequest`, so callers never set them by hand.
//

import Foundation

extension CRMService {

    /// GET /api/v1/crm/desk/call-list — the operator's daily worklist.
    /// `mine` force-scopes to the caller's own assigned tasks (the backend also
    /// scopes a non-admin operator server-side).
    func deskCallList(date: String,
                      status: DeskStatus? = nil,
                      query search: String? = nil,
                      mine: Bool = true,
                      limit: Int = 500) async throws -> DeskCallListPage {
        var q: [String: String] = ["date": date, "limit": String(limit)]
        // nil = "All"; any specific status (incl. `pending`) narrows the list.
        if let status { q["status"] = status.rawValue }
        if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            q["q"] = search
        }
        if mine { q["mine"] = "1" }
        return try await DeskHelpers.getObject(path: "/api/v1/crm/desk/call-list", query: q)
    }

    /// GET /api/v1/crm/desk/summary — the day's roll-up for the header strip.
    func deskSummary(date: String) async throws -> DeskDaySummary {
        try await DeskHelpers.getObject(path: "/api/v1/crm/desk/summary", query: ["date": date])
    }

    /// POST /api/v1/crm/desk/generate — build today's list (ADMIN ONLY). The
    /// backend answers 403 for a non-admin operator; that surfaces as
    /// `CRMServiceError.serverStatus(403, …)` so the caller can show a friendly
    /// "admins only" message instead of a raw error.
    @discardableResult
    func deskGenerate(date: String) async throws -> DeskGenerateResult {
        try await DeskHelpers.sendObject(path: "/api/v1/crm/desk/generate",
                                         method: "POST",
                                         body: ["date": date])
    }

    /// PATCH /api/v1/crm/desk/call-list/{id} — disposition a call. `orderValue`
    /// is sent only for Order Taken (nil clears it server-side for the others).
    @discardableResult
    func deskUpdateTask(id: String,
                        status: DeskStatus,
                        orderValue: Double? = nil,
                        notes: String? = nil) async throws -> DeskCallTask {
        var body: [String: Any] = ["status": status.rawValue]
        // Always send order_value so switching away from Order Taken clears it.
        body["order_value"] = orderValue ?? NSNull()
        body["notes"] = (notes?.isEmpty == false) ? (notes as Any) : NSNull()
        let result: DeskPatchResult = try await DeskHelpers.sendObject(
            path: "/api/v1/crm/desk/call-list/\(id)",
            method: "PATCH",
            body: body
        )
        return result.task
    }
}

// MARK: - File-scoped request helpers (same shape as AnalyticsHelpers)

private enum DeskHelpers {
    static let baseHostURL: URL = URL(string: "https://api.kinematicapp.com")!

    /// GET → decode the envelope's `data` object into `T`.
    static func getObject<T: Codable>(path: String, query: [String: String] = [:]) async throws -> T {
        let url = try buildURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        applyHeaders(to: &req)
        let (data, resp) = try await CRMHTTP.send(req)
        try validate(resp, data: data)
        return try decodeObjectEnvelope(T.self, from: data)
    }

    /// POST / PATCH a JSON body → decode the envelope's `data` object into `T`.
    static func sendObject<T: Codable>(path: String, method: String, body: [String: Any]) async throws -> T {
        // Mirror the main service's local read-only guard so "View as User"
        // sessions see a clean message rather than a server 403.
        if ImpersonationState.readOnly {
            throw CRMServiceError.server("You're viewing as another user (read-only). You can't make changes in this mode.")
        }
        let url = try buildURL(path: path, query: [:])
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.httpBody = body.isEmpty ? Data("{}".utf8) : try JSONSerialization.data(withJSONObject: body, options: [])
        applyHeaders(to: &req)
        let (data, resp) = try await CRMHTTP.send(req)
        try validate(resp, data: data)
        return try decodeObjectEnvelope(T.self, from: data)
    }

    static func buildURL(path: String, query: [String: String]) throws -> URL {
        var components = URLComponents(url: baseHostURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw CRMServiceError.server("Bad URL") }
        return url
    }

    /// Identical header contract to `CRMService.makeRequest`, including the
    /// org-admin `X-Client-Id` scope header (mirrors the dashboard).
    static func applyHeaders(to req: inout URLRequest) {
        let token = Session.sharedToken.isEmpty
            ? (UserDefaults.standard.string(forKey: "auth_token") ?? "")
            : Session.sharedToken
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let orgId = Session.currentUser?.orgId { req.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        if let cid = CRMClientScope.selectedClientId(), !cid.isEmpty {
            req.setValue(cid, forHTTPHeaderField: "X-Client-Id")
        }
        if let proj = Session.project, !proj.isEmpty { req.setValue(proj, forHTTPHeaderField: "X-Kinematic-Project") }
    }

    /// Validate HTTP status, preserving the status code via `.serverStatus` so
    /// callers can branch on 403 (admin-only generate) while still surfacing the
    /// backend message.
    static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw CRMServiceError.badResponse(0) }
        guard !(200..<300).contains(http.statusCode) else { return }
        let msg = (try? JSONDecoder().decode(APIEnvelope<EmptyAck>.self, from: data))
            .flatMap { $0.error ?? $0.message }
        if let msg { throw CRMServiceError.serverStatus(http.statusCode, msg) }
        throw CRMServiceError.badResponse(http.statusCode)
    }

    /// Decode `{ success, data: {...} }`, falling back to a raw top-level object.
    static func decodeObjectEnvelope<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
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
