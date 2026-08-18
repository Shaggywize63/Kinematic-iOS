//
//  PlanogramModels.swift
//  Kinematic
//
//  Codable models for the AI Planogram Engine. Mirrors the JSON shape
//  returned by /api/v1/planograms on the kinematic backend.
//

import Foundation
import CoreGraphics

// MARK: - Planogram (expected layout)

struct ExpectedSKU: Codable, Identifiable, Hashable {
    var id: String { sku_id }
    let sku_id: String
    let sku_name: String
    let shelf_index: Int
    let facings: Int
    let position: Int?
    let weight: Double?
}

struct PlanogramLayout: Codable, Hashable {
    struct Shelf: Codable, Hashable {
        let index: Int
        let capacity: Int?
    }
    let shelves: [Shelf]
}

struct Planogram: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String?
    let store_format: String?
    let layout: PlanogramLayout?
    let expected_skus: [ExpectedSKU]
    let version: Int
    let is_active: Bool
}

// MARK: - Capture / Recognition / Compliance

struct DetectedSKU: Codable, Identifiable, Hashable {
    var id: String { (sku_id ?? sku_name) + "_\(shelf_index)_\(facings)" }
    let sku_id: String?
    let sku_name: String
    let facings: Int
    let shelf_index: Int
    let bbox: [Double]            // [x, y, w, h] normalized
    let confidence: Double
    let is_competitor: Bool
    // Retail-execution additions (nil on captures that predate them, so the
    // synthesized decoder maps these snake_case keys via decodeIfPresent).
    let units_estimate: Int?      // estimated physical units on shelf
    let stock_status: String?     // "in_stock" | "low" | "out"

    var rect: CGRect {
        guard bbox.count == 4 else { return .zero }
        return CGRect(x: bbox[0], y: bbox[1], width: bbox[2], height: bbox[3])
    }
}

struct ShelfRecognition: Codable {
    let detected_skus: [DetectedSKU]
    let shelf_map: ShelfMap?
    let overall_confidence: Double
    let needs_review: Bool
    // Point-of-sale materials detected on the shelf image. Absent on older
    // recognitions that predate POSM detection (optional → decodes safely).
    let posm: [PosmDetection]?

    struct ShelfMap: Codable {
        let shelf_count: Int
    }
}

struct ComplianceMissing: Codable, Identifiable, Hashable {
    var id: String { sku_id }
    let sku_id: String
    let sku_name: String
    let expected_facings: Int
}

struct ComplianceMisplaced: Codable, Identifiable, Hashable {
    var id: String { sku_id }
    let sku_id: String
    let sku_name: String
    let expected_shelf: Int
    let actual_shelf: Int
}

struct ComplianceFacingDelta: Codable, Identifiable, Hashable {
    var id: String { sku_id }
    let sku_id: String
    let sku_name: String
    let expected: Int
    let actual: Int
    let delta: Int
}

struct ComplianceRecommendation: Codable, Identifiable, Hashable {
    var id: String { action }
    let priority: Priority
    let action: String
    let sku_id: String?
    let sku_name: String?
    let rationale: String

    enum Priority: String, Codable, Hashable {
        case critical, high, medium, low
    }
}

// MARK: - Retail execution (stock availability + POSM)

/// One SKU reference inside a stock list. `units_estimate` is present on the
/// low-stock list and omitted on the out-of-stock list.
struct StockSkuRef: Codable, Identifiable, Hashable {
    var id: String { sku_id }
    let sku_id: String
    let sku_name: String
    let units_estimate: Int?
}

/// On-shelf stock estimate rollup for a capture (units + availability).
/// The nested arrays are always present when the summary itself is present
/// (the backend builds them, empty when there is nothing to report).
struct StockSummary: Codable, Hashable {
    let total_units: Int
    let own_units: Int
    let competitor_units: Int
    let availability_rate: Double        // share of expected SKUs in stock, 0..100
    let oos_count: Int
    let low_count: Int
    let out_of_stock_skus: [StockSkuRef]
    let low_stock_skus: [StockSkuRef]
}

/// A point-of-sale material element detected on the shelf image (recognition).
struct PosmDetection: Codable, Identifiable, Hashable {
    var id: String { type + "_" + name }
    let type: String
    let name: String
    let brand: String?
    let bbox: [Double]?
    let condition: String                // "good" | "damaged" | "obscured"
    let confidence: Double
}

/// A POSM entry in the compliance `missing` / `damaged` lists (`{ type, name }`).
struct PosmItem: Codable, Identifiable, Hashable {
    var id: String { type + "_" + name }
    let type: String
    let name: String
}

/// A POSM entry in the compliance `found` list.
struct PosmFound: Codable, Identifiable, Hashable {
    var id: String { type + "_" + name }
    let type: String
    let name: String
    let brand: String?
    let condition: String                // "good" | "damaged" | "obscured"
    let confidence: Double
}

/// POSM compliance rollup — expected point-of-sale materials vs what was found.
struct PosmCompliance: Codable, Hashable {
    let expected_count: Int
    let required_count: Int
    let found_count: Int
    let score: Double?                    // 0..100, nil when nothing was expected
    let missing: [PosmItem]
    let damaged: [PosmItem]
    let found: [PosmFound]
}

// MARK: - Share of shelf + competitor price (retail execution v2)

