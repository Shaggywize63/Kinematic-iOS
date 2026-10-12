// ExpenseModels — wire types for /api/v1/expenses (Field Expense / Travel Claims).
//
// Property names are snake_case to match the JSON keys directly, because the
// shared decoder (see ExpensesAPI) uses no keyDecodingStrategy — same idiom as
// DistributionModels.
//
// Reps file multi-line claims (mileage from the GPS trail, receipts uploaded
// and read by OCR); claims are checked against the policy that governs the rep
// and route up the reporting line. Rejecting a claim or a line always carries a
// remark, which the rep sees here.
//
// JSONEncoder omits nil optionals, so on update an omitted `receipt_url` means
// "keep the receipt on file" and an empty string means "remove it".

import Foundation

// MARK: - Policy

struct ExpenseCategoryRule: Codable, Equatable {
    let enabled: Bool?
    let per_day_limit: Double?
    let per_claim_limit: Double?
    let per_month_limit: Double?
    let receipt_required_over: Double?
}

/// One vehicle type a policy pays for, with its cost per km (travel allowance by vehicle).
struct ExpenseVehicleRate: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let rate_per_km: Double
}

struct ExpensePolicyRules: Codable, Equatable {
    let mileage_rate: Double?
    /// When present, mileage is priced by vehicle from the odometer readings (computed by the server).
    let vehicle_rates: [ExpenseVehicleRate]?
    /// With vehicle rates: a photo of the odometer before and after is mandatory (default true).
    let odometer_photos_required: Bool?
    let receipt_required_over: Double?
    let max_claim_amount: Double?
    let submit_within_days: Int?
    let auto_approve_under: Double?
    let escalate_over: Double?
    /// "flag" lets a breach through to the approver; "block" stops submission.
    let enforcement: String?
    let categories: [String: ExpenseCategoryRule]?
    // Per-client presentation switches. Every one is optional and absent means "as before", so a policy
    // that does not send them behaves exactly as it always has.
    /// Display-name overrides for the categories, e.g. ["mileage": "Travel"]. Used wherever a category name is shown.
    let category_labels: [String: String]?
    /// false: no From / To on mileage lines (default true).
    let route_fields: Bool?
    /// true: a claim is one line — no "Add another expense" (default false).
    let single_line: Bool?
    /// true: an odometer photo can only be taken with the camera (no photo library), and the reading is read from it.
    let odometer_camera_only: Bool?
    /// true (with vehicle rates): a mileage line may claim the distance the server worked out from the rep's GPS route
    /// for that day instead of odometer readings, and the server prices it from the vehicle's rate. Default false.
    let gps_distance: Bool?
    /// true (with vehicle rates): the rep records the day's travel in two steps — the start odometer in the morning and
    /// the end odometer in the evening — on the "Today's travel" card, instead of entering both at once in the combined
    /// editor. Opt-in per client; default false, and the combined editor is unchanged for every policy without it.
    let odometer_daily_trip: Bool?
}

/// The policy that governs the signed-in user. The scalar fields are the
/// original single-policy shape; `rules` carries the full detail.
struct ExpensePolicy: Codable {
    let id: String?
    let name: String?
    let currency: String
    let mileage_rate: Double
    let auto_approve_under: Double?
    let escalate_over: Double?
    let require_receipt_over: Double
    let category_limits: [String: Double]?
    let is_active: Bool?
    let rules: ExpensePolicyRules?
}

// MARK: - Claims

struct ExpenseFlag: Codable, Identifiable, Equatable {
    var id: String { code + "|" + (item_id ?? "") + "|" + (detail ?? "") }
    let code: String
    let severity: String?
    let detail: String?
    /// For an unsaved-claim check, the position of the line this is about.
    let item_id: String?
    let category: String?
    /// True when, under the policy, the claim cannot be submitted with this.
    let blocking: Bool?
}

struct ExpenseClaimItem: Codable, Identifiable {
    let id: String
    let category: String
    let item_date: String?
    let description: String?
    let amount: Double
    let distance_km: Double?
    let from_location: String?
    let to_location: String?
    let merchant: String?
    let receipt_url: String?
    /// Short-lived viewable link for `receipt_url`, signed by the server on every read.
    let receipt_signed_url: String?
    // Travel allowance by vehicle (policies with vehicle rates).
    let vehicle_type: String?
    let odometer_start: Double?
    let odometer_end: Double?
    let odometer_start_photo_url: String?
    let odometer_end_photo_url: String?
    let odometer_start_photo_signed_url: String?
    let odometer_end_photo_signed_url: String?
    let flagged: Bool?
    let flag_reason: String?
    /// "approved" | "rejected" once an approver has decided this line.
    let decision: String?
    let decision_note: String?
}

