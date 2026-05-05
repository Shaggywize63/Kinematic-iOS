import Foundation
import Combine
import SwiftUI

@MainActor
final class DistributionViewModel: ObservableObject {
    @Published var route: RouteToday?
    @Published var suggest: CartSuggest?
    @Published var cartQty: [String: Int] = [:]
    @Published var preview: OrderPreview?
    @Published var previewing = false
    @Published var previewError: String?

    @Published var orders: [DistOrder] = []
    @Published var loadingOrders = false
    @Published var currentOrder: DistOrder?

    @Published var submitting = false
    @Published var submitError: String?
    @Published var lastQueuedOrder: PendingOrder?

    private let api = DistributionAPI.shared
    private let cache = OrderCache.shared

    func loadRoute() async {
        do { route = try await api.routeToday() } catch { route = nil }
    }

    func loadSuggest(outletId: String) async {
        do {
            let s = try await api.cartSuggest(outletId: outletId)
            suggest = s
            for r in s.recommendations where cartQty[r.sku_id] == nil {
                cartQty[r.sku_id] = r.suggested_qty
            }
        } catch { suggest = nil }
    }

    func setQty(skuId: String, qty: Int) {
        if qty <= 0 { cartQty.removeValue(forKey: skuId) } else { cartQty[skuId] = qty }
    }

    func clearCart() {
        cartQty = [:]; preview = nil; previewError = nil; submitError = nil
    }

    func runPreview(outletId: String) async {
        let items = cartQty.compactMap { (skuId, qty) -> CartLineInput? in
            guard qty > 0 else { return nil }
            return CartLineInput(sku_id: skuId, qty: qty, uom: nil)
        }
        guard !items.isEmpty else { preview = nil; return }
        previewing = true; previewError = nil
        defer { previewing = false }
        let outlet = route?.outlets.first(where: { $0.id == outletId })
        let gps = (outlet?.lat).flatMap { lat in (outlet?.lng).map { GeoPoint(lat: lat, lng: $0) } }
        let input = OrderInput(outlet_id: outletId, distributor_id: nil, visit_id: outlet?.route_visit_id, items: items, gps: gps, notes: nil, client_total: nil)
        do {
            preview = try await api.preview(input)
        } catch {
            previewError = error.localizedDescription
        }
    }

    func submit(outletId: String, outletName: String?, visitId: String?) async {
        let items = cartQty.compactMap { (skuId, qty) -> CartLineInput? in
            guard qty > 0 else { return nil }
            return CartLineInput(sku_id: skuId, qty: qty, uom: nil)
        }
        guard !items.isEmpty else { submitError = "Cart is empty"; return }
        submitting = true; submitError = nil
        defer { submitting = false }

        let outlet = route?.outlets.first(where: { $0.id == outletId })
        let gps = (outlet?.lat).flatMap { lat in (outlet?.lng).map { GeoPoint(lat: lat, lng: $0) } }
        let total = preview?.totals.grand_total
        let input = OrderInput(outlet_id: outletId, distributor_id: nil, visit_id: visitId, items: items, gps: gps, notes: nil, client_total: total)

        let pending = cache.enqueueOrder(input: input, clientTotal: total ?? 0, outletName: outletName, visitId: visitId)
        lastQueuedOrder = pending

        do {
            _ = try await api.submitOrder(input, idempotencyKey: pending.idempotencyKey)
            cache.markOrderSynced(pending.id)
        } catch {
            cache.recordOrderError(pending.id, error: error.localizedDescription)
            submitError = "Queued — will sync when network is available."
        }
        clearCart()
    }

    func loadOrders() async {
        loadingOrders = true
        do { orders = try await api.myOrders() } catch {}
        loadingOrders = false
    }

    func loadOrder(_ id: String) async {
        do { currentOrder = try await api.order(id: id) } catch { currentOrder = nil }
    }

    func flushQueue() async {
        let p = cache.pendingForCurrentUser()
        for row in p.orders {
            do {
                _ = try await api.submitOrder(row.input, idempotencyKey: row.idempotencyKey)
                cache.markOrderSynced(row.id)
            } catch { cache.recordOrderError(row.id, error: error.localizedDescription) }
        }
        for row in p.payments {
            do {
                _ = try await api.submitPayment(row.input, idempotencyKey: row.idempotencyKey)
                cache.markPaymentSynced(row.id)
            } catch { cache.recordPaymentError(row.id, error: error.localizedDescription) }
        }
        for row in p.returns {
            do {
                _ = try await api.submitReturn(row.input, idempotencyKey: row.idempotencyKey)
                cache.markReturnSynced(row.id)
            } catch { cache.recordReturnError(row.id, error: error.localizedDescription) }
        }
    }
}
