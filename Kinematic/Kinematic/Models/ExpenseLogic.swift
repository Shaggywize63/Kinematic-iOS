// ExpenseLogic — the rules behind the expense screens, kept free of SwiftUI so
// they can be unit-tested (see KinematicTests/ExpenseLogicTests). The screens
// only render what these decide.

import Foundation

// MARK: - Errors

enum ExpenseErrors {
    /// The message inside an API error body: `{ "error": "..." }` or `{ "error": { "message": "..." } }`.
    static func serverMessage(in data: Data) -> String? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let s = obj["error"] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s }
        if let e = obj["error"] as? [String: Any], let m = e["message"] as? String, !m.isEmpty { return m }
        if let m = obj["message"] as? String, !m.isEmpty { return m }
        return nil
    }

    /// What to show: the server's own words (written for the user), else a plain line per status.
    static func message(serverMessage: String?, status: Int) -> String {
        if let m = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { return m }
        switch status {
        case 401: return "Your session has expired — sign in again."
        case 403: return "You don't have permission to do that."
        case 404: return "That claim could not be found."
        case 413: return "That file is too large (10 MB maximum)."
        case 500...599: return "The server had a problem. Try again in a moment."
        default: return "Request failed (\(status))"
        }
    }
}

// MARK: - Claims

enum ExpenseLogic {
    static let categories = ExpenseCategory.allCases.map { $0.rawValue }

    /// The one place a category's name is worked out: the policy's own name for it (`category_labels`,
    /// e.g. "mileage" → "Travel") when it has one, else the built-in name. Every screen goes through here.
    static func categoryLabel(_ c: String, labels: [String: String]? = nil) -> String {
        customLabel(c, labels: labels) ?? (c == "misc" ? "Other" : c.capitalized)
    }

    /// The policy's own name for a category, or nil when it set none (a blank name counts as none).
    static func customLabel(_ c: String, labels: [String: String]?) -> String? {
        guard let l = labels?[c]?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty else { return nil }
        return l
    }

    // MARK: Policy switches (all optional on the wire; absent = the behaviour before they existed)

    /// The categories the policy lets a line use (a category the policy does not mention is allowed).
    static func enabledCategories(_ rules: ExpensePolicyRules?) -> [String] {
        categories.filter { rules?.categories?[$0]?.enabled != false }
    }

    /// Single-category mode: exactly one category is enabled. Nil for a policy that leaves several (or none) on,
    /// and for no policy at all.
    static func singleCategory(_ rules: ExpensePolicyRules?) -> String? {
        let enabled = enabledCategories(rules)
        return enabled.count == 1 ? enabled[0] : nil
    }

    /// What a new line starts as: the only enabled category in single-category mode, else "food" as always.
    static func defaultCategory(_ rules: ExpensePolicyRules?) -> String { singleCategory(rules) ?? "food" }

    /// The categories a line may be switched to — the enabled ones, plus the line's current category so an
    /// older claim that uses a now-disabled category still renders (and can be moved off it).
    static func allowedCategories(_ rules: ExpensePolicyRules?, current: String) -> [String] {
        categories.filter { $0 == current || rules?.categories?[$0]?.enabled != false }
    }

    /// The category picker is hidden in single-category mode — unless the line is an older one on another
    /// category, which still needs a way to be moved to the allowed one.
    static func showsCategoryPicker(_ rules: ExpensePolicyRules?, current: String) -> Bool {
        singleCategory(rules) == nil || allowedCategories(rules, current: current).count > 1
    }

    /// From / To on mileage lines (default on).
    static func showsRoute(_ rules: ExpensePolicyRules?) -> Bool { rules?.route_fields != false }

    /// A claim of exactly one line: no "Add another expense" (default off).
    static func isSingleLine(_ rules: ExpensePolicyRules?) -> Bool { rules?.single_line == true }

    /// Odometer photos only from the camera, and the reading is read from the photo (default off).
    static func odometerCameraOnly(_ rules: ExpensePolicyRules?) -> Bool { rules?.odometer_camera_only == true }

    /// Mileage is priced by vehicle from odometer readings.
    static func paysByVehicle(_ rules: ExpensePolicyRules?) -> Bool { !(rules?.vehicle_rates ?? []).isEmpty }

