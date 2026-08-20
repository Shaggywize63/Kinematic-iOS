// ExpensesAPI — thin async wrapper over /api/v1/expenses (Field Expense /
// Travel Claims). Mirrors DistributionAPI: dedicated client, snake_case
// decoding, structured errors, Idempotency-Key on creates. Client scoping is by
// the authenticated user (JWT), so no X-Client-Id header is needed here.

import Foundation

enum ExpensesAPIError: Error, LocalizedError {
    case http(Int, String?)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .http(let s, let m): return m ?? "Request failed (\(s))"
        case .noResponse:         return "No response"
        }
    }
}

struct ExpensesAPI {
    static let shared = ExpensesAPI()
    private let baseURL = "https://api.kinematicapp.com/api/v1"

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil, idempotencyKey: String? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw ExpensesAPIError.noResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        if let proj = Session.project, !proj.isEmpty { req.setValue(proj, forHTTPHeaderField: "X-Kinematic-Project") }
        if let orgId = Session.currentUser?.orgId { req.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        if let key = idempotencyKey { req.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(ExpenseAnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            let serverMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw ExpensesAPIError.http(status, serverMsg)
        }
        return data
    }

    private struct Envelope<U: Decodable>: Decodable { let success: Bool; let data: U }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        do { return try decoder.decode(Envelope<T>.self, from: data).data }
        catch { return try decoder.decode(T.self, from: data) }
    }

    // ── Policy ────────────────────────────────────────────────────────────────
    func policy() async throws -> ExpensePolicy {
        try decode(try await request("/expenses/policy"))
    }

    // ── Claims (mine) ─────────────────────────────────────────────────────────
    func myClaims(status: String? = nil) async throws -> [ExpenseClaim] {
        let q = status.map { "?status=\($0)" } ?? ""
        return try decode(try await request("/expenses/claims\(q)"))
    }
    func claim(id: String) async throws -> ExpenseClaim {
        try decode(try await request("/expenses/claims/\(id)"))
    }
    func createClaim(_ input: ExpenseClaimInput) async throws -> ExpenseClaim {
        try decode(try await request("/expenses/claims", method: "POST", body: input, idempotencyKey: UUID().uuidString))
    }
    func submit(id: String) async throws -> ExpenseClaim {
        try decode(try await request("/expenses/claims/\(id)/submit", method: "POST", body: EmptyBody(), idempotencyKey: "submit-\(id)"))
    }
    func cancel(id: String) async throws {
        _ = try await request("/expenses/claims/\(id)/cancel", method: "PATCH", body: EmptyBody())
    }

    // ── AI: mileage + receipt OCR ─────────────────────────────────────────────
    func mileage(fromISO: String, toISO: String) async throws -> ExpenseMileageResult {
        let f = fromISO.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? fromISO
        let t = toISO.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? toISO
        return try decode(try await request("/expenses/mileage?from=\(f)&to=\(t)"))
    }
    func scanReceipt(imageBase64: String, mediaType: String) async throws -> ExpenseReceiptFields {
        struct Body: Encodable { let image: String; let media_type: String }
        return try decode(try await request("/expenses/scan-receipt", method: "POST", body: Body(image: imageBase64, media_type: mediaType)))
    }

    // ── Approver ──────────────────────────────────────────────────────────────
    func pendingClaims() async throws -> [ExpenseClaim] {
        try decode(try await request("/expenses/claims/pending"))
    }
    func decide(id: String, decision: String, note: String?) async throws {
        struct Body: Encodable { let decision: String; let note: String? }
        _ = try await request("/expenses/claims/\(id)/decision", method: "PATCH", body: Body(decision: decision, note: note))
    }
}

private struct EmptyBody: Encodable {}

/// Erases the static type so request() can encode any Encodable.
private struct ExpenseAnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
        return cs
    }()
}
