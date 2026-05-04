// DistributionAPI — thin async wrapper over /api/v1/salesman + /api/v1/distribution.
//
// We keep the production `KinematicRepository` untouched and use this dedicated
// client because the distribution endpoints all need:
//   - Idempotency-Key header on mutations
//   - snake_case decoding
//   - structured error reporting (so the UI can react to PRICE_MISMATCH 409)

import Foundation

enum DistributionAPIError: Error, LocalizedError {
    case http(Int, String?)
    case decoding(String)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .http(let s, let m): return "HTTP \(s)\(m.map { ": \($0)" } ?? "")"
        case .decoding(let m):    return "Decoding: \(m)"
        case .noResponse:         return "No response"
        }
    }
}

struct DistributionAPI {
    static let shared = DistributionAPI()
    private let baseURL = "https://kinematic-production.up.railway.app/api/v1"

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil, idempotencyKey: String? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw DistributionAPIError.noResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }
        if let key = idempotencyKey { req.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let enc = JSONEncoder()
            req.httpBody = try enc.encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            let serverMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?("error") as? String
            throw DistributionAPIError.http(status, serverMsg)
        }
        return data
    }

    private struct Envelope<U: Decodable>: Decodable {
        let success: Bool
        let data: U
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            let env = try decoder.decode(Envelope<T>.self, from: data)
            return env.data
        } catch {
            return try decoder.decode(T.self, from: data)
        }
    }

    // ── Reads ────────────────────────────────────────────────────────────────
    func routeToday() async throws -> RouteToday {
        let data = try await request("/salesman/route/today")
        return try decode(data)
    }
    func cartSuggest(outletId: String) async throws -> CartSuggest {
        let data = try await request("/salesman/outlets/\(outletId)/cart-suggest")
        return try decode(data)
    }
    func myOrders(status: String? = nil) async throws -> [DistOrder] {
        let q = status.map { "?status=\($0)" } ?? ""
        let data = try await request("/salesman/orders\(q)")
        return try decode(data)
    }
    func order(id: String) async throws -> DistOrder {
        let data = try await request("/salesman/orders/\(id)")
        return try decode(data)
    }

    // ── Mutations ────────────────────────────────────────────────────────────────
    func preview(_ input: OrderInput) async throws -> OrderPreview {
        let data = try await request("/salesman/orders/preview", method: "POST", body: input)
        return try decode(data)
    }
    func submitOrder(_ input: OrderInput, idempotencyKey: String) async throws -> DistOrder {
        let data = try await request("/salesman/orders", method: "POST", body: input, idempotencyKey: idempotencyKey)
        return try decode(data)
    }
    func submitPayment(_ input: PaymentInput, idempotencyKey: String) async throws -> DistributionPayment {
        let data = try await request("/salesman/payments", method: "POST", body: input, idempotencyKey: idempotencyKey)
        return try decode(data)
    }
    func submitReturn(_ input: ReturnInput, idempotencyKey: String) async throws -> DistributionReturn {
        let data = try await request("/salesman/returns", method: "POST", body: input, idempotencyKey: idempotencyKey)
        return try decode(data)
    }
    func signUpload(kind: String, ext: String? = nil) async throws -> SignedUpload {
        struct Body: Encodable { let kind: String; let ext: String? }
        let data = try await request("/salesman/uploads/sign", method: "POST", body: Body(kind: kind, ext: ext), idempotencyKey: UUID().uuidString)
        return try decode(data)
    }
}

/// Erases the static type so request() can encode any Encodable. Apple's
/// JSONEncoder requires a concrete type at the top level.
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
