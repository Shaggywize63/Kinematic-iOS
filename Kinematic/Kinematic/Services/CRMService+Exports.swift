//
//  CRMService+Exports.swift
//  Kinematic CRM
//
//  Server-side CSV export endpoints. These return the CSV text directly
//  (Content-Type: text/csv) rather than going through the JSON envelope
//  pipeline, so we hit them with a raw URLSession call and return Data.
//
//  - GET /api/v1/crm/deals/export      → Deals CSV (includes line items,
//                                        custom-field columns, lead phone)
//  - GET /api/v1/crm/activities/export → Activities CSV (includes lead_phone,
//                                        drops legacy Contact/Account/Deal
//                                        name columns)
//
//  Both honour the org's selected-client header so admins exporting from the
//  client picker see the client's data, matching the web behaviour.
//

import Foundation

extension CRMService {
    /// Download the deals export as raw CSV bytes (UTF-8).
    func exportDealsCSV() async throws -> Data {
        try await downloadExport(path: "/api/v1/crm/deals/export")
    }

    /// Download the activities export as raw CSV bytes (UTF-8).
    func exportActivitiesCSV() async throws -> Data {
        try await downloadExport(path: "/api/v1/crm/activities/export")
    }

    private func downloadExport(path: String) async throws -> Data {
        let token = Session.sharedToken.isEmpty
            ? (UserDefaults.standard.string(forKey: "auth_token") ?? "")
            : Session.sharedToken
        guard !token.isEmpty else { throw CRMServiceError.missingAuth }

        guard let url = URL(string: "https://kinematic-production.up.railway.app\(path)") else {
            throw CRMServiceError.server("Bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 60
        req.setValue("text/csv", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }
        if let cid = CRMClientScope.selectedClientId() {
            req.setValue(cid, forHTTPHeaderField: "X-Client-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CRMServiceError.badResponse(0)
        }
        if !(200..<300).contains(http.statusCode) {
            // The export endpoints can still emit JSON on error.
            if let env = try? JSONDecoder().decode(APIEnvelope<EmptyAck>.self, from: data),
               let msg = env.error ?? env.message {
                throw CRMServiceError.server(msg)
            }
            throw CRMServiceError.badResponse(http.statusCode)
        }
        return data
    }
}
