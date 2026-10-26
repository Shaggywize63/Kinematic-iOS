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
        let req = try makeRequest(url: url, method: method, body: body, idempotencyKey: idempotencyKey, timeout: 20)
        let (data, status) = try await perform(req)
        if !(200..<300).contains(status) {
            let serverMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw DistributionAPIError.http(status, serverMsg)
        }
        return data
    }

    /// Builds the request: auth + routing headers, the Idempotency-Key, and the JSON body.
    ///
    /// The body is encoded with SORTED KEYS so the same value always produces the same bytes. The server's
    /// idempotency middleware compares a retry's body with the first attempt's, and a queued write is re-encoded
    /// from disk (in a later process) every time it is replayed — an unstable key order would turn a harmless
    /// replay into "Idempotency-Key reused with a different request body".
    private func makeRequest(url: URL, method: String, body: Encodable?, idempotencyKey: String?, timeout: TimeInterval,
                             clientId: String? = nil) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        if let proj = Session.project, !proj.isEmpty { req.setValue(proj, forHTTPHeaderField: "X-Kinematic-Project") }
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }
        if let key = idempotencyKey { req.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        // The company the rep is selling for. A queued write names the company it was taken for, so a later
        // replay cannot be re-filed under whichever company is active then.
        if let cid = clientId.flatMap({ SellingCompany.isUUID($0) ? $0 : nil }) {
            req.setValue(cid, forHTTPHeaderField: "X-Client-Id")
        } else if SellingCompany.appliesTo(path: url.path), let cid = SellingCompany.selectedId() {
            req.setValue(cid, forHTTPHeaderField: "X-Client-Id")
        }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            req.httpBody = try enc.encode(AnyEncodable(body))
        }
        return req
    }

    /// Sends `req` and returns the body and HTTP status (0 when there was no HTTP answer). On a 401 the access
    /// token is refreshed once (the same silent refresh the rest of the app uses) and the request goes out again
    /// with the new token — an hour-old token must not leave a collected payment stuck in the queue.
    private func perform(_ req: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            let refreshed = await KinematicRepository.shared.refreshAccessToken()
            if refreshed {
                var again = req
                again.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
                let (data2, response2) = try await URLSession.shared.data(for: again)
                return (data2, (response2 as? HTTPURLResponse)?.statusCode ?? 0)
            }
        }
        return (data, status)
    }

    /// What one call came to, without throwing: the HTTP status and body, or — when the request itself failed
    /// (no connection, timeout, a body that could not be encoded) — the error, with status 0.
    struct RawResponse {
        let status: Int
        let body: Data
        let error: Error?
    }

    /// One attempt of a request whose outcome the caller classifies itself (the offline queue: see
    /// `DistributionQueuePolicy`). Never throws.
    func send(path: String, method: String = "POST", queryItems: [URLQueryItem] = [], body: Encodable? = nil,
              idempotencyKey: String? = nil, timeout: TimeInterval = 20, clientId: String? = nil) async -> RawResponse {
        do {
            guard var components = URLComponents(string: "\(baseURL)\(path)") else {
                return RawResponse(status: 0, body: Data(), error: DistributionAPIError.noResponse)
            }
            if !queryItems.isEmpty { components.queryItems = queryItems }
            guard let url = components.url else {
                return RawResponse(status: 0, body: Data(), error: DistributionAPIError.noResponse)
            }
            let req = try makeRequest(url: url, method: method, body: body, idempotencyKey: idempotencyKey, timeout: timeout,
                                      clientId: clientId)
            let (data, status) = try await perform(req)
            return RawResponse(status: status, body: data, error: nil)
        } catch {
            return RawResponse(status: 0, body: Data(), error: error)
        }
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
    /// Companies the signed-in rep may sell for. Nil when the call fails (the picker then stays hidden).
    func myCompanies() async -> MyCompanies? {
        guard let data = try? await request("/companies/mine") else { return nil }
        return try? decode(data)
    }
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

    // ── Outlet picker + outstanding (online only; nothing here is cached) ─────────
    /// Outlets in the rep's scope (today's route-plan outlets first), `name` / `code` search, at most 100 — the
    /// picker behind "Collect Payment" and "Book Order". Never throws: a missing connection is `.offline`.
    func searchOutlets(query: String?, limit: Int = OutletPickerLogic.pageSize) async -> OutletSearchResult {
        var items: [URLQueryItem] = []
        if let q = query, !q.isEmpty { items.append(URLQueryItem(name: "search", value: q)) }
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        let response = await send(path: "/salesman/outlets", method: "GET", queryItems: items)
        if let error = response.error {
            if DistributionQueuePolicy.isOffline(error) { return .offline }
            return .failed(DistributionQueuePolicy.message(forThrown: error))
        }
        if (200..<300).contains(response.status) {
            return .found(SalesmanJSON.outlets(fromData: response.body))
        }
        return .failed(DistributionQueuePolicy.serverMessage(body: response.body, httpStatus: response.status))
    }

    /// Proposes a new outlet for a manager to approve. Never throws; no connection is `.offline`.
    func createOutlet(_ input: NewOutletInput) async -> OutletCreateResult {
        let response = await send(path: "/salesman/outlets", method: "POST", body: input)
        if let error = response.error {
            return DistributionQueuePolicy.isOffline(error) ? .offline : .failed(DistributionQueuePolicy.message(forThrown: error))
        }
        guard (200..<300).contains(response.status) else {
            return .failed(DistributionQueuePolicy.serverMessage(body: response.body, httpStatus: response.status))
        }
        guard let outlet: ProposedOutlet = try? decode(response.body) else {
            return .failed("The server sent an empty reply. Please try again.")
        }
        return .created(outlet)
    }

    /// The rep's own outlets that are waiting for approval or were refused. Empty when it can't be loaded.
    func proposedOutlets() async -> [ProposedOutlet] {
        let response = await send(path: "/salesman/outlets/proposed", method: "GET")
        guard response.error == nil, (200..<300).contains(response.status) else { return [] }
        return (try? decode(response.body)) ?? []
    }

    /// An outlet's balance and open invoices (oldest first). Online only: money data must not be stale, so it is
    /// never cached and offline is reported as such.
    func outstanding(outletId: String) async -> OutstandingResult {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let safeId = outletId.addingPercentEncoding(withAllowedCharacters: allowed) ?? outletId
        let response = await send(path: "/salesman/outlets/\(safeId)/outstanding", method: "GET")
        if let error = response.error {
            return DistributionQueuePolicy.isOffline(error) ? .offline : .unavailable
        }
        guard (200..<300).contains(response.status), let parsed = SalesmanJSON.outstanding(fromData: response.body) else {
            return .unavailable
        }
        return .loaded(parsed)
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

    // ── Supply Chain — batch & expiry (FEFO batches + receiving/GRN) ───────────
    /// Stock batches for a distributor. `status` filters active | near_expiry |
    /// expired | all (default all when nil); `nearDays` overrides the server's
    /// near-expiry window. Rows include days_to_expiry for FEFO ordering.
    func fetchBatches(distributorId: String, status: String? = nil, nearDays: Int? = nil) async throws -> [StockBatch] {
        var q = "?distributor_id=\(distributorId)"
        if let status = status, !status.isEmpty { q += "&status=\(status)" }
        if let nearDays = nearDays { q += "&near_days=\(nearDays)" }
        let data = try await request("/distribution/batches\(q)")
        return try decode(data)
    }
    /// Near-expiry / expired rollup for a distributor. `withinDays` sets the
    /// near-expiry window (server default when nil). Backs the alerts summary.
    func fetchBatchAlerts(distributorId: String, withinDays: Int? = nil) async throws -> BatchAlerts {
        var q = "?distributor_id=\(distributorId)"
        if let withinDays = withinDays { q += "&within_days=\(withinDays)" }
        let data = try await request("/distribution/batches/alerts\(q)")
        return try decode(data)
    }
    /// Receive stock (GRN) against a distributor — opens (or tops up) a batch.
    /// The Idempotency-Key guards against a double-submit on a slow network.
    /// Returns the created / updated batch (the `balance` field is discarded).
    func receiveBatch(_ input: ReceiveBatchInput, idempotencyKey: String) async throws -> StockBatch {
        let data = try await request("/distribution/receiving", method: "POST", body: input, idempotencyKey: idempotencyKey)
        let result: ReceiveBatchResult = try decode(data)
        return result.batch
    }
}

/// Erases the static type so request() can encode any Encodable. Apple's
/// JSONEncoder requires a concrete type at the top level.
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