/// Per-category rollup for category-wise shelf analysis (own vs competitor
/// share, occupancy, facings and average shelf prices). `avg_own_price` /
/// `avg_competitor_price` are null when no price was read for that side —
/// hence optional; the remaining fields are always present when the array is.
struct CategoryBreakdown: Codable, Identifiable, Hashable {
    var id: String { category }
    let category: String
    let occupancy: Double                 // filled shelf space for the category, 0..100
    let own_share: Double                 // own facings % within the category, 0..100
    let competitor_share: Double
    let facings: Int
    let sku_count: Int
    let avg_own_price: Double?
    let avg_competitor_price: Double?
}

/// Own vs competitor facings within a placement band (low / eye-level / top).
struct ZoneBreakdown: Codable, Identifiable, Hashable {
    var id: String { zone }
    let zone: String                      // "low" | "eye" | "top"
    let own_facings: Int
    let competitor_facings: Int
    let own_share: Double                 // own share of the band, 0..100
    let sku_ids: [String]
}

/// A single pricing observation — an own SKU (shelf price vs expected MRP) or a
/// competitor. Backend-nullable numerics (`price`, `expected_price`, `delta`)
/// are optional; the always-present `sku_name` / `is_competitor` / `confidence`
/// are not. `currency`/`source`/`brand` are optional metadata.
struct PricingRow: Codable, Identifiable, Hashable {
    var id: String { (sku_id ?? sku_name) + "_\(is_competitor)" }
    let sku_id: String?
    let sku_name: String
    let is_competitor: Bool
    let price: Double?
    let currency: String?
    let expected_price: Double?
    let delta: Double?                    // shelf price − expected MRP (own rows)
    let source: String?                   // "shelf_tag" | "on_pack" | "promo"
    let confidence: Double
    let brand: String?                    // competitor identity, when matched
}

struct ComplianceResult: Codable {
    let score: Double
    let presence_score: Double
    let facing_score: Double
    let position_score: Double
    let competitor_share: Double
    let missing_skus: [ComplianceMissing]
    let misplaced_skus: [ComplianceMisplaced]
    let facing_deltas: [ComplianceFacingDelta]
    let recommendations: [ComplianceRecommendation]
    // Retail-execution rollups — all optional so older captures still decode.
    let stock_summary: StockSummary?
    let posm: PosmCompliance?
    let posm_score: Double?              // scalar mirror of posm.score
    let availability_rate: Double?       // scalar mirror of stock_summary.availability_rate
    let oos_count: Int?                  // scalar mirror of stock_summary.oos_count
    let low_stock_count: Int?            // scalar mirror of stock_summary.low_count
    // Share-of-shelf + pricing (retail-execution v2). All optional so pre-v2
    // captures still decode; property-name decoding maps each snake_case key
    // through the synthesized decodeIfPresent.
    let shelf_share_own: Double?         // own facings % of total, 0..100
    let shelf_share_competitor: Double?  // competitor facings % of total, 0..100
    let occupancy_score: Double?         // filled shelf space %, 0..100
    let category_breakdown: [CategoryBreakdown]?
    let zone_breakdown: [ZoneBreakdown]?
    let pricing: [PricingRow]?
}

struct CaptureResponse: Codable {
    let capture_id: String
    let compliance_id: String
    let result: ComplianceResult
    let recognition: ShelfRecognition
}

// MARK: - API envelope

/// Defensive shape: every field is optional so we tolerate routes that
/// return `{ data }` without an explicit `success` flag (e.g. the older
/// messaging routes before they were wrapped). Decoders that strictly
/// require `success` would silently drop the response and surface as an
/// empty list in the UI.
struct APIEnvelope<T: Codable>: Codable {
    let success: Bool?
    let data: T?
    let error: String?
    let message: String?
    let pagination: PageMeta?

    private enum CodingKeys: String, CodingKey { case success, data, error, message, pagination }

    // The backend ships `error` in two shapes:
    //   - a plain string (legacy 4xx responses)
    //   - `{ code, message }` (newer quota / RBAC failures — including the
    //     KINI 429 path)
    // When the second shape was decoded as `String?`, the whole envelope
    // failed to parse and `try? decoder.decode(...)` swallowed it — leaving
    // the chat surface with no quota message to render. Accept both shapes
    // and normalise to the message string so the existing
    // `env.error ?? env.message` consumers keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try c.decodeIfPresent(Bool.self, forKey: .success)
        self.data = try c.decodeIfPresent(T.self, forKey: .data)
        self.message = try c.decodeIfPresent(String.self, forKey: .message)
        self.pagination = try c.decodeIfPresent(PageMeta.self, forKey: .pagination)
        if let s = try? c.decodeIfPresent(String.self, forKey: .error) {
            self.error = s
        } else if let obj = try? c.decodeIfPresent(ErrorObject.self, forKey: .error) {
            self.error = obj.message
        } else {
            self.error = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(success, forKey: .success)
        try c.encodeIfPresent(data, forKey: .data)
        try c.encodeIfPresent(error, forKey: .error)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encodeIfPresent(pagination, forKey: .pagination)
    }

    private struct ErrorObject: Codable {
        let code: String?
        let message: String?
    }
}

/// Server pagination block returned alongside `data` on list endpoints
/// (e.g. /crm/leads). All optional so non-paginated responses still decode.
struct PageMeta: Codable {
    let total: Int?
    let page: Int?
    let limit: Int?
    let totalPages: Int?
    let hasNext: Bool?
    let hasPrev: Bool?
}
