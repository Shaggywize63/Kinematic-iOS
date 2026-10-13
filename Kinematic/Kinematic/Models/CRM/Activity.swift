import Foundation

struct Activity: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let type: String?           // call, email, meeting, note, task
    let subject: String?
    let description: String?
    /// The persisted note column on `crm_activities`. The backend folds a
    /// POSTed `description` into `body` (the `description` key does not exist
    /// as a column), so a call logged via the Log Call sheet carries its
    /// remarks here — `description` comes back nil for those rows. Read
    /// `body` for the remarks, falling back to `description` for any older
    /// surface that still echoes it.
    let body: String?
    /// Call disposition — a real `crm_activities` column, passed straight
    /// through by the backend. Holds the Log Call sheet's "outcome".
    let outcome: String?
    let leadId: String?
    let contactId: String?
    let accountId: String?
    let dealId: String?
    let ownerId: String?
    let ownerName: String?
    /// Workflow state stamped by the backend: open / in_progress / completed / cancelled.
    /// The CRM Activities list pill renders this directly (matches the web
    /// dashboard); when nil, the row falls back to "completed" if
    /// `completedAt` is set, else "open".
    let status: String?
    let dueAt: String?
    let completedAt: String?
    let direction: String?      // inbound / outbound
    let durationMinutes: Int?
    let imageUrl: String?
    let createdAt: String?
    let updatedAt: String?
    /// Denormalised name of the linked lead — stamped by the backend so the
    /// activity card can surface context without a second fetch.
    let leadName: String?
    /// Denormalised phone of the linked lead (backend stamp) — surfaced as
    /// the activity card's "Contact" when there's no directory number.
    let leadPhone: String?
    /// Denormalised name of the linked contact (fallback when no lead is set).
    let contactName: String?
    /// Denormalised name of the linked deal (fallback when neither lead nor
    /// contact is set).
    let dealName: String?
    /// SRS / BMW site-visits link a People-Directory dealer via
    /// custom_fields.dealer_name; the backend resolves it to the person's
    /// name + mobile so the card can show "Radha Traders · 9431188608".
    let directoryName: String?
    let directoryPhone: String?
    /// Campaign feedback captured on the Log Call sheet (humanised keys like
    /// `digigold_explained`, `app_rating`, `customer_rating`, `complaint`…).
    /// Decoded loosely — mirrors `Lead.customFields`.
    let customFields: [String: AnyCodable]?
    /// Free-form activity metadata (jsonb). Imported calls stamp
    /// `metadata.campaign` here; app-logged calls may omit it. Read the
    /// campaign via `metadata["campaign"]?.value`.
    let metadata: [String: AnyCodable]?

    /// The remarks note for display — the persisted `body`, falling back to
    /// the legacy `description` echo.
    var remarksText: String? {
        if let b = body?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty { return b }
        if let d = description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { return d }
        return nil
    }

    /// The campaign string stamped on this activity's `metadata`, if any.
    var metadataCampaign: String? {
        guard let raw = metadata?["campaign"]?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    /// Effective workflow state for UI rendering — falls back to a sensible
    /// default when the backend hasn't stamped `status` yet (older rows).
    var effectiveStatus: String {
        if let s = status?.trimmingCharacters(in: .whitespaces), !s.isEmpty { return s.lowercased() }
        return (completedAt?.isEmpty == false) ? "completed" : "open"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case type, subject, description, status
        case body, outcome
        case customFields = "custom_fields"
        case metadata
        case leadId = "lead_id"
        case contactId = "contact_id"
        case accountId = "account_id"
        case dealId = "deal_id"
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case dueAt = "due_at"
        case completedAt = "completed_at"
        case direction
        case durationMinutes = "duration_minutes"
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case leadName = "lead_name"
        case leadPhone = "lead_phone"
        case contactName = "contact_name"
        case dealName = "deal_name"
        case directoryName = "directory_name"
        case directoryPhone = "directory_phone"
    }
}
