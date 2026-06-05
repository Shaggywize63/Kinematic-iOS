import Foundation

/// An admin-defined custom field definition (crm_custom_field_defs). Rendered
/// on the lead/contact create forms. `orgRoleIds` scopes the field to specific
/// hierarchy roles — empty/nil means everyone sees it.
struct CRMCustomFieldDef: Codable, Identifiable, Hashable {
    let id: String
    let entityType: String
    let fieldKey: String
    let label: String
    let fieldType: String
    let options: [String]?
    let required: Bool?
    let position: Int?
    let orgRoleIds: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case entityType = "entity_type"
        case fieldKey = "field_key"
        case label
        case fieldType = "field_type"
        case options
        case required
        case position
        case orgRoleIds = "org_role_ids"
    }
}
