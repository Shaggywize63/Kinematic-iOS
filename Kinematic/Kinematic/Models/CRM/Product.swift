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
    let currency: String?
    let taxPct: Double?
    let hsnCode: String?
    let imageUrl: String?
    let isActive: Bool?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case sku, name, description, unit
        case categoryId = "category_id"
        case unitPrice = "unit_price"
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