struct ExpenseItemDecision: Codable {
    let item_id: String?
    let category: String?
    let amount: Double?
    let decision: String?
    let note: String?
}

struct ExpenseApproval: Codable, Identifiable {
    let id: String
    let level: Int
    /// Which submission this belongs to (a rejected claim can be resubmitted).
    let round: Int?
    let approver_id: String?
    let status: String?
    let note: String?
    let decided_at: String?
    let approver_name: String?
    let item_decisions: [ExpenseItemDecision]?
}

struct ExpenseClaim: Codable, Identifiable {
    let id: String
    let user_id: String?
    let claim_no: String?
    let title: String?
    let status: String?
    let currency: String
    let total_amount: Double
    /// What will actually be paid once decided (less than the total on a partial approval).
    let approved_amount: Double?
    let distance_km: Double?
    let gps_derived_km: Double?
    let approver_id: String?
    let current_level: Int?
    let submitted_at: String?
    let reviewed_at: String?
    /// The approver's remark. Always present on a rejected claim.
    let review_note: String?
    let ai_summary: String?
    let ai_flags: [ExpenseFlag]?
    let policy_name: String?
    let submit_count: Int?
    let auto_approved: Bool?
    let reimbursed_at: String?
    let reimbursed_ref: String?
    let created_at: String?
    let user_name: String?
    let employee_id: String?
    let approver_name: String?
    let reviewer_name: String?
    let items: [ExpenseClaimItem]?
    let approvals: [ExpenseApproval]?

    var statusLabel: String { (status ?? "draft").capitalized }
}

struct ExpenseMileageResult: Codable {
    let distance_km: Double
    let points_used: Int?
    let points_excluded: Int?
    let segments_skipped: Int?
    let mileage_rate: Double
    let currency: String
    let suggested_amount: Double
}

struct ExpenseReceiptFields: Codable, Equatable {
    let merchant: String?
    let txn_date: String?
    let amount: Double?
    let currency: String?
    let tax_amount: Double?
    let category: String?
}

/// What the server read off an odometer photo (`POST /expenses/receipts?scan=odometer`).
/// `reading` is nil when the number could not be read; `confidence` is "high" | "medium" | "low".
struct ExpenseOdometerScan: Decodable, Equatable {
    let reading: Double?
    let confidence: String?

    private enum CodingKeys: String, CodingKey { case reading, confidence }

    init(reading: Double?, confidence: String? = nil) {
        self.reading = reading
        self.confidence = confidence
    }

    // Lenient on purpose: a reading that arrives as a string ("12340") still counts, and anything odd
    // becomes "could not read" — it must never fail the upload that has already stored the photo.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let d = try? c.decodeIfPresent(Double.self, forKey: .reading) {
            reading = d
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .reading),
                  let d = Double(s.trimmingCharacters(in: .whitespaces)) {
            reading = d
        } else {
            reading = nil
        }
        confidence = (try? c.decodeIfPresent(String.self, forKey: .confidence)) ?? nil
    }
}

/// POST /expenses/receipts result: the stored object, a link to show it now, and the OCR read.
struct ExpenseUploadedReceipt: Decodable {
    let url: String
    let path: String?
    let content_type: String?
    let size: Int?
    let signed_url: String?
    let scan: ExpenseReceiptFields?
    /// Only on an upload made with `?scan=odometer`.
    let odometer: ExpenseOdometerScan?

    private enum CodingKeys: String, CodingKey { case url, path, content_type, size, signed_url, scan, odometer }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        content_type = try c.decodeIfPresent(String.self, forKey: .content_type)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
        signed_url = try c.decodeIfPresent(String.self, forKey: .signed_url)
        scan = try c.decodeIfPresent(ExpenseReceiptFields.self, forKey: .scan)
        // An odometer block the app cannot make sense of is "no reading", never a failed upload.
        odometer = (try? c.decodeIfPresent(ExpenseOdometerScan.self, forKey: .odometer)) ?? nil
    }
}

/// Which read the server should do on an uploaded photo.
enum ExpenseUploadScan: Equatable {
    /// Read it as a receipt (merchant, date, amount) — the default.
    case receipt
    /// Just store it (`?scan=0`) — e.g. an odometer photo on a policy that does not read the number.
    case storeOnly
    /// Read the odometer number (`?scan=odometer`).
    case odometer

