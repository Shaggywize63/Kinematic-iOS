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
    /// `preferKey` lets the caller name the field they want to surface when
    /// the backend returns an object with multiple chart series side by
    /// side (e.g. lead-tracker → `daily`). Falls back to the first
    /// non-empty array field when the preferred key is absent.
    func analyticsReport(_ path: String, query: [String: String] = [:], preferKey: String? = nil) async throws -> [[String: AnyCodableValue]] {
        try await analyticsGetList(path, query: query, preferKey: preferKey)
    }
}

// MARK: - Private helpers (file-scoped, same shape as CRMService+Phase2)

private extension CRMService {
    func analyticsGetList<T: Codable>(_ path: String, query: [String: String] = [:], preferKey: String? = nil) async throws -> [T] {
        let url = try AnalyticsHelpers.buildURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        AnalyticsHelpers.applyHeaders(to: &req)
        let (data, resp) = try await CRMHTTP.send(req)
        try AnalyticsHelpers.validate(resp, data: data)
        return try AnalyticsHelpers.decodeListEnvelope(T.self, from: data, preferKey: preferKey)
    }
}

private enum AnalyticsHelpers {
    static let baseHostURL: URL = URL(string: "https://api.kinematicapp.com")!

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

    static func decodeListEnvelope<T: Codable>(_ type: T.Type, from data: Data, preferKey: String? = nil) throws -> [T] {
        let decoder = JSONDecoder()
        // Preferred shapes — `{ success, data: [...] }` envelope or a raw
        // top-level array. Every legacy report uses one of these.
        if let env = try? decoder.decode(APIEnvelope<[T]>.self, from: data), let p = env.data {
            return p
        }
        if let raw = try? decoder.decode([T].self, from: data) { return raw }

        // Some reports (lead-tracker, team-performance, team-daily, …)
        // return an OBJECT inside `data` — not a flat array — because
        // the response carries several chart series side-by-side. The
        // generic reports table can still render those, but the
        // decoder was throwing a hard error on every object-shaped
        // response ("Could not read server response: Expected list of
        // Dictionary<String, AnyCodableValue>"). Try to extract the
        // first array-valued field via a raw JSONSerialization pass;
        // if none exists, wrap the whole object as a single row so
        // the rep sees something instead of the red error card.
        if T.self == [String: AnyCodableValue].self,
           let json = try? JSONSerialization.jsonObject(with: data),
           let inner = (json as? [String: Any])?["data"] ?? json as? [String: Any] {
            if let dict = inner as? [String: Any] {
                // Try the caller's preferred key first so reports with
                // multiple series side by side (lead-tracker, team-
                // performance) surface the right table by default.
                if let pk = preferKey, let arr = dict[pk] as? [[String: Any]], !arr.isEmpty {
                    if let bytes = try? JSONSerialization.data(withJSONObject: arr),
                       let rows = try? decoder.decode([[String: AnyCodableValue]].self, from: bytes) {
                        return rows as! [T]
                    }
                }
                // Fallback: first array of dicts in alphabetical order.
                for key in dict.keys.sorted() {
                    if let arr = dict[key] as? [[String: Any]], !arr.isEmpty {
                        if let bytes = try? JSONSerialization.data(withJSONObject: arr),
                           let rows = try? decoder.decode([[String: AnyCodableValue]].self, from: bytes) {
                            return rows as! [T]
                        }
                    }
                }
                // No array field — fall back to a single summary row
                // (each top-level key becomes a column).
                if let bytes = try? JSONSerialization.data(withJSONObject: dict),
                   let row = try? decoder.decode([String: AnyCodableValue].self, from: bytes) {
                    return [row] as! [T]
                }
            }
        }
        throw CRMServiceError.decodeFailed("Expected list of \(T.self)")
    }
}
