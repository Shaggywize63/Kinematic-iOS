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

/// Structured server error: some endpoints return `error` as `{code,message}`
/// instead of a plain string. We decode either shape transparently — old
/// `error` access still returns the string for legacy callers; `errorObject`
/// exposes the structured form.
struct APIErrorObject: Codable {
    let code: String?
    let message: String?
}

struct APIEnvelope<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: String?
    let errorObject: APIErrorObject?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case success, data, error, message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        self.data    = try c.decodeIfPresent(T.self,   forKey: .data)
        self.message = try c.decodeIfPresent(String.self, forKey: .message)
        // `error` may be a string OR an object {code,message}; try both.
        if let s = try? c.decodeIfPresent(String.self, forKey: .error) {
            self.error = s
            self.errorObject = nil
        } else if let o = try? c.decodeIfPresent(APIErrorObject.self, forKey: .error) {
            self.errorObject = o
            self.error = o.message
        } else {
            self.error = nil
            self.errorObject = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(success, forKey: .success)
        try c.encodeIfPresent(data, forKey: .data)
        try c.encodeIfPresent(message, forKey: .message)
        if let errorObject {
            try c.encode(errorObject, forKey: .error)
        } else {
            try c.encodeIfPresent(error, forKey: .error)
        }
    }
}