    /// The request path for the upload.
    var path: String {
        switch self {
        case .receipt:  return "/expenses/receipts"
        case .storeOnly: return "/expenses/receipts?scan=0"
        case .odometer: return "/expenses/receipts?scan=odometer"
        }
    }
}

/// One odometer line from `GET /expenses/odometer-history` — the caller's own readings, newest first.
struct ExpenseOdometerEntry: Decodable, Identifiable, Equatable {
    let id: String
    let claim_id: String?
    let claim_no: String?
    let claim_status: String?
    let user_id: String?
    let user_name: String?
    let item_date: String?
    let vehicle_type: String?
    let vehicle_label: String?
    let odometer_start: Double?
    let odometer_end: Double?
    let distance_km: Double?
    let amount: Double?
    let start_photo_url: String?
    let end_photo_url: String?
    let created_at: String?
}

/// POST /expenses/claims/check result — what the policy says about unsaved lines.
struct ExpenseClaimCheck: Decodable {
    let policy: ExpensePolicy?
    let total: Double?
    let violations: [ExpenseFlag]?
    /// True when a "block" policy would refuse to submit these lines.
    let blocking: Bool?
    let would_auto_approve: Bool?
}

struct ExpenseDecisionResult: Decodable {
    let ok: Bool?
    let status: String?
    let approved_amount: Double?
    let rejected_lines: Int?
    /// True when approval passed the claim to the next manager instead of finishing it.
    let escalated: Bool?
}

// MARK: - Request bodies

struct ExpenseClaimItemInput: Encodable, Equatable {
    /// Set when editing an existing line, so the server keeps its receipt and history.
    let id: String?
    let category: String
    let item_date: String?
    let description: String?
    let amount: Double?
    let distance_km: Double?
    let from_location: String?
    let to_location: String?
    let merchant: String?
    /// Omit to keep the receipt on file, "" to remove it, a URL to attach one.
    let receipt_url: String?
    /// What OCR read off the receipt, kept on the line for the approver's audit.
    let ai_extracted: ExpenseReceiptFields?
    // Travel allowance by vehicle: the server works the distance and amount out from the readings.
    // nil is omitted (keep what is on file); "" clears a photo.
    let vehicle_type: String?
    let odometer_start: Double?
    let odometer_end: Double?
    let odometer_start_photo_url: String?
    let odometer_end_photo_url: String?
}

struct ExpenseClaimInput: Encodable {
    let title: String?
    let items: [ExpenseClaimItemInput]
}

struct ExpenseClaimCheckInput: Encodable {
    let items: [ExpenseClaimItemInput]
    let claim_id: String?
}

/// One line's decision inside a decision request.
struct ExpenseLineDecisionInput: Encodable, Equatable {
    let id: String
    let decision: String          // approved | rejected
    let note: String?
}

/// Approve or reject a claim, optionally line by line. Rejecting — the claim or
/// any line — requires a non-blank note; the server refuses otherwise.
struct ExpenseDecisionInput: Encodable {
    let decision: String
    let note: String?
    let items: [ExpenseLineDecisionInput]?
}

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case mileage, travel, food, lodging, fuel, toll, misc
    var id: String { rawValue }
    var label: String { self == .misc ? "Other" : rawValue.capitalized }
}

// MARK: - Daily odometer trip (two-step: start in the morning, end in the evening)

/// One day's odometer trip, as `/expenses/odometer-trip` reports it. A trip is the mileage line of that day's
/// draft claim: `status` is "none" before it exists, "open" after the start reading is in, and "closed" once the
/// end reading closes it and the claim is priced. `amount` / `distance_km` are set once the trip is closed.
///
/// Decoded leniently so a field the server omits (or an amount that is null until the trip closes) never fails the
/// whole response — a missing non-optional falls back to a sensible default, the same idiom as ExpenseUploadedReceipt.
struct OdometerTrip: Decodable, Equatable {
    let claim_id: String
    let claim_no: String?
    let claim_status: String
    let item_id: String
    let date: String?
    let vehicle_type: String?
    let odometer_start: Double?
    let odometer_end: Double?
    let distance_km: Double?
    let amount: Double
    let start_photo_url: String?
    let end_photo_url: String?
    /// "none" | "open" | "closed".
    let status: String
    let editable: Bool

    private enum CodingKeys: String, CodingKey {
        case claim_id, claim_no, claim_status, item_id, date, vehicle_type
        case odometer_start, odometer_end, distance_km, amount
        case start_photo_url, end_photo_url, status, editable
    }

