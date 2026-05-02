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

struct OrderPreview: Codable {
    let lines: [PricedLine]
    let totals: OrderTotals
    let price_list_version: Int
    let intra_state: Bool?
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
