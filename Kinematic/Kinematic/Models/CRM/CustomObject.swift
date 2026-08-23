import Foundation

/// An admin-defined CRM object type. Its fields are `crm_custom_field_defs`
/// rows with `entity_type == key`, so records reuse `CustomFieldsModel`.
struct CRMCustomObject: Codable, Identifiable, Hashable {
    let id: String
    let key: String
    let label: String
    let labelPlural: String?
    let icon: String?
    let description: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, key, label
        case labelPlural = "label_plural"
        case icon, description
        case isActive = "is_active"
    }

    var displayPlural: String { labelPlural ?? label }
}

/// One record of a custom object. `data` holds the field values keyed by
/// `crm_custom_field_defs.field_key` — the same shape `CustomFieldsModel`
/// hydrates from and emits.
struct CRMCustomRecord: Codable, Identifiable {
    let id: String
    let objectId: String?
    let title: String?
    let data: [String: AnyCodable]?
    let ownerId: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case objectId = "object_id"
        case title, data
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// `GET /crm/custom-objects/{key}/records` returns `{ rows, total }`.
struct CRMCustomRecordsPage: Codable {
    let rows: [CRMCustomRecord]?
    let total: Int?
}
