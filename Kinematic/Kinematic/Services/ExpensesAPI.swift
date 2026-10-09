// ExpensesAPI — thin async wrapper over /api/v1/expenses (Field Expense /
// Travel Claims). Mirrors DistributionAPI: dedicated client, snake_case
// decoding, structured errors, Idempotency-Key on creates. Client scoping is by
// the authenticated user (JWT), so no X-Client-Id header is needed here.
//
// Failures never hide: a non-2xx response throws an ExpensesAPIError carrying the
// server's own message (written for the user, e.g. "Add a remark explaining why
// this claim is rejected."), and callers show it.

import Foundation

enum ExpensesAPIError: Error, LocalizedError {
    case http(Int, String?)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .http(let s, let m): return ExpenseErrors.message(serverMessage: m, status: s)
        case .noResponse:         return "No response"
        }
    }
}

struct ExpensesAPI {
    static let shared = ExpensesAPI()
    private let baseURL = "https://api.kinematicapp.com/api/v1"

    private func makeRequest(_ path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw ExpensesAPIError.noResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        if let proj = Session.project, !proj.isEmpty { req.setValue(proj, forHTTPHeaderField: "X-Kinematic-Project") }
        if let orgId = Session.currentUser?.orgId { req.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            throw ExpensesAPIError.http(status, ExpenseErrors.serverMessage(in: data))
        }
        return data
    }

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil, idempotencyKey: String? = nil) async throws -> Data {
        var req = try makeRequest(path, method: method)
        if let key = idempotencyKey { req.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(ExpenseAnyEncodable(body))
        }
        return try await send(req)
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
    /// Edit a claim's title/lines before it is approved — a draft, a submitted
    /// claim, or a rejected one being fixed for resubmission.
    func updateClaim(id: String, _ input: ExpenseClaimInput) async throws -> ExpenseClaim {
        try decode(try await request("/expenses/claims/\(id)", method: "PATCH", body: input))
    }
    /// Submit a draft, or resubmit a rejected claim. A "block" policy answers 422.
    func submit(id: String) async throws -> ExpenseClaim {
        try decode(try await request("/expenses/claims/\(id)/submit", method: "POST", body: EmptyBody(), idempotencyKey: "submit-\(id)-\(UUID().uuidString)"))
    }
    func cancel(id: String) async throws {
        _ = try await request("/expenses/claims/\(id)/cancel", method: "PATCH", body: EmptyBody())
    }
    /// Dry-run the policy against unsaved lines so problems show before submitting.
    func check(items: [ExpenseClaimItemInput], claimId: String?) async throws -> ExpenseClaimCheck {
        try decode(try await request("/expenses/claims/check", method: "POST", body: ExpenseClaimCheckInput(items: items, claim_id: claimId)))
    }

    // ── Receipts + mileage ────────────────────────────────────────────────────
    /// Upload a receipt photo/PDF (multipart field "file", 10 MB max). Returns the
    /// stored reference to put on the line, a link to show it, and the read of it.
    /// `scan` picks the read: `.receipt` (default) reads it as a receipt; `.storeOnly` stores the file without a
    /// read (`?scan=0`, e.g. an odometer photo is not a receipt); `.odometer` reads the odometer number
    /// (`?scan=odometer`) and answers it in `odometer`.
    func uploadReceipt(data: Data, filename: String, mime: String, scan: ExpenseUploadScan = .receipt) async throws -> ExpenseUploadedReceipt {
        var req = try makeRequest(scan.path, method: "POST")
        req.timeoutInterval = 60
        let boundary = "kinematic-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        add("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        add("\r\n--\(boundary)--\r\n")
        req.httpBody = body
        return try decode(try await send(req))
    }

    /// The caller's own odometer readings, newest first (`GET /expenses/odometer-history`). `from` / `to` are
    /// optional ISO dates; they are left off the request when nil.
    func odometerHistory(limit: Int = 50, from: String? = nil, to: String? = nil) async throws -> [ExpenseOdometerEntry] {
        var q = "?limit=\(limit)"
        if let f = from, !f.isEmpty { q += "&from=" + (f.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? f) }
        if let t = to, !t.isEmpty { q += "&to=" + (t.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? t) }
        return try decode(try await request("/expenses/odometer-history\(q)"))
    }

    func mileage(fromISO: String, toISO: String) async throws -> ExpenseMileageResult {
        let f = fromISO.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? fromISO
        let t = toISO.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? toISO
        return try decode(try await request("/expenses/mileage?from=\(f)&to=\(t)"))
    }

    // ── Approver ──────────────────────────────────────────────────────────────
    func pendingClaims() async throws -> [ExpenseClaim] {
        try decode(try await request("/expenses/claims/pending"))
    }
    /// Approve or reject, optionally line by line. Rejecting needs a remark.
    @discardableResult
    func decide(id: String, decision: String, note: String?, items: [ExpenseLineDecisionInput]? = nil) async throws -> ExpenseDecisionResult {
        try decode(try await request("/expenses/claims/\(id)/decision", method: "PATCH",
                                     body: ExpenseDecisionInput(decision: decision, note: note, items: items)))
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
