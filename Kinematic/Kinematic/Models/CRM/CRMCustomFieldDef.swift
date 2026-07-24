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
    // Lifecycle flags. Deleting/reconciling a field tombstones it
    // (is_active=false, often hidden=true) — forms must skip both.
    let isActive: Bool?
    let hidden: Bool?
    let orgRoleIds: [String]?
    // Lookup-only — the table whose rows the picker searches when
    // fieldType == "lookup". Decoded from `target_table` on the JSON row.
    let targetTable: String?
    // Lookup-only — admin-configured filter clauses (e.g. `[{ field:
    // 'is_active', op: 'eq', value: true }]`) that narrow the search.
    // Encoded as JSON in the /lookup/search ?filter= query string.
    let lookupFilter: [LookupFilterClause]?

    /// Label for form rows — appends the same " *" marker built-in
    /// required fields use when the admin marked this field mandatory.
    var formLabel: String { required == true ? label + " *" : label }

    enum CodingKeys: String, CodingKey {
        case id
        case entityType = "entity_type"
        case fieldKey = "field_key"
        case label
        case fieldType = "field_type"
        case options
        case required
        case position
        case isActive = "is_active"
        case hidden
        case orgRoleIds = "org_role_ids"
        case targetTable = "target_table"
        case lookupFilter = "lookup_filter"
    }
}

/// One filter clause attached to a lookup-typed custom field. Backend
/// honours `eq | ne | contains | gte | lte`.
struct LookupFilterClause: Codable, Hashable {
    let field: String
    let op: String
    let value: AnyCodable?
}

/// One row from GET /api/v1/crm/lookup/search. The picker stores `id`
/// in the custom_fields blob and shows `label` in the dropdown.
struct CRMLookupOption: Codable, Identifiable, Hashable {
    let id: String
    let label: String
}
