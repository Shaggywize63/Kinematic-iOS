// Distribution module — DTOs.
// Mirrors backend /api/v1/distribution + /api/v1/salesman.
// All snake_case decoded via convertFromSnakeCase on the JSONDecoder.

import Foundation

struct GeoPoint: Codable {
    let lat: Double
    let lng: Double
}

struct CartLineInput: Codable, Identifiable {
    var id: String { sku_id }
    let sku_id: String
    let qty: Int
    let uom: String?
}

struct OrderInput: Codable {
    let outlet_id: String
    let distributor_id: String?
    let visit_id: String?
    let items: [CartLineInput]
    let gps: GeoPoint?
    let notes: String?
    let client_total: Double?
}

struct OrderTotals: Codable {
    let subtotal: Double
    let discount_total: Double
    let taxable_value: Double
    let cgst: Double
    let sgst: Double
    let igst: Double
    let cess: Double
    let round_off: Double
    let grand_total: Double
}

struct PricedLine: Codable, Identifiable {
    var id: String { sku_id }
    let sku_id: String
    let sku_name: String?
    let sku_code: String?
    let hsn_code: String?
    let qty: Int
    let uom: String
    let unit_price: Double
    let mrp: Double
    let taxable_value: Double
    let gst_rate: Double
    let cgst: Double
    let sgst: Double
    let igst: Double
    let cess: Double
    let total: Double
    let is_free_good: Bool?
}

/// Order-time credit snapshot returned by /salesman/orders/preview.
/// Every field is optional so older previews (no `credit` object) — and any
/// partial payload — still decode. `status` ∈ "na" | "ok" | "warning" |
/// "exceeded"; use `statusValue` for a normalized, lowercased default of "na".
struct Credit: Codable {
    let credit_limit: Double?
    let current_balance: Double?
    let order_value: Double?
    let projected_balance: Double?
    let available: Double?
    let utilization_pct: Int?
    let status: String?

    var statusValue: String { (status ?? "na").lowercased() }
}

struct OrderPreview: Codable {
    let lines: [PricedLine]
    let totals: OrderTotals
    let price_list_version: Int
    let intra_state: Bool?
    let credit: Credit?
}

struct OrderDistributorAddress: Codable {
    let line1: String?
    let city: String?
    let state: String?
    let pincode: String?
}

struct OrderDistributor: Codable {
    let name: String?
    let gstin: String?
    let address: OrderDistributorAddress?
    let state_code: String?
    let place_of_supply: String?
}

struct DistOrder: Codable, Identifiable {
    let id: String
    let order_no: String
    let outlet_id: String
    let outlet_name: String?
    let distributor_id: String
    let salesman_id: String?
    let status: String
    let placed_at: String
    let grand_total: Double
    let taxable_value: Double?
    let geofence_passed: Bool?
    let geofence_distance_m: Int?
    let order_items: [PricedLine]?
    let distributor: OrderDistributor?
}

struct OutletSummary: Codable {
    let id: String
    let name: String
    let current_balance: Double
    let credit_limit: Double
}

struct Recommendation: Codable, Identifiable {
    var id: String { sku_id }
    let sku_id: String
    let sku_name: String?
    let mrp: Double
    let suggested_qty: Int
    let reason: String?
}

struct CartSuggest: Codable {
    let outlet: OutletSummary
    let last_orders: [DistOrder]?
    let recommendations: [Recommendation]
}

struct RouteOutletDist: Codable, Identifiable {
    let id: String
    let name: String
    let address: String?
    let lat: Double?
    let lng: Double?
    let geofence_radius_m: Int?
    let current_balance: Double?
    let credit_limit: Double?
    let last_order_at: String?
    let route_visit_id: String?
}

struct RouteToday: Codable {
    let date: String
    let outlets: [RouteOutletDist]
}

struct GeofenceCheck: Codable {
    let geofence_passed: Bool?
    let distance_m: Int?
    let radius_m: Int?
}

struct SignedUpload: Codable {
    let upload_url: String
    let token: String
    let bucket: String
    let path: String
    let public_url: String
    let expires_in: Int
}

struct AppliedInvoice: Codable {
    let invoice_id: String
    let amount: Double
}

struct PaymentInput: Codable {
    let outlet_id: String
    let mode: String
    let amount: Double
    let reference: String?
    let cheque_bank: String?
    let cheque_date: String?
    let cheque_image_url: String?
    let applied_to_invoices: [AppliedInvoice]?
    let gps: GeoPoint?
}

struct ReturnLineInput: Codable {
    let sku_id: String
    let qty: Int
    let condition: String
    let original_invoice_item_id: String?
}

struct ReturnInput: Codable {
    let outlet_id: String
    let original_invoice_id: String
    let reason_code: String
    let reason_notes: String?
    let photo_urls: [String]
    let items: [ReturnLineInput]
    let gps: GeoPoint?
}

struct DistributionPayment: Codable, Identifiable {
    let id: String
    let payment_no: String
    let outlet_id: String
    let mode: String
    let amount: Double
    let received_at: String
    let status: String
}

struct DistributionReturn: Codable, Identifiable {
    let id: String
    let return_no: String
    let outlet_id: String
    let total_value: Double
    let status: String
    let requires_supervisor: Bool?
}

// ── Catalogue (browse full orderable SKU list) ────────────────────────────
// Backs GET /salesman/outlets/{outletId}/catalogue. Decoded by property name
// (the DistributionAPI decoder is a plain JSONDecoder — no snake_case strategy),
// so keys stay snake_case to match the payload. Optional fields tolerate a
// sparse row (missing name/code/category/min/max).

