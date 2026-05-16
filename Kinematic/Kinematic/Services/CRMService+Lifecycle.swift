//
//  CRMService+Lifecycle.swift
//  Kinematic CRM
//
//  Step-2 lifecycle helpers for the lead surface: disqualify (PATCH) and
//  reopen (dedicated POST). Disqualify is a thin wrapper over the existing
//  generic updateLead(id:body:) — kept here so call-sites read as a single
//  semantic action rather than a bag of fields. Reopen needs its own POST
//  because the backend writes a distinct `lead_reopened` history row and
//  clears converted_*_id atomically.
//

import Foundation

extension CRMService {
    /// PATCH /api/v1/crm/leads/:id with { status, lost_reason }. Server
    /// stamps disqualified_at and writes a crm_lead_history row.
    func disqualifyLead(id: String, status: String, lostReason: String) async throws -> Lead {
        try await updateLead(id: id, body: [
            "status": status,
            "lost_reason": lostReason,
        ])
    }

    /// POST /api/v1/crm/leads/:id/reopen. Server clears converted_*_id,
    /// flips status='working', is_converted=false, nulls lost_reason +
    /// disqualified_at, and writes a `lead_reopened` history row.
    func reopenLead(id: String, reason: String? = nil) async throws -> Lead {
        var body: [String: Any] = [:]
        if let reason, !reason.isEmpty { body["reason"] = reason }
        return try await postJSONPublic("/api/v1/crm/leads/\(id)/reopen", body: body)
    }

    /// Public bridge to the private postJSON helper on CRMService. Kept as
    /// a thin shim so this extension doesn't need to duplicate the auth /
    /// envelope handling already living on the main file.
    private func postJSONPublic<T: Codable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = URL(string: "https://kinematic-production.up.railway.app")!.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = Session.sharedToken.isEmpty
            ? (UserDefaults.standard.string(forKey: "auth_token") ?? "")
            : Session.sharedToken
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            throw CRMServiceError.missingAuth
        }
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }
        req.timeoutInterval = 30
        req.httpBody = body.isEmpty
            ? Data("{}".utf8)
            : try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await CRMHTTP.send(req)
        guard let http = response as? HTTPURLResponse else {
            throw CRMServiceError.badResponse(0)
        }
        if !(200..<300).contains(http.statusCode) {
            // Try to pull a server error message out of the envelope.
            if let env = try? JSONDecoder().decode(APIEnvelope<EmptyAck>.self, from: data),
               let msg = env.error ?? env.message {
                throw CRMServiceError.server(msg)
            }
            throw CRMServiceError.badResponse(http.statusCode)
        }
        let decoder = JSONDecoder()
        if let env = try? decoder.decode(APIEnvelope<T>.self, from: data), let payload = env.data {
            return payload
        }
        return try decoder.decode(T.self, from: data)
    }
}
