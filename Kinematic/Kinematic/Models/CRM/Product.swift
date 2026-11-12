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
    let weightKg: Double?
    let createdAt: String?
    let updatedAt: String?
    /// Manufacturer / brand of the product (connected-B2B). A deal line picked from the catalogue
    /// starts with these. Brand is not make: MAC, PHD, BEKO, PIAB... are brands.
    let makeId: String?
    let brandId: String?
    let makeName: String?
    let brandName: String?

    // Backend column names diverge from the Swift property names for
    // historical reasons:
    //   crm_products.price        → unitPrice
    //   crm_products.tax_rate_pct → taxPct
    // Without these aliases every product decoded to nil price + 0%
    // tax — the bug behind "all products show ₹0 in the app".
    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case sku, name, description, unit
        case categoryId = "category_id"
        case unitPrice = "price"
        case currency
        case taxPct = "tax_rate_pct"
        case hsnCode = "hsn_code"
        case imageUrl = "image_url"
        case isActive = "is_active"
        case weightKg = "weight_kg"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case makeId = "make_id"
        case brandId = "brand_id"
        case makeName = "make_name"
        case brandName = "brand_name"
    }
}

/// One product line on a deal. Connected-B2B lines also carry make, brand, a MAC funnel reference and the
/// ORDER value (what was actually ordered, filled when the deal is won). Decoding is lenient: numbers may
/// arrive as strings, and every key but `id` may be missing.
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
    /// Product reference (the product's sku, e.g. 13280).
    let reference: String?
    let makeId: String?
    let brandId: String?
    let makeName: String?
    let brandName: String?
    /// MAC funnel reference (required for MAC products, optional otherwise).
    let funnelRef: String?
    /// Ordered value; nil until it is known.
    let orderValue: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case dealId = "deal_id"
        case productId = "product_id"
        case productName = "product_name"
        case name
        case sku
        case quantity
        case unitPrice = "unit_price"
        case discountPct = "discount_pct"
        case taxPct = "tax_pct"
        case lineTotal = "line_total"
        case reference
        case makeId = "make_id"
        case brandId = "brand_id"
        case makeName = "make_name"
        case brandName = "brand_name"
        case funnelRef = "funnel_ref"
        case orderValue = "order_value"
    }

    init(id: String, dealId: String = "", productId: String? = nil, productName: String = "",
         sku: String? = nil, quantity: Double = 1, unitPrice: Double = 0,
         discountPct: Double? = nil, taxPct: Double? = nil, lineTotal: Double? = nil,
         reference: String? = nil, makeId: String? = nil, brandId: String? = nil,
         makeName: String? = nil, brandName: String? = nil,
         funnelRef: String? = nil, orderValue: Double? = nil) {
        self.id = id
        self.dealId = dealId
        self.productId = productId
        self.productName = productName
        self.sku = sku
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discountPct = discountPct
        self.taxPct = taxPct
        self.lineTotal = lineTotal
        self.reference = reference
        self.makeId = makeId
        self.brandId = brandId
        self.makeName = makeName
        self.brandName = brandName
        self.funnelRef = funnelRef
        self.orderValue = orderValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = LenientDecode.string(c, .id) ?? ""
        dealId = LenientDecode.string(c, .dealId) ?? ""
        productId = LenientDecode.string(c, .productId)
        productName = LenientDecode.string(c, .productName) ?? LenientDecode.string(c, .name) ?? ""
        sku = LenientDecode.string(c, .sku)
        quantity = LenientDecode.double(c, .quantity) ?? 0
        unitPrice = LenientDecode.double(c, .unitPrice) ?? 0
        discountPct = LenientDecode.double(c, .discountPct)
        taxPct = LenientDecode.double(c, .taxPct)
        lineTotal = LenientDecode.double(c, .lineTotal)
        reference = LenientDecode.string(c, .reference)
        makeId = LenientDecode.string(c, .makeId)
        brandId = LenientDecode.string(c, .brandId)
        makeName = LenientDecode.string(c, .makeName)
        brandName = LenientDecode.string(c, .brandName)
        funnelRef = LenientDecode.string(c, .funnelRef)
        orderValue = LenientDecode.double(c, .orderValue)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(dealId, forKey: .dealId)
        try c.encodeIfPresent(productId, forKey: .productId)
        try c.encode(productName, forKey: .productName)
        try c.encodeIfPresent(sku, forKey: .sku)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(unitPrice, forKey: .unitPrice)
        try c.encodeIfPresent(discountPct, forKey: .discountPct)
        try c.encodeIfPresent(taxPct, forKey: .taxPct)
        try c.encodeIfPresent(lineTotal, forKey: .lineTotal)
        try c.encodeIfPresent(reference, forKey: .reference)
        try c.encodeIfPresent(makeId, forKey: .makeId)
        try c.encodeIfPresent(brandId, forKey: .brandId)
        try c.encodeIfPresent(makeName, forKey: .makeName)
        try c.encodeIfPresent(brandName, forKey: .brandName)
        try c.encodeIfPresent(funnelRef, forKey: .funnelRef)
        try c.encodeIfPresent(orderValue, forKey: .orderValue)
    }
}
