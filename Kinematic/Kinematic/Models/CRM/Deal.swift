import Foundation

struct Deal: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let name: String
    let accountId: String?
    let contactId: String?
    let pipelineId: String?
    let stageId: String?
    let stageName: String?
    let amount: Double?
    let currency: String?
    let probability: Double?
    let winProbability: Double?
    let expectedCloseDate: String?
    let actualCloseDate: String?
    let status: String?           // open / won / lost
    let lostReason: String?
    let ownerId: String?
    let nextActionAt: String?
    let nextActionLabel: String?
    let tags: [String]?
    let createdAt: String?
    let updatedAt: String?
    // Linked lead — set on conversion-style deal creation. Product edits
    // on the deal are mirrored back onto this lead's custom_fields.
    let leadId: String?
    // Free-form jsonb. Carries the deal's own basket (`product_lines`,
    // `volume_kg`) plus `closed_quantities = { [product_id]: number }`
    // persisted by the Products section.
    let customFields: [String: AnyCodable]?
    // Server-stamped display fields — GET /deals and /deals/:id enrich
    // each row with the resolved dealer label, the linked lead's
    // name/phone, and the owner's name (stampOwnerName on the backend).
    // Read-only: never included in create/PATCH bodies.
    let dealerName: String?
    let leadName: String?
    let leadPhone: String?
    let ownerName: String?
    /// Spark & Ray quotation number — nil for every other tenant.
    let quotationNo: String?
    // Spark & Ray deal sections (nil for every other tenant). Dates are "YYYY-MM-DD".
    let pricingQuoted: Double?
    let pricingDiscountPct: Double?
    let pricingFinal: Double?
    let pricingValidTill: String?
    let trialRequired: Bool?
    let trialStart: String?
    let trialEnd: String?
    /// "pending" | "successful" | "failed".
    let trialResult: String?
    let trialNotes: String?
    /// People: user ids, plus the names the backend stamps on reads (read-only; never sent back).
    let technicalApprovalBy: String?
    let preparedBy: String?
    let checkedBy: String?
    let supervisorId: String?
    let technicalApprovalByName: String?
    let preparedByName: String?
    let checkedByName: String?
    let supervisorIdName: String?
    // Product lines roll-up (connected-B2B). Read leniently: a number may arrive as a string and a
    // missing / odd value reads as nil, so a surprising value never fails the whole deal.
    private let lineCountWire: LenientDouble?
    private let quotedAmountWire: LenientDouble?
    private let orderAmountWire: LenientDouble?
    private let brandsWire: LenientStringList?

    /// Number of product lines on the deal.
    var lineCount: Int? {
        guard let v = lineCountWire?.value, v >= 0, v < 1e9 else { return nil }
        return Int(v)
    }
    /// Sum of the lines' quoted values (nil when the deal has no lines).
    var quotedAmount: Double? { quotedAmountWire?.value }
    /// Sum of the lines' order values (nil when none is set).
    var orderAmount: Double? { orderAmountWire?.value }
    /// Distinct brand names of the lines.
    var brands: [String]? { brandsWire?.values }

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case name
        case accountId = "account_id"
        case contactId = "contact_id"
        case pipelineId = "pipeline_id"
        case stageId = "stage_id"
        case stageName = "stage_name"
        case amount, currency, probability
        case winProbability = "win_probability"
        case expectedCloseDate = "expected_close_date"
        case actualCloseDate = "actual_close_date"
        case status
        case lostReason = "lost_reason"
        case ownerId = "owner_id"
        case nextActionAt = "next_action_at"
        case nextActionLabel = "next_action_label"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case leadId = "lead_id"
        case customFields = "custom_fields"
        case dealerName = "dealer_name"
        case leadName = "lead_name"
        case leadPhone = "lead_phone"
        case ownerName = "owner_name"
        case quotationNo = "quotation_no"
        case pricingQuoted = "pricing_quoted"
        case pricingDiscountPct = "pricing_discount_pct"
        case pricingFinal = "pricing_final"
        case pricingValidTill = "pricing_valid_till"
        case trialRequired = "trial_required"
        case trialStart = "trial_start"
        case trialEnd = "trial_end"
        case trialResult = "trial_result"
        case trialNotes = "trial_notes"
        case technicalApprovalBy = "technical_approval_by"
        case preparedBy = "prepared_by"
        case checkedBy = "checked_by"
        case supervisorId = "supervisor_id"
        case technicalApprovalByName = "technical_approval_by_name"
        case preparedByName = "prepared_by_name"
        case checkedByName = "checked_by_name"
        case supervisorIdName = "supervisor_id_name"
        case lineCountWire = "line_count"
        case quotedAmountWire = "quoted_amount"
        case orderAmountWire = "order_amount"
        case brandsWire = "brands"
    }
}
