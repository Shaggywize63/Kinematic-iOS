// DistributionAPI — thin async wrapper over /api/v1/salesman + /api/v1/distribution.
//
// We keep the production `KinematicRepository` untouched and use this dedicated
// client because the distribution endpoints all need:
//   - Idempotency-Key header on mutations
//   - snake_case decoding
//   - structured error reporting (so the UI can react to PRICE_MISMATCH 409)

import Foundation
import Combine

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
    private let baseURL = "https://api.kinematicapp.com/api/v1"

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil, idempotencyKey: String? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw DistributionAPIError.noResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        if let proj = Session.project, !proj.isEmpty { req.setValue(proj, forHTTPHeaderField: "X-Kinematic-Project") }
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
            let serverMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
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

    /// Full orderable SKU catalogue for an outlet (browse beyond reorder
    /// suggestions). Mirrors `cartSuggest`'s decode path.
    func catalogue(outletId: String) async throws -> OrderCatalogue {
        let data = try await request("/salesman/outlets/\(outletId)/catalogue")
        return try decode(data)
    }

    /// GST invoice document for an order. The endpoint returns 404 until the
    /// order is invoiced, so we translate that single case into `nil` and let
    /// every other error propagate for the caller to surface.
    func orderInvoice(orderId: String) async throws -> Invoice? {
        do {
            let data = try await request("/salesman/orders/\(orderId)/invoice")
            return try decode(data)
        } catch DistributionAPIError.http(404, _) {
            return nil
        }
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

    /// Cancel an order (Android parity — POST /salesman/orders/{id}/cancel).
    /// Optional reason is sent as JSON body; idempotency-key prevents
    /// double-fire when the user mashes the button on a slow network.
    func cancelOrder(id: String, reason: String? = nil) async throws -> DistOrder {
        struct Body: Encodable { let reason: String? }
        let key = "cancel-\(id)-\(UUID().uuidString.prefix(8))"
        let data = try await request("/salesman/orders/\(id)/cancel",
                                     method: "POST",
                                     body: Body(reason: reason),
                                     idempotencyKey: String(key))
        return try decode(data)
    }

    /// Mark a visit checkin (Android parity — POST /salesman/visits/{id}/checkin).
    /// Drives the server-side geofence pass flag for any orders booked next.
    func visitCheckin(visitId: String, lat: Double, lng: Double) async throws {
        struct Body: Encodable { let lat: Double; let lng: Double }
        _ = try await request("/salesman/visits/\(visitId)/checkin",
                              method: "POST",
                              body: Body(lat: lat, lng: lng),
                              idempotencyKey: "checkin-\(visitId)")
    }

    // ── Van load (salesman surface) ───────────────────────────────────────────
    /// The rep's open load for today, or `nil` when they haven't loaded yet.
    /// The endpoint returns `data: null` in that case, decoded straight into the
    /// optional (Envelope<VanLoad?> → nil), so no 404 catch is needed.
    func vanLoadToday() async throws -> VanLoad? {
        let data = try await request("/salesman/van-load/today")
        return try decode(data)
    }
    /// Open a van load (day-start load-in). Min 1 item, loaded_qty ≥ 0.
    func createVanLoad(_ input: VanLoadCreateInput, idempotencyKey: String) async throws -> VanLoad {
        let data = try await request("/salesman/van-load", method: "POST", body: input, idempotencyKey: idempotencyKey)
        return try decode(data)
    }
    /// Reconcile a van load (end-of-day returned + damaged per SKU). Server
    /// derives sold = loaded − returned − damaged and flips status → reconciled.
    func reconcileVanLoad(id: String, input: VanReconcileInput, idempotencyKey: String) async throws -> VanLoad {
        let data = try await request("/salesman/van-load/\(id)/reconcile", method: "POST", body: input, idempotencyKey: idempotencyKey)
        return try decode(data)
    }

    // ── Distributor stock (read-only on-hand) ─────────────────────────────────
    /// Distributor picker source. Degrades to an empty list when the endpoint is
    /// missing (404) or the reading user lacks the module (403) — the caller
    /// shows a "no distributors" message instead of crashing.
    func distributors() async throws -> [DistributorLite] {
        do {
            let data = try await request("/distribution/distributors")
            return try decode(data)
        } catch DistributionAPIError.http(404, _), DistributionAPIError.http(403, _) {
            return []
        }
    }
    /// Per-SKU on-hand rows for a distributor. `lowOnly` appends `low=1` to
    /// filter to available ≤ 0.
    func distributorStock(distributorId: String, lowOnly: Bool = false) async throws -> [DistributorStockRow] {
        var q = "?distributor_id=\(distributorId)"
        if lowOnly { q += "&low=1" }
        let data = try await request("/distribution/stock\(q)")
        return try decode(data)
    }

    // ── SKU catalogue (van load-in picker) ────────────────────────────────────
    /// Full SKU list. The `inventory` module is universal, so this is reachable
    /// for any distribution client. Response may be enveloped or a bare array —
    /// `decode()` handles both.
    func skus() async throws -> [SkuLite] {
        let data = try await request("/skus")
        return try decode(data)
    }

    // ── Damage / expiry register (distributor damaged-stock log) ──────────────
    /// Log a damaged / expired / breakage entry against a distributor. The
    /// Idempotency-Key guards against a double-submit on a slow network.
    func logDamage(_ input: DamageEntryInput, idempotencyKey: String) async throws -> DamageEntry {
        let data = try await request("/distribution/damage", method: "POST", body: input, idempotencyKey: idempotencyKey)
        return try decode(data)
    }
    /// Recent damage-register entries, optionally scoped to one distributor.
    func damageEntries(distributorId: String? = nil) async throws -> [DamageEntry] {
        let q = distributorId.map { "?distributor_id=\($0)" } ?? ""
        let data = try await request("/distribution/damage\(q)")
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
