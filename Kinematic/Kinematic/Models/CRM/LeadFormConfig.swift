//
//  LeadFormConfig.swift
//  Kinematic CRM
//
//  Models for the per-org form customization the web admin exposes:
//
//    1. `FieldOverride` — entries in `crm_settings.config.field_overrides`,
//       keyed by `<entity>.<field_key>` (e.g. "lead.first_name"). Lets an
//       admin relabel, hide, or toggle required on a built-in field without
//       a schema change.
//
//    2. `CRMCustomField` — rows from /api/v1/crm/custom-fields. These are
//       admin-defined extra fields rendered inline in the create/edit form.
//       Values land in the lead's `custom_fields` JSON column at submit.
//
//  Both are fetched once when the create/edit sheet appears.
//

import Foundation

/// Override an individual built-in form field. All keys are optional; an
/// absent key means "no override, use the iOS default."
struct FieldOverride: Codable, Hashable {
    let label: String?
    let required: Bool?
    let hidden: Bool?
    let position: Int?
}

/// Admin-defined custom field. `fieldType` controls which SwiftUI control
/// we render. `options` is non-nil for select/multiselect/radio.
struct CRMCustomField: Codable, Identifiable, Hashable {
    let id: String
    let entityType: String
    let fieldKey: String
    let label: String
    let fieldType: String
    let options: [String]?
    let required: Bool?
    let position: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case entityType = "entity_type"
        case fieldKey = "field_key"
        case label
        case fieldType = "field_type"
        case options
        case required
        case position
    }
}

/// In-memory holder for the values a user enters into custom fields. Keyed
/// by `field_key`. Stored as `Any` because the values are heterogeneous
/// (Bool, Double, String, [String], Date, ...). Serialized via
/// `jsonReady()` before submit.
struct CustomFieldValues {
    private var storage: [String: Any] = [:]

    subscript(key: String) -> Any? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    var isEmpty: Bool { storage.isEmpty }

    /// Convert into a JSON-serializable dict. Dates become ISO-8601 strings;
    /// nil/empty values are dropped so we don't stamp blanks.
    func jsonReady() -> [String: Any] {
        var out: [String: Any] = [:]
        let isoDateTime: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
        for (k, v) in storage {
            // Bool conforms to several numeric protocols, so test it before
            // the numeric branches to avoid `true` decaying to `1`.
            if let b = v as? Bool {
                out[k] = b
                continue
            }
            if let s = v as? String {
                if !s.isEmpty { out[k] = s }
                continue
            }
            if let i = v as? Int {
                out[k] = i
                continue
            }
            if let d = v as? Double {
                out[k] = d
                continue
            }
            if let arr = v as? [String] {
                if !arr.isEmpty { out[k] = arr }
                continue
            }
            if let date = v as? Date {
                // We don't know date-vs-datetime from value alone; ISO-8601
                // covers both — backend can truncate when storing date-only.
                out[k] = isoDateTime.string(from: date)
                continue
            }
        }
        return out
    }
}
