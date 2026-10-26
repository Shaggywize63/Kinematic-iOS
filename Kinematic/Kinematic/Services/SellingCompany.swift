//
//  SellingCompany.swift
//  Kinematic
//
//  The company (client) a salesman is selling for right now. A rep can work for several companies; each has its
//  own catalogue, prices, orders and collections, so the choice is sent as `X-Client-Id` on the distribution
//  (order / payment / return / catalogue) calls only — never on CRM, attendance or forms, which keep using the
//  user's home client. Kept apart from `CRMClientScope`, which is an org admin's tenant switcher for CRM.
//
//  Pure Foundation. `appliesTo(path:)` and `isUUID` are unit-tested.
//

import Foundation

enum SellingCompany {
    /// UserDefaults key of the persisted choice (also listed in `SessionCleanup`, which wipes it at sign-out).
    static let storageKey = "kinematic_selling_company"

    /// The stored company, or nil unless it is a valid UUID (nothing else may reach a request header).
    static func selectedId(in defaults: UserDefaults = .standard) -> String? {
        guard let raw = defaults.string(forKey: storageKey), isUUID(raw) else { return nil }
        return raw
    }

    static func set(_ id: String?, in defaults: UserDefaults = .standard) {
        if let id, isUUID(id) {
            defaults.set(id, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }

    /// Only the distribution surface follows the selling company (`/skus` is the company's catalogue too).
    static func appliesTo(path: String) -> Bool {
        path.hasPrefix("/api/v1/salesman/") || path.hasPrefix("/api/v1/distribution/") || path == "/api/v1/skus"
    }

    static func isUUID(_ s: String) -> Bool {
        s.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
                options: [.regularExpression, .caseInsensitive]) != nil
    }
}
