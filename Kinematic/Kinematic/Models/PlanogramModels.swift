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