    init(claim_id: String, claim_no: String? = nil, claim_status: String = "draft", item_id: String = "",
         date: String? = nil, vehicle_type: String? = nil, odometer_start: Double? = nil, odometer_end: Double? = nil,
         distance_km: Double? = nil, amount: Double = 0, start_photo_url: String? = nil, end_photo_url: String? = nil,
         status: String = "none", editable: Bool = true) {
        self.claim_id = claim_id; self.claim_no = claim_no; self.claim_status = claim_status; self.item_id = item_id
        self.date = date; self.vehicle_type = vehicle_type; self.odometer_start = odometer_start
        self.odometer_end = odometer_end; self.distance_km = distance_km; self.amount = amount
        self.start_photo_url = start_photo_url; self.end_photo_url = end_photo_url
        self.status = status; self.editable = editable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claim_id = (try? c.decodeIfPresent(String.self, forKey: .claim_id)) ?? ""
        claim_no = (try? c.decodeIfPresent(String.self, forKey: .claim_no)) ?? nil
        claim_status = (try? c.decodeIfPresent(String.self, forKey: .claim_status)) ?? "draft"
        item_id = (try? c.decodeIfPresent(String.self, forKey: .item_id)) ?? ""
        date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? nil
        vehicle_type = (try? c.decodeIfPresent(String.self, forKey: .vehicle_type)) ?? nil
        odometer_start = (try? c.decodeIfPresent(Double.self, forKey: .odometer_start)) ?? nil
        odometer_end = (try? c.decodeIfPresent(Double.self, forKey: .odometer_end)) ?? nil
        distance_km = (try? c.decodeIfPresent(Double.self, forKey: .distance_km)) ?? nil
        amount = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        start_photo_url = (try? c.decodeIfPresent(String.self, forKey: .start_photo_url)) ?? nil
        end_photo_url = (try? c.decodeIfPresent(String.self, forKey: .end_photo_url)) ?? nil
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "none"
        editable = (try? c.decodeIfPresent(Bool.self, forKey: .editable)) ?? true
    }
}

/// `/expenses/odometer-trip` (GET / start / end). When the flow is NOT opted in the server answers only
/// `{ enabled:false, date, trip:null }`, so every config field is optional/defaulted here. The `/end` response
/// carries, in addition, the built and priced `claim` ready to submit.
struct OdometerTripResponse: Decodable {
    let enabled: Bool
    let date: String
    let trip: OdometerTrip?
    let vehicle_rates: [ExpenseVehicleRate]
    let sole_vehicle: String?
    let photos_required: Bool
    let camera_only: Bool
    /// Only on the `/end` response: the built, priced, ready-to-submit claim.
    let claim: ExpenseClaim?

    private enum CodingKeys: String, CodingKey {
        case enabled, date, trip, vehicle_rates, sole_vehicle, photos_required, camera_only, claim
    }

    init(enabled: Bool, date: String, trip: OdometerTrip?, vehicle_rates: [ExpenseVehicleRate] = [],
         sole_vehicle: String? = nil, photos_required: Bool = true, camera_only: Bool = false, claim: ExpenseClaim? = nil) {
        self.enabled = enabled; self.date = date; self.trip = trip; self.vehicle_rates = vehicle_rates
        self.sole_vehicle = sole_vehicle; self.photos_required = photos_required; self.camera_only = camera_only
        self.claim = claim
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? ""
        // A malformed trip object counts as "no trip" (status none), never a failed response.
        trip = (try? c.decodeIfPresent(OdometerTrip.self, forKey: .trip)) ?? nil
        vehicle_rates = (try? c.decodeIfPresent([ExpenseVehicleRate].self, forKey: .vehicle_rates)) ?? []
        sole_vehicle = (try? c.decodeIfPresent(String.self, forKey: .sole_vehicle)) ?? nil
        photos_required = (try? c.decodeIfPresent(Bool.self, forKey: .photos_required)) ?? true
        camera_only = (try? c.decodeIfPresent(Bool.self, forKey: .camera_only)) ?? false
        claim = (try? c.decodeIfPresent(ExpenseClaim.self, forKey: .claim)) ?? nil
    }
}

/// POST /expenses/odometer-trip/start. `vehicle_type` may be omitted when the policy has a single vehicle (the
/// server falls back to it); `start_photo_url` is omitted when no photo was taken (policies that do not require one).
struct OdometerTripStartInput: Encodable {
    let odometer_start: Double
    let vehicle_type: String?
    let start_photo_url: String?
    let date: String?
}

/// POST /expenses/odometer-trip/end.
struct OdometerTripEndInput: Encodable {
    let odometer_end: Double
    let end_photo_url: String?
    let date: String?
}
