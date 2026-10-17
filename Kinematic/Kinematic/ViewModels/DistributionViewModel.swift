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

    private let api = DistributionAPI.shared

    // ── Company the rep is taking orders for ─────────────────────────
    /// The companies the rep may sell for and the one orders are being taken for.
    @Published var companies: [Company] = []
    @Published var activeCompanyId: String?
    /// True only when the rep has more than one company, i.e. a real choice.
    @Published var companyPickRequired = false
    @Published var companiesLoaded = false

    var activeCompanyName: String? { companies.first { $0.id == activeCompanyId }?.name }

    /// Loads the rep's companies and reconciles the stored selection with them: a stale pick (a company the rep no
    /// longer has) is dropped, and a rep with exactly one company is set to it automatically. When the list can't be
    /// fetched (offline) the screen carries on with whatever was last selected.
    func loadCompanies() async {
        guard let mine = await api.myCompanies() else {
            activeCompanyId = SellingCompany.selectedId()
            companiesLoaded = true
            return
        }
        let ids = mine.companies.map { $0.id }
        var active = SellingCompany.selectedId().flatMap { ids.contains($0) ? $0 : nil }
        if active == nil, mine.companies.count == 1 { active = mine.companies[0].id }
        if active != SellingCompany.selectedId() { SellingCompany.set(active) }
        companies = mine.companies
        activeCompanyId = active
        companyPickRequired = mine.pick_required ?? false
        companiesLoaded = true
    }

    /// Switches the company orders are taken for. Catalogue and prices differ per company, so the cart starts over.
    func selectCompany(_ id: String) {
        if id != SellingCompany.selectedId() {
            SellingCompany.set(id)
            clearCart()
            suggest = nil
            catalogue = nil
        }
        activeCompanyId = id
    }

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

    @Published var catalogue: OrderCatalogue?

    /// Full orderable SKU list for the outlet. Loaded lazily when the rep opens
    /// the "Browse catalogue" sheet. Selections still land in `cartQty`, so
    /// Preview/Place are unchanged.
    func loadCatalogue(outletId: String) async {
        do { catalogue = try await api.catalogue(outletId: outletId) } catch { catalogue = nil }
    }

    func setQty(skuId: String, qty: Int) {
        if qty <= 0 { cartQty.removeValue(forKey: skuId) } else { cartQty[skuId] = qty }
        // The priced total no longer matches the cart: placing it would be refused as PRICE_MISMATCH. Price it again.
        preview = nil
    }

    func clearCart() {
        cartQty = [:]; preview = nil; previewError = nil; submitError = nil
    }

    /// `distributorId` = the picked outlet's distributor ("Choose another outlet" / Book Order); nil on the route-plan
    /// path, where the server resolves it from the outlet.
    func runPreview(outletId: String, distributorId: String? = nil) async {
        let items = cartQty.compactMap { (skuId, qty) -> CartLineInput? in
            guard qty > 0 else { return nil }
            return CartLineInput(sku_id: skuId, qty: qty, uom: nil)
        }
        guard !items.isEmpty else { preview = nil; return }
        previewing = true; previewError = nil
        defer { previewing = false }
        let outlet = route?.outlets.first(where: { $0.id == outletId })
        let gps = (outlet?.lat).flatMap { lat in (outlet?.lng).map { GeoPoint(lat: lat, lng: $0) } }
        let input = OrderInput(outlet_id: outletId, distributor_id: DistributionQueuePolicy.nonBlank(distributorId), visit_id: outlet?.route_visit_id, items: items, gps: gps, notes: nil, client_total: nil)
        do {
            preview = try await api.preview(input)
        } catch {
            previewError = error.localizedDescription
        }
    }

    /// Places the order: saved on the phone first, sent straight away, and left in the queue when the network is
    /// down. `idempotencyKey` is made ONCE by the confirm screen and passed back on every submit, so a second tap or
    /// a retry is the same order on the server; after a refused order the screen takes a NEW key (the refused one is
    /// spent). `distributorId` = the picked outlet's distributor (nil on the route-plan path; the server then resolves
    /// it from the outlet). Returns what happened (nil if nothing was attempted: empty cart, or a send in progress).
    /// The cart is cleared once the order is placed or saved; after a refusal it is kept and `submitError` says why.
    func submit(outletId: String, outletName: String?, visitId: String?, distributorId: String?,
                idempotencyKey: String) async -> DistributionSync.SubmitOutcome? {
        if submitting { return nil }      // a second tap while the first is still in flight
        let items = cartQty.compactMap { (skuId, qty) -> CartLineInput? in
            guard qty > 0 else { return nil }
            return CartLineInput(sku_id: skuId, qty: qty, uom: nil)
        }
        guard !items.isEmpty else { submitError = "Cart is empty"; return nil }
        submitting = true; submitError = nil
        defer { submitting = false }

        let outlet = route?.outlets.first(where: { $0.id == outletId })
        let gps = (outlet?.lat).flatMap { lat in (outlet?.lng).map { GeoPoint(lat: lat, lng: $0) } }
        let total = preview?.totals.grand_total
        let input = OrderInput(outlet_id: outletId, distributor_id: DistributionQueuePolicy.nonBlank(distributorId), visit_id: visitId, items: items, gps: gps, notes: nil, client_total: total)

        let outcome = await DistributionSync.shared.recordOrder(input: input, clientTotal: total ?? 0, outletName: outletName,
                                                                visitId: visitId, idempotencyKey: idempotencyKey)
        switch outcome {
        case .synced, .queued:
            clearCart()
        case .rejected(let message):
            submitError = message
        }
        return outcome
    }

    func loadOrders() async {
        loadingOrders = true
        do { orders = try await api.myOrders() } catch {}
        loadingOrders = false
    }

    func loadOrder(_ id: String) async {
        do { currentOrder = try await api.order(id: id) } catch { currentOrder = nil }
    }

    @Published var invoice: Invoice?
    @Published var loadingInvoice = false
    /// True once a load attempt has completed, so the view can tell "still
    /// loading" apart from "loaded, but the order has no invoice yet" (404 → nil).
    @Published var invoiceLoaded = false

    func loadInvoice(orderId: String) async {
        loadingInvoice = true
        defer { loadingInvoice = false; invoiceLoaded = true }
        do { invoice = try await api.orderInvoice(orderId: orderId) } catch { invoice = nil }
    }

    @Published var cancelling = false
    @Published var cancelError: String?

    /// Cancel the order currently displayed in detail. Returns true on success
    /// so the calling view can pop / refresh. Android parity.
    func cancelCurrentOrder(reason: String? = nil) async -> Bool {
        guard let id = currentOrder?.id else { return false }
        cancelling = true; cancelError = nil
        defer { cancelling = false }
        do {
            currentOrder = try await api.cancelOrder(id: id, reason: reason)
            // Update the order in the list too so the history reflects it.
            if let idx = orders.firstIndex(where: { $0.id == id }) {
                orders[idx] = currentOrder!
            }
            return true
        } catch {
            cancelError = error.localizedDescription
            return false
        }
    }

    /// "Retry now": sends everything waiting (orders, payments, returns). Rows the server refuses are marked failed
    /// and stay in the list; rows that could not be delivered stay waiting.
    func flushQueue() async {
        await DistributionSync.shared.flushAll()
    }
}