struct CatalogueItem: Codable, Identifiable {
    var id: String { sku_id }
    let sku_id: String
    let sku_name: String?
    let sku_code: String?
    let category: String?
    let uom: String
    let pack_size: Double
    let mrp: Double
    let base_price: Double
    let min_qty: Double?
    let max_qty: Double?
    let gst_rate: Double
}

struct OrderCatalogue: Codable {
    let items: [CatalogueItem]
    let price_list_version: Int?
    let customer_class: String?
    let credit: Credit?
}

// ── Invoice (GST tax-invoice document) ────────────────────────────────────
// Backs GET /salesman/orders/{orderId}/invoice, which 404s until the order is
// invoiced. EVERY field is optional on purpose: the exact invoice_items schema
// isn't pinned down here, so optional-tolerant decoding avoids a strict-Codable
// failure on any field the backend omits or renames a sibling of.

struct InvoiceParty: Codable {
    let name: String?
    let gstin: String?
    let address: String?
    let state_code: String?
    let place_of_supply: String?
}

struct InvoiceItem: Codable {
    let sku_name: String?
    let hsn_code: String?
    let qty: Double?
    let uom: String?
    let unit_price: Double?
    let taxable_value: Double?
    let gst_rate: Double?
    let cgst: Double?
    let sgst: Double?
    let igst: Double?
    let cess: Double?
    let total: Double?
}

struct Invoice: Codable {
    let id: String?
    let invoice_no: String?
    let status: String?
    let irn: String?
    let qr_code_url: String?
    let place_of_supply: String?
    let subtotal: Double?
    let discount_total: Double?
    let taxable_value: Double?
    let cgst: Double?
    let sgst: Double?
    let igst: Double?
    let cess: Double?
    let round_off: Double?
    let grand_total: Double?
    let bill_type: String?
    let issued_at: String?
    let invoice_items: [InvoiceItem]?
    let distributor: InvoiceParty?
    let outlet: InvoiceParty?
    let buyer_gstin: String?
    let buyer_state_code: String?
}

// ── SKU catalogue lite (van load-in picker) ───────────────────────────────
// Backs GET /skus. The DistributionAPI decoder is a plain JSONDecoder (no
// snake_case strategy), so keys stay snake_case. Optional fields tolerate a
// sparse row; `is_active` defaults to true at the call site when absent.

struct SkuLite: Codable, Identifiable {
    let id: String
    let name: String?
    let sku_code: String?
    let category: String?
    let is_active: Bool?
}

// ── Van load (rep day-start load-in + end-of-day reconcile) ───────────────
// Backs GET /salesman/van-load/today, POST /salesman/van-load and
// POST /salesman/van-load/{id}/reconcile. Quantities are decoded as Double so
// a numeric column that comes back fractional (or as `5.0`) never fails.

struct VanLoadItemSku: Codable {
    let name: String?
    let sku_code: String?
}

struct VanLoadItem: Codable, Identifiable {
    let id: String
    let sku_id: String
    let loaded_qty: Double
    let sold_qty: Double
    let returned_qty: Double
    let damaged_qty: Double
    let skus: VanLoadItemSku?
}

struct VanLoadTotals: Codable {
    let loaded: Double
    let sold: Double
    let returned: Double
    let damaged: Double
}

struct VanLoad: Codable, Identifiable {
    let id: String
    let user_id: String?
    let distributor_id: String?
    let route_plan_id: String?
    let load_date: String
    let status: String
    let opened_at: String?
    let closed_at: String?
    let notes: String?
    let items: [VanLoadItem]
    let totals: VanLoadTotals?
}

struct VanLoadItemInput: Codable {
    let sku_id: String
    let loaded_qty: Double
}

struct VanLoadCreateInput: Codable {
    let distributor_id: String?
    let route_plan_id: String?
    let load_date: String?
    let notes: String?
    let items: [VanLoadItemInput]
}

struct VanReconcileItemInput: Codable {
    let sku_id: String
    let returned_qty: Double?
    let damaged_qty: Double?
}

struct VanReconcileInput: Codable {
    let items: [VanReconcileItemInput]
    let notes: String?
}

// ── Distributor stock (read-only on-hand view) ────────────────────────────
// Backs GET /distribution/distributors (picker) + GET /distribution/stock.

struct DistributorLite: Codable, Identifiable {
    let id: String
    let name: String?
    let code: String?
}

struct DistributorStockRow: Codable, Identifiable {
    let id: String
    let distributor_id: String?
    let sku_id: String
    let qty: Double
    let reserved: Double
    let available: Double
    let updated_at: String?
    let sku_name: String?
    let sku_code: String?
    let category: String?
}

// ── Damage / expiry register (distributor damaged-stock log) ──────────────
// Backs POST /distribution/damage and GET /distribution/damage. The
// DistributionAPI decoder is a plain JSONDecoder (no snake_case strategy), so
// keys stay snake_case to match the payload. The optional joins + detail
// fields tolerate a sparse row (a fresh POST response may omit the sku /
// distributor names the GET list joins in).

struct DamageEntry: Codable, Identifiable {
    let id: String
    let distributor_id: String?
    let sku_id: String
    let qty: Int
    let reason: String
    let status: String
    let batch_no: String?
    let expiry_date: String?
    let unit_value: Double?
    let note: String?
    let created_at: String?
    let sku_name: String?
    let sku_code: String?
    let distributor_name: String?
}

// Encodable-only input for POST /distribution/damage. Optional fields are
// synthesized with encodeIfPresent, so nil batch/expiry/unit_value/note are
// omitted from the body entirely (matching the backend's optional contract).
struct DamageEntryInput: Encodable {
    let distributor_id: String
    let sku_id: String
    let qty: Int
    let reason: String
    let batch_no: String?
    let expiry_date: String?
    let unit_value: Double?
    let note: String?
}
