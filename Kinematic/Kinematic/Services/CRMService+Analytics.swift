//
//  CRMService+Analytics.swift
//  Kinematic CRM
//
//  Read-only fetch helpers for the extended /api/v1/crm/analytics surface
//  that powers the Lead Analytics view. Mirrors the dashboard's
//  `crmAnalyticsExt` (lead-velocity, lost-reasons, stage-conversion,
//  leads-at-risk) plus `crmAnalytics.leadSourceRoi`.
//
//  The pipeline-funnel widget reuses the existing `CRMService.funnel()`
//  declared on the main service — it already returns `FunnelStageMetric`.
//
//  Pattern mirrors CRMService+Edit / CRMService+Phase2: a thin extension
//  with its own private auth + envelope helpers so we never touch the
//  main service file.
//

import Foundation
import Combine

extension CRMService {
    /// GET /api/v1/crm/analytics/lead-velocity?months=N
    func leadVelocity(months: Int = 6) async throws -> [LeadVelocityPoint] {
        try await analyticsGetList("/api/v1/crm/analytics/lead-velocity", query: ["months": String(months)])
    }

    /// GET /api/v1/crm/analytics/lost-reasons
    func lostReasons(from: String? = nil, to: String? = nil) async throws -> [ReasonCount] {
        var q: [String: String] = [:]
        if let from { q["from"] = from }
        if let to   { q["to"]   = to }
        return try await analyticsGetList("/api/v1/crm/analytics/lost-reasons", query: q)
    }

    /// GET /api/v1/crm/analytics/stage-conversion
    func stageConversion(pipelineId: String? = nil) async throws -> [StageConversionRow] {
        var q: [String: String] = [:]
        if let pipelineId { q["pipeline_id"] = pipelineId }
        return try await analyticsGetList("/api/v1/crm/analytics/stage-conversion", query: q)
    }

    /// GET /api/v1/crm/analytics/leads-at-risk?score=60&idle_days=14
    func leadsAtRisk(score: Int = 60, idleDays: Int = 14) async throws -> [LeadAtRisk] {
        try await analyticsGetList(
            "/api/v1/crm/analytics/leads-at-risk",
            query: ["score": String(score), "idle_days": String(idleDays)]
        )
    }

    /// GET /api/v1/crm/analytics/lead-source-roi
    func leadSourceRoi() async throws -> [LeadSourceROIRow] {
        try await analyticsGetList("/api/v1/crm/analytics/lead-source-roi")
    }

    /// Generic report fetch for the Reports hub — exposes the file-private
    /// `analyticsGetList` to other files. Returns each row as a loose JSON map
    /// so any analytics endpoint can be rendered as a table + exported.
    func analyticsReport(_ path: String, query: [String: String] = [:]) async throws -> [[String: AnyCodableValue]] {
        try await analyticsGetList(path, query: query)
    }
}

// MARK: - Private helpers (file-scoped, same shape as CRMService+Phase2)

private extension CRMService {
    func analyticsGetList<T: Codable>(_ path: String, query: [String: String] = [:]) async throws -> [T] {
        let url = try AnalyticsHelpers.buildURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        AnalyticsHelpers.applyHeaders(to: &req)
        let (data, resp) = try await CRMHTTP.send(req)
        try AnalyticsHelpers.validate(resp, data: data)
        return try AnalyticsHelpers.decodeListEnvelope(T.self, from: data)
    }
}

private enum AnalyticsHelpers {
    static let baseHostURL: URL = URL(string: "https://kinematic-production.up.railway.app")!

    static func buildURL(path: String, query: [String: String]) throws -> URL {
        var components = URLComponents(url: baseHostURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
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

    static func decodeListEnvelope<T: Codable>(_ type: T.Type, from data: Data) throws -> [T] {
        let decoder = JSONDecoder()
        if let env = try? decoder.decode(APIEnvelope<[T]>.self, from: data), let p = env.data {
            return p
        }
        if let raw = try? decoder.decode([T].self, from: data) { return raw }
        throw CRMServiceError.decodeFailed("Expected list of \(T.self)")
    }
}