    /// The vehicles the Vehicle picker offers: those of the policy that governs the signed-in person, nothing else.
    /// GET /expenses/policy already answers with that person's own policy (the one naming them, else their role's,
    /// else everyone's), so its `vehicle_rates` ARE their vehicles; no built-in or other policy's list is mixed in.
    /// In the policy's order; a blank or repeated id is dropped (it could not be told apart in the picker).
    static func policyVehicles(_ rules: ExpensePolicyRules?) -> [ExpenseVehicleRate] {
        var seen = Set<String>()
        var out: [ExpenseVehicleRate] = []
        for v in rules?.vehicle_rates ?? [] {
            let id = v.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty || seen.contains(v.id) { continue }
            seen.insert(v.id)
            out.append(v)
        }
        return out
    }

    /// The vehicle a mileage line starts with: the policy's ONLY vehicle. Nil when the policy lists none or
    /// several — then the person chooses. (The server also falls back to a sole vehicle when a line has none.)
    static func soleVehicleId(_ vehicles: [ExpenseVehicleRate]?) -> String? {
        guard let list = vehicles, list.count == 1 else { return nil }
        return list[0].id
    }

    /// Claims the owner may still change: before approval, or being fixed after a rejection.
    static func isEditable(_ status: String?) -> Bool {
        ["draft", "submitted", "rejected"].contains((status ?? "draft").lowercased())
    }

    /// Part of the claim was approved but not all of it.
    static func isPartlyApproved(_ c: ExpenseClaim) -> Bool {
        let s = (c.status ?? "").lowercased()
        guard let approved = c.approved_amount else { return false }
        return (s == "approved" || s == "reimbursed") && approved < c.total_amount - 0.005
    }

    /// What the claimant will actually be paid (the approved amount once decided, otherwise the claimed total).
    static func payable(_ c: ExpenseClaim) -> Double {
        let s = (c.status ?? "").lowercased()
        if let a = c.approved_amount, s == "approved" || s == "reimbursed" { return a }
        return c.total_amount
    }

    /// Plain-language names for the policy checks the server reports.
    static func flagLabel(_ code: String) -> String {
        switch code {
        case "category_not_allowed":    return "Not reimbursable"
        case "receipt_missing":         return "Receipt needed"
        case "over_category_limit":     return "Over daily limit"
        case "over_claim_category_limit": return "Over claim limit"
        case "over_month_limit":        return "Over monthly limit"
        case "over_claim_limit":        return "Over claim maximum"
        case "late_submission":         return "Submitted late"
        case "future_date":             return "Future date"
        case "vehicle_missing":         return "Pick a vehicle"
        case "odometer_missing":        return "Odometer reading needed"
        case "odometer_invalid":        return "Odometer reading wrong"
        case "odometer_photo_missing":  return "Odometer photo needed"
        default:
            let s = code.replacingOccurrences(of: "_", with: " ")
            return s.prefix(1).uppercased() + s.dropFirst()
        }
    }

    /// Flags that belong to the line at `index` of a policy check (unsaved lines are identified by position).
    static func flags(forLine index: Int, in flags: [ExpenseFlag]?) -> [ExpenseFlag] {
        (flags ?? []).filter { $0.item_id == String(index) }
    }

    /// Flags that are about the claim as a whole rather than one line.
    static func claimLevelFlags(_ flags: [ExpenseFlag]?) -> [ExpenseFlag] {
        (flags ?? []).filter { ($0.item_id ?? "").isEmpty || Int($0.item_id ?? "") == nil }
    }

    /// Whether a manager should be offered a one-tap approval — not when the policy flagged something serious.
    static func canQuickApprove(_ c: ExpenseClaim) -> Bool {
        !(c.ai_flags ?? []).contains { $0.severity == "high" }
    }

