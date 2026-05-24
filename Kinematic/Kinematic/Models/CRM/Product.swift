import Foundation

struct Product: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let sku: String?
    let name: String
    let description: String?
    let categoryId: String?
    let unit: String?
    let unitPrice: Double?
    /// Canonical per-unit price from `crm_products.price`. The legacy
    /// `unit_price` accessor above is retained for older call sites; new
    /// code (e.g. multi-line lead convert) should prefer `price` since the
    /// backend canonicalises against this column when re-deriving totals.
    let price: Double?
    /// Per-unit weight in kg (Tata Tiscon ships products by tonnage, so the
    /// convert flow needs kg/pieces/subtotal three-way sync against this).
    let weightKg: Double?
    let currency: String?
    let taxPct: Double?
    let hsnCode: String?
    let imageUrl: String?
    let isActive: Bool?
    let createdAt: String?
    let updatedAt: String?

    /// Convenience: prefer the new `price` column, fall back to legacy
    /// `unit_price`. Keeps the existing ProductsListView row rendering
    /// working without a separate migration.
    var effectivePrice: Double? { price ?? unitPrice }

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case sku, name, description, unit
        case categoryId = "category_id"
        case unitPrice = "unit_price"
        case price
        case weightKg = "weight_kg"
        case currency
        case taxPct = "tax_pct"
        case hsnCode = "hsn_code"
        case imageUrl = "image_url"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DealLineItem: Codable, Identifiable, Hashable {
    let id: String
    let dealId: String
    let productId: String?
    let productName: String
    let sku: String?
    let quantity: Double
    let unitPrice: Double
    let discountPct: Double?
    let taxPct: Double?
    let lineTotal: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case dealId = "deal_id"
        case productId = "product_id"
        case productName = "product_name"
        case sku
        case quantity
        case unitPrice = "unit_price"
        case discountPct = "discount_pct"
        case taxPct = "tax_pct"
        case lineTotal = "line_total"
    }
}