    /// Mirrors the backend's approver roles; a field executive (data scope "own") never approves.
    /// An unknown role keeps the entry, since the API is the authority.
    static func canApprove(role: String?, dataScope: String?) -> Bool {
        guard let role = role?.trimmingCharacters(in: .whitespaces).lowercased(), !role.isEmpty else { return true }
        if (dataScope ?? "").lowercased() == "own" { return false }
        let approverRoles: Set<String> = ["super_admin", "admin", "main_admin", "org_admin", "sub_admin", "client",
                                          "city_manager", "supervisor", "manager", "hr", "program_manager"]
        return approverRoles.contains(role)
    }

    static func money(_ v: Double, _ currency: String) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        let n = f.string(from: NSNumber(value: v)) ?? String(v)
        return currency == "INR" ? "₹\(n)" : "\(currency) \(n)"
    }

    /// The vehicle a line was priced with, if the policy still lists it.
    static func vehicleRate(_ id: String?, in vehicles: [ExpenseVehicleRate]?) -> ExpenseVehicleRate? {
        guard let id = id, !id.isEmpty else { return nil }
        return (vehicles ?? []).first { $0.id == id }
    }

    /// The policy's own label when the vehicle is still listed, else "two_wheeler" → "Two wheeler".
    static func vehicleName(_ id: String?, in vehicles: [ExpenseVehicleRate]?) -> String {
        if let v = vehicleRate(id, in: vehicles), !v.label.trimmingCharacters(in: .whitespaces).isEmpty { return v.label }
        let t = (id ?? "").replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// "120", "99.5" — no trailing zeros, for putting a number back into a text field.
    static func trimNumber(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // MARK: Odometer history

    private static let dayIn: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let dayOut: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "d MMM yyyy"; return f
    }()

    /// "2026-10-05" (or a full timestamp) → "5 Oct 2026". Anything that is not a date is shown as typed (first 10 characters).
    static func shortDate(_ iso: String?) -> String? {
        guard let iso = iso, iso.count >= 10 else { return nil }
        let day = String(iso.prefix(10))
        guard let d = dayIn.date(from: day) else { return day }
        return dayOut.string(from: d)
    }

    /// The newest odometer reading the person has on file — the end reading of the newest line, else its start.
    /// `history` is newest first (as the server sends it). Lines of `claimId` — the claim being edited — are
    /// skipped, so a draft does not offer its own reading back as "last".
    static func lastReading(in history: [ExpenseOdometerEntry], excludingClaim claimId: String? = nil) -> ExpenseLastReading? {
        for e in history {
            if let cid = claimId, !cid.isEmpty, e.claim_id == cid { continue }
            if let km = e.odometer_end ?? e.odometer_start { return ExpenseLastReading(km: km, date: e.item_date) }
        }
        return nil
    }

    /// "Last reading: 12392 km (5 Oct 2026)".
    static func lastReadingText(_ r: ExpenseLastReading) -> String {
        var s = "Last reading: \(trimNumber(r.km)) km"
        if let d = shortDate(r.date) { s += " (\(d))" }
        return s
    }
}

/// The newest odometer reading on file, for the hint under the "before" field.
struct ExpenseLastReading: Equatable {
    let km: Double
    let date: String?
}

extension ExpenseOdometerEntry {
    /// The vehicle's name: the policy label the server sent, else "two_wheeler" → "Two wheeler"; "" when unknown.
    var vehicleText: String {
        let l = (vehicle_label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return l.isEmpty ? ExpenseLogic.vehicleName(vehicle_type, in: nil) : l
    }

    /// "12340 → 12392" (a missing end shows "—"); nil when the line has no readings.
    var readingsText: String? {
        guard odometer_start != nil || odometer_end != nil else { return nil }
        let a = odometer_start.map { ExpenseLogic.trimNumber($0) } ?? "—"
        let b = odometer_end.map { ExpenseLogic.trimNumber($0) } ?? "—"
        return "\(a) → \(b)"
    }

    /// The claim's status as a label, "Draft" when the server sent none.
    var statusText: String { (claim_status ?? "draft").capitalized }
}

// MARK: - Editing a claim

/// The values of one line in the editor, as plain data.
struct ExpenseLineFields: Equatable {
    var id: String? = nil
    var category: String = "food"
    var itemDate: String = ""          // yyyy-MM-dd
    var amount: String = ""
    var description: String = ""
    var merchant: String = ""
    var fromLocation: String = ""
    var toLocation: String = ""
    var distanceKm: String = ""
    /// The reference to store on the line (empty when there is no receipt).
    var receiptUrl: String = ""
    /// The line already had a receipt when the editor opened.
    var hadReceipt: Bool = false
    /// What OCR read from a receipt attached in this session.
    var ocr: ExpenseReceiptFields? = nil
    // Travel allowance by vehicle — the vehicle id and the odometer readings before / after, each with the
    // stored reference of its photo. Distance and amount come from these.
    var vehicleType: String = ""
    var odometerStart: String = ""
    var odometerEnd: String = ""
    var odoStartPhoto: String = ""
    var odoEndPhoto: String = ""
    /// The line already had that photo when the editor opened (so removing it must be sent as "").
    var hadOdoStartPhoto: Bool = false
    var hadOdoEndPhoto: Bool = false

    private static func positive(_ s: String) -> Double? {
        guard let v = Double(s.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        return v
    }

    /// An odometer reading: any number from 0 up (a new bike can read 0).
    private static func reading(_ s: String) -> Double? {
        guard let v = Double(s.trimmingCharacters(in: .whitespaces)), v >= 0, v.isFinite else { return nil }
        return v
    }

    /// Km travelled, or nil until both readings are in and in order.
    var odometerKm: Double? {
        guard let start = Self.reading(odometerStart), let end = Self.reading(odometerEnd), end >= start else { return nil }
        return ((end - start) * 100).rounded() / 100
    }

    /// What is wrong with the pair of readings right now, or nil (an incomplete pair is not an error yet).
    var odometerOrderProblem: String? {
        guard let start = Self.reading(odometerStart), let end = Self.reading(odometerEnd) else { return nil }
        return end < start ? "The reading after the trip is lower than the reading before it." : nil
    }

    /// Anything typed or attached — an untouched blank line is simply dropped on save.
    var isFilled: Bool {
        !amount.isEmpty || !distanceKm.isEmpty || !merchant.isEmpty || !description.isEmpty ||
            !receiptUrl.isEmpty || !fromLocation.isEmpty || !toLocation.isEmpty ||
            !vehicleType.isEmpty || !odometerStart.isEmpty || !odometerEnd.isEmpty ||
            !odoStartPhoto.isEmpty || !odoEndPhoto.isEmpty
    }

    /// A mileage line that has no vehicle yet — the one the policy's only vehicle is pre-selected on.
    var lacksVehicle: Bool {
        category == "mileage" && vehicleType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// This line with the policy's only vehicle (`sole`, see `ExpenseLogic.soleVehicleId`) pre-selected. Only a
    /// mileage line with no vehicle takes it — a vehicle the line already has is never replaced, and other
    /// categories are left alone. Nil / blank `sole` (no policy yet, none or several vehicles) changes nothing.
    func withSoleVehicle(_ sole: String?) -> ExpenseLineFields {
        guard let sole = sole, !sole.isEmpty, lacksVehicle else { return self }
        var out = self
        out.vehicleType = sole
        return out
    }

    /// `isFilled`, except that on a NEW line (not yet saved on the claim) the pre-selected sole vehicle alone is
    /// not something the person entered: an untouched form still says "Add at least one expense", is dropped on
    /// save and is not sent to the live policy check. A saved line always counts what it has.
    func isFilledIgnoring(soleVehicle sole: String?) -> Bool {
        guard id == nil, let sole = sole, !sole.isEmpty, vehicleType == sole else { return isFilled }
        var rest = self
        rest.vehicleType = ""
        return rest.isFilled
    }

    /// A filled line can be saved when it has an amount (or, for mileage, a distance).
    var isValid: Bool { canSave(byVehicle: false) }

    /// Where the policy pays mileage by vehicle (`byVehicle`) a draft only needs something to go on — the
    /// vehicle or a reading; the rest is enforced when the claim is submitted and shown live by the policy check.
    func canSave(byVehicle: Bool) -> Bool {
        if category == "mileage" {
            if byVehicle { return !vehicleType.isEmpty || Self.reading(odometerStart) != nil || Self.reading(odometerEnd) != nil }
            return Self.positive(amount) != nil || Self.positive(distanceKm) != nil
        }
        return Self.positive(amount) != nil
    }

    /// The line's amount for the on-screen total. Mileage with only a distance is priced at the policy rate;
    /// by vehicle it is the odometer distance × that vehicle's rate (`vehicles` non-empty).
    func effectiveAmount(mileageRate: Double, vehicles: [ExpenseVehicleRate]? = nil) -> Double {
        if category == "mileage", let vs = vehicles, !vs.isEmpty {
            guard let km = odometerKm, let rate = ExpenseLogic.vehicleRate(vehicleType, in: vs)?.rate_per_km else { return 0 }
            return (km * rate * 100).rounded() / 100
        }
        if let a = Self.positive(amount) { return a }
        if category == "mileage", let km = Self.positive(distanceKm) { return (km * mileageRate * 100).rounded() / 100 }
        return 0
    }

    /// `routeFields` false (the policy turned From / To off): the route is never sent. Like any nil it is
    /// omitted, so a route already on file is left alone.
    func toInput(byVehicle: Bool = false, routeFields: Bool = true) -> ExpenseClaimItemInput {
        let mileage = category == "mileage"
        let vehicleLine = mileage && byVehicle
        func nonEmpty(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
        // A receipt that is attached is sent; one that was removed is cleared with "" (nil is omitted,
        // and an omitted receipt means "keep what is on file"). Odometer photos follow the same rule.
        func photo(_ url: String, had: Bool) -> String? { !url.isEmpty ? url : (had ? "" : nil) }
        let receipt: String? = photo(receiptUrl, had: hadReceipt)
        return ExpenseClaimItemInput(
            id: id,
            category: category,
            item_date: itemDate.isEmpty ? nil : itemDate,
            description: nonEmpty(description),
            // By vehicle the server works the distance and amount out from the readings; never send them.
            amount: vehicleLine ? nil : Self.positive(amount),
            distance_km: (mileage && !vehicleLine) ? Self.positive(distanceKm) : nil,
            from_location: (mileage && routeFields) ? nonEmpty(fromLocation) : nil,
            to_location: (mileage && routeFields) ? nonEmpty(toLocation) : nil,
            merchant: mileage ? nil : nonEmpty(merchant),
            receipt_url: receipt,
            ai_extracted: ocr,
            vehicle_type: vehicleLine ? nonEmpty(vehicleType) : nil,
            odometer_start: vehicleLine ? Self.reading(odometerStart) : nil,
            odometer_end: vehicleLine ? Self.reading(odometerEnd) : nil,
            odometer_start_photo_url: vehicleLine ? photo(odoStartPhoto, had: hadOdoStartPhoto) : nil,
            odometer_end_photo_url: vehicleLine ? photo(odoEndPhoto, had: hadOdoEndPhoto) : nil
        )
    }

    /// Fill what the receipt scan found into a line, never overwriting what the person already typed.
    /// `allowedCategories` (single-category mode) keeps the scan from moving the line to a category the
    /// policy does not allow; nil keeps the original rule (any known category).
    func withScan(_ scan: ExpenseReceiptFields?, receiptUrl url: String, allowedCategories: [String]? = nil) -> ExpenseLineFields {
        var out = self
        let fresh = amount.isEmpty && merchant.isEmpty
        out.receiptUrl = url
        if let scan = scan { out.ocr = scan }
        if amount.isEmpty, let a = scan?.amount { out.amount = ExpenseLogic.trimNumber(a) }
        if merchant.isEmpty, let m = scan?.merchant, !m.isEmpty { out.merchant = m }
        if fresh, let d = scan?.txn_date, !d.isEmpty { out.itemDate = String(d.prefix(10)) }
        if fresh, category != "mileage", let c = scan?.category, (allowedCategories ?? ExpenseLogic.categories).contains(c) { out.category = c }
        return out
    }

    /// Put the reading the server read off an odometer photo into the Before (`start`) or After slot,
    /// replacing what was there; the person can still edit it. A photo that could not be read leaves the
    /// slot as it was. Returns what to tell the person.
    mutating func applyOdometerScan(_ scan: ExpenseOdometerScan?, start: Bool) -> OdometerScanNote {
        guard let km = scan?.reading, km.isFinite, km >= 0 else { return .unreadable }
        if start { odometerStart = ExpenseLogic.trimNumber(km) } else { odometerEnd = ExpenseLogic.trimNumber(km) }
        return .read
    }
}

/// What to tell the person after an odometer photo went through the reader.
enum OdometerScanNote: Equatable {
    /// The number was read and is now in the field.
    case read
    /// It could not be read; the photo is attached all the same.
    case unreadable

    var text: String {
        switch self {
        case .read:       return "Read from the photo — please check"
        case .unreadable: return "Couldn't read the number — please enter it"
        }
    }
}

extension ExpenseClaimItem {
    func toFields() -> ExpenseLineFields {
        var f = ExpenseLineFields()
        f.id = id
        f.category = category
        f.itemDate = item_date ?? ""
        f.amount = amount != 0 ? ExpenseLogic.trimNumber(amount) : ""
        f.description = description ?? ""
        f.merchant = merchant ?? ""
        f.fromLocation = from_location ?? ""
        f.toLocation = to_location ?? ""
        f.distanceKm = distance_km.map { ExpenseLogic.trimNumber($0) } ?? ""
        f.receiptUrl = receipt_url ?? ""
        f.hadReceipt = !(receipt_url ?? "").isEmpty
        f.vehicleType = vehicle_type ?? ""
        f.odometerStart = odometer_start.map { ExpenseLogic.trimNumber($0) } ?? ""
        f.odometerEnd = odometer_end.map { ExpenseLogic.trimNumber($0) } ?? ""
        f.odoStartPhoto = odometer_start_photo_url ?? ""
        f.odoEndPhoto = odometer_end_photo_url ?? ""
        f.hadOdoStartPhoto = !(odometer_start_photo_url ?? "").isEmpty
        f.hadOdoEndPhoto = !(odometer_end_photo_url ?? "").isEmpty
        return f
    }

    /// "Pune → Nashik" for read-only views (a missing end shows "—"); nil when neither end was recorded, so a
    /// line without a route prints no route at all.
    var routeText: String? {
        let from = (from_location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let to = (to_location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if from.isEmpty && to.isEmpty { return nil }
        return "\(from.isEmpty ? "—" : from) → \(to.isEmpty ? "—" : to)"
    }

    /// "Two-wheeler · Odometer 12340 → 12392", for read-only views; nil when the line carries no odometer data.
    func odometerSummary(vehicles: [ExpenseVehicleRate]? = nil) -> String? {
        guard category == "mileage",
              !(vehicle_type ?? "").isEmpty || odometer_start != nil || odometer_end != nil else { return nil }
        var parts: [String] = []
        if let v = vehicle_type, !v.isEmpty { parts.append(ExpenseLogic.vehicleName(v, in: vehicles)) }
        if odometer_start != nil || odometer_end != nil {
            let a = odometer_start.map { ExpenseLogic.trimNumber($0) } ?? "—"
            let b = odometer_end.map { ExpenseLogic.trimNumber($0) } ?? "—"
            parts.append("Odometer \(a) → \(b)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Reviewing a claim

/// One line's decision while an approver reviews it.
struct ExpenseLineReview: Equatable {
    var id: String
    var approved: Bool = true
    var note: String = ""
}

enum ExpenseReview {
    /// Which rejected lines still lack the remark the server will insist on.
    static func linesMissingRemark(_ reviews: [ExpenseLineReview]) -> [String] {
        reviews.filter { !$0.approved && $0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { $0.id }
    }

    /// What would be paid if the approver approves with these line decisions.
    static func approvedTotal(items: [ExpenseClaimItem], reviews: [ExpenseLineReview]) -> Double {
        let rejected = Set(reviews.filter { !$0.approved }.map { $0.id })
        return items.filter { !rejected.contains($0.id) }.reduce(0) { $0 + $1.amount }
    }

    /// The per-line part of an approve request: every line's decision, with its remark if rejected.
    static func body(_ reviews: [ExpenseLineReview]) -> [ExpenseLineDecisionInput] {
        reviews.map {
            let note = $0.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return ExpenseLineDecisionInput(id: $0.id, decision: $0.approved ? "approved" : "rejected",
                                            note: ($0.approved || note.isEmpty) ? nil : note)
        }
    }

    /// For rejecting the whole claim: only lines where the reviewer already wrote their own remark need to be sent.
    static func ownRemarks(_ reviews: [ExpenseLineReview]) -> [ExpenseLineDecisionInput] {
        reviews.compactMap {
            let note = $0.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return (!$0.approved && !note.isEmpty) ? ExpenseLineDecisionInput(id: $0.id, decision: "rejected", note: note) : nil
        }
    }
}

// MARK: - History

enum ExpenseStepTone { case done, bad, waiting, info }

struct ExpenseTimelineStep: Equatable {
    var title: String
    var date: String? = nil
    var tone: ExpenseStepTone = .info
    /// The approver's remark on this decision.
    var remark: String? = nil
    /// Rejected lines in this decision, each with its own remark.
    var rejectedLines: [String] = []
}

/// The claim's story: created, each submission, each decision with its remark, reimbursement.
/// `categoryLabels` is the policy's `category_labels`, so a renamed category reads the same here as everywhere else.
func expenseTimeline(_ c: ExpenseClaim, categoryLabels: [String: String]? = nil) -> [ExpenseTimelineStep] {
    var out = [ExpenseTimelineStep(title: "Claim created", date: c.created_at.map { String($0.prefix(10)) })]
    let approvals = c.approvals ?? []
    var rounds: [Int] = []
    for a in approvals { let r = a.round ?? 1; if !rounds.contains(r) { rounds.append(r) } }
    let multi = rounds.count > 1 || (c.submit_count ?? 1) > 1
    var last = 0

    func lineText(_ d: ExpenseItemDecision) -> String {
        var s = "\(ExpenseLogic.categoryLabel(d.category ?? "misc", labels: categoryLabels)) · \(ExpenseLogic.money(d.amount ?? 0, c.currency))"
        if let n = d.note, !n.isEmpty { s += " — \(n)" }
        return s
    }

    for a in approvals {
        let r = a.round ?? 1
        if r != last {
            last = r
            let title = multi ? "Submitted\(r > 1 ? " again" : "") (attempt \(r))" : "Submitted for approval"
            out.append(ExpenseTimelineStep(title: title, date: r == rounds.last ? c.submitted_at.map { String($0.prefix(10)) } : nil))
        }
        let who = a.approver_name ?? "approver"
        let level = a.level > 1 ? " (level \(a.level))" : ""
        let rejected = (a.item_decisions ?? []).filter { $0.decision == "rejected" }
        let remark = (a.note ?? "").isEmpty ? nil : a.note
        let date = a.decided_at.map { String($0.prefix(10)) }
        switch a.status {
        case "pending":
            out.append(ExpenseTimelineStep(title: "Waiting for \(who)\(level)", tone: .waiting))
        case "approved":
            out.append(ExpenseTimelineStep(title: "\(rejected.isEmpty ? "Approved" : "Partly approved") by \(who)\(level)", date: date,
                                           tone: .done, remark: remark, rejectedLines: rejected.map(lineText)))
        default:
            out.append(ExpenseTimelineStep(title: "Rejected by \(who)\(level)", date: date, tone: .bad, remark: remark,
                                           rejectedLines: rejected.filter { !($0.note ?? "").isEmpty }.map(lineText)))
        }
    }
    if c.auto_approved == true {
        out.append(ExpenseTimelineStep(title: "Approved automatically under the policy", date: c.reviewed_at.map { String($0.prefix(10)) }, tone: .done))
    }
    if (c.status ?? "") == "cancelled" { out.append(ExpenseTimelineStep(title: "Cancelled")) }
    if let paid = c.reimbursed_at, !paid.isEmpty {
        let ref = (c.reimbursed_ref ?? "").isEmpty ? "" : " · ref \(c.reimbursed_ref ?? "")"
        out.append(ExpenseTimelineStep(title: "Reimbursed\(ref)", date: String(paid.prefix(10)), tone: .done))
    }
    return out
}
