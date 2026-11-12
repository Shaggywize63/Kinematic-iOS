import Foundation

// Spark & Ray account-journey logic: account updates, multi-assignee / product /
// form-serial activities, and the quotation + product-lines deal form.
//
// Everything here is pure (no UI, no network) so it can be unit-tested; the views
// and `CRMService` just call into it. Every control built on this is shown ONLY for
// the Spark & Ray client — `SparkJourney.isActive` is the same client-id gate the
// Spark lead create / edit forms use (`LeadB2B.sparkClientId`). Other tenants never
// see it and never send these fields.

/// A `{ id, name }` reference the backend stamps on Spark activities
/// (`assignees`, `products`). Decoding is forgiving — a missing key reads as an
/// empty string — so one odd row can never fail the whole activity list.
struct SparkNamedRef: Codable, Identifiable, Hashable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey { case id, name }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
    }
}

/// One note on a Spark account's "Recent updates" timeline
/// (`GET /crm/accounts/:id/updates`). Optionally tied to one of the account's
/// contacts.
struct AccountUpdate: Codable, Identifiable, Hashable {
    let id: String
    let accountId: String?
    let contactId: String?
    let body: String
    let createdBy: String?
    let createdAt: String?
    let updatedAt: String?
    let contactName: String?
    let authorName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case contactId = "contact_id"
        case body
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case contactName = "contact_name"
        case authorName = "author_name"
    }
}

enum SparkJourney {
    /// Backend caps: `assignee_ids` (max 20) and an update's `body` (1...4000).
    static let maxAssignees = 20
    static let maxUpdateLength = 4000

    /// True when `clientId` is the Spark & Ray client (case-insensitive).
    static func isSpark(clientId: String?) -> Bool {
        (clientId ?? "").lowercased() == LeadB2B.sparkClientId
    }

    /// The live gate: is the effective client Spark & Ray? Goes through
    /// `CRMClientScope.effectiveClientId()` (picker selection first, else the signed-in
    /// user's own client) so a client admin pinned to Spark by their login is covered.
    /// EVERY Spark gate (lead / deal / activity / expense forms) must use this.
    static var isActive: Bool {
        isSpark(clientId: CRMClientScope.effectiveClientId())
    }

    // MARK: Account updates

    /// POST body for a new account update, or nil when `text` is blank. The text is
    /// trimmed and clamped to the backend's 4000 characters; `contact_id` is added
    /// only when a contact was picked ("No specific contact" sends none).
    static func updateBody(text: String, contactId: String?) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var body: [String: Any] = ["body": String(trimmed.prefix(maxUpdateLength))]
        if let contactId, !contactId.isEmpty { body["contact_id"] = contactId }
        return body
    }

    /// Parse the backend's ISO-8601 timestamps (with or without fractional seconds).
    static func parseISO(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        return ISO8601DateFormatter().date(from: raw)
    }

    /// "5 min. ago" style text for an ISO timestamp; empty when it can't be parsed.
    static func relativeTime(_ raw: String?, now: Date = Date()) -> String {
        guard let date = parseISO(raw) else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }

    // MARK: Form serial

    /// A form serial as the backend expects it: no whitespace anywhere, upper-case
    /// (`" srpr2627-12 "` -> `"SRPR2627-12"`).
    static func normalizedSerial(_ raw: String) -> String {
        raw.components(separatedBy: .whitespacesAndNewlines).joined().uppercased()
    }

    /// Whether a server error message is about the form serial (so the composer
    /// shows it under the serial field rather than as a general error).
    static func isSerialError(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("serial") || m.contains("form")
    }

    // MARK: Multi-select helpers (order = tap order; first = Primary)

    /// `ids` with `id` toggled: removed when present, otherwise appended (ignored
    /// once `limit` is reached).
    static func toggled(_ id: String, in ids: [String], limit: Int = Int.max) -> [String] {
        if let i = ids.firstIndex(of: id) {
            var out = ids
            out.remove(at: i)
            return out
        }
        guard ids.count < limit else { return ids }
        return ids + [id]
    }

    /// `ids` with `id` moved to the front (the Primary slot). Unchanged when `id`
    /// isn't selected.
    static func makingPrimary(_ id: String, in ids: [String]) -> [String] {
        guard let i = ids.firstIndex(of: id) else { return ids }
        var out = ids
        out.remove(at: i)
        return [id] + out
    }

    /// `ids` without blanks or repeats, first occurrence kept, in order.
    static func deduped(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in ids where !id.isEmpty && seen.insert(id).inserted { out.append(id) }
        return out
    }

    // MARK: Numbers

    /// Parse a typed number: surrounding spaces and thousands commas are ignored;
    /// blank / non-numeric / non-finite reads as nil.
    static func parseNumber(_ raw: String) -> Double? {
        let t = raw.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }

    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// Editable text for a price: whole numbers without decimals, else 2 dp.
    static func priceText(_ v: Double) -> String {
        guard v.isFinite else { return "" }
        if v == v.rounded(), abs(v) < 1e12 { return String(Int(v)) }
        return String(format: "%.2f", v)
    }
}

// MARK: - Activity extras

/// The Spark-only values on an activity: who it is assigned to (first = primary),
/// "Product interested" ids, the linked product-form serial and the activity's Outcome.
struct SparkActivityExtras: Equatable {
    var assigneeIds: [String] = []
    var productIds: [String] = []
    var formSerial: String = ""
    /// The activity's Outcome text (<= 500 characters; required once the activity is completed).
    var outcome: String = ""

    /// The extras as they will be sent: no blanks / repeats, at most 20 assignees,
    /// the serial normalised.
    var cleaned: SparkActivityExtras {
        SparkActivityExtras(
            assigneeIds: Array(SparkJourney.deduped(assigneeIds).prefix(SparkJourney.maxAssignees)),
            productIds: SparkJourney.deduped(productIds),
            formSerial: SparkJourney.normalizedSerial(formSerial),
            outcome: SparkActivityOutcome.clamped(outcome)
        )
    }

    /// Merge into an activity POST / PATCH body. Only what is needed goes on the
    /// wire: on create (`previous == nil`) the non-empty values; on edit only the
    /// values that differ from `previous`, so an untouched edit never re-sends (and
    /// re-notifies) assignees. Clearing products sends `[]`; clearing the serial
    /// sends `""` (the backend's clear signal). Removing every assignee on an edit
    /// sends `assignee_ids: []`, which the backend turns into "no assignee" (it
    /// clears `assigned_to`); on create an empty list is simply left out.
    func apply(to body: inout [String: Any], previous: SparkActivityExtras? = nil) {
        let now = cleaned
        let before = previous?.cleaned
        let assigneesChanged = before == nil ? !now.assigneeIds.isEmpty : now.assigneeIds != before?.assigneeIds
        if assigneesChanged {
            body["assignee_ids"] = now.assigneeIds
        }
        if now.productIds != (before?.productIds ?? []) {
            body["product_ids"] = now.productIds
        }
        if now.formSerial != (before?.formSerial ?? "") {
            body["form_serial"] = now.formSerial
        }
        // The outcome: on create only when filled (blank is left out); on edit only when it changed, and a
        // cleared one goes out as an explicit null.
        if now.outcome != (before?.outcome ?? "") {
            body["outcome"] = now.outcome.isEmpty ? NSNull() : now.outcome
        }
    }
}

/// Everything the activity composer hands back on save, including the Spark extras.
/// Hosts that opt in via `ActivityComposeView.sparkSubmit(_:)` receive this instead
/// of the fixed 7-argument `onSubmit` callback.
struct ActivityComposeResult {
    let type: String
    let subject: String
    let description: String
    let imageUrl: String?
    let when: Date
    let leadId: String?
    let customFields: [String: Any]
    let extras: SparkActivityExtras
    /// Editing only: whether the date was edited. An untouched date sends no `completed_at` / `due_at`.
    /// Creating (and every existing caller) keeps the default: the date is sent.
    var whenEdited: Bool = true
    /// Editing only: the keys of a changed "Linked entity" (`<type>_id` set, the other three null); empty when
    /// the link is untouched.
    var linkPatch: [String: Any] = [:]
}

// MARK: - Deal lines

/// One editable product line on the Spark deal form.
struct DealLineDraft: Identifiable, Equatable {
    let id: UUID
    var productId: String?
    var name: String
    var quantityText: String
    var unitPriceText: String

    init(id: UUID = UUID(), productId: String? = nil, name: String = "",
         quantityText: String = "1", unitPriceText: String = "") {
        self.id = id
        self.productId = productId
        self.name = name
        self.quantityText = quantityText
        self.unitPriceText = unitPriceText
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var quantity: Double { SparkJourney.parseNumber(quantityText) ?? 0 }
    var unitPrice: Double { SparkJourney.parseNumber(unitPriceText) ?? 0 }

    /// Qty x unit price, to 2 dp. Zero while either is unusable.
    var lineTotal: Double {
        guard isValid else { return 0 }
        return SparkJourney.round2(quantity * unitPrice)
    }

    /// Nothing entered yet (the default quantity of 1 doesn't count) — ignored on save.
    var isBlank: Bool {
        trimmedName.isEmpty && productId == nil
            && unitPriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// An empty price means 0; otherwise it must be a number >= 0.
    private var hasValidPrice: Bool {
        if unitPriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        guard let v = SparkJourney.parseNumber(unitPriceText) else { return false }
        return v >= 0
    }

    /// What the backend accepts: a name, quantity > 0, unit price >= 0.
    var isValid: Bool {
        !trimmedName.isEmpty && quantity > 0 && hasValidPrice
    }

    /// The `items[]` entry: `product_id` (when from the catalogue), name, quantity,
    /// unit_price.
    var payload: [String: Any] {
        var d: [String: Any] = [
            "name": trimmedName,
            "quantity": quantity,
            "unit_price": unitPrice,
        ]
        if let productId, !productId.isEmpty { d["product_id"] = productId }
        return d
    }

    /// Prefill this line from a catalogue product: name + its price.
    mutating func apply(product: Product) {
        productId = product.id
        name = product.name
        unitPriceText = SparkJourney.priceText(product.unitPrice ?? 0)
    }
}

enum DealLines {
    /// Lines the rep actually filled in (blank rows are dropped on save).
    static func active(_ lines: [DealLineDraft]) -> [DealLineDraft] {
        lines.filter { !$0.isBlank }
    }

    /// Sum of the valid filled-in lines' totals.
    static func grandTotal(_ lines: [DealLineDraft]) -> Double {
        SparkJourney.round2(active(lines).reduce(0) { $0 + $1.lineTotal })
    }

    /// The `items[]` for the request — valid filled-in lines only.
    static func payload(_ lines: [DealLineDraft]) -> [[String: Any]] {
        active(lines).filter { $0.isValid }.map { $0.payload }
    }

    /// A readable message for the first filled-in line the backend would reject,
    /// or nil when every filled-in line is fine.
    static func firstProblem(_ lines: [DealLineDraft]) -> String? {
        for (i, line) in lines.enumerated() where !line.isBlank && !line.isValid {
            if line.trimmedName.isEmpty { return "Line \(i + 1): choose a product or enter a name." }
            if line.quantity <= 0 { return "Line \(i + 1): quantity must be more than 0." }
            return "Line \(i + 1): unit price must be 0 or more."
        }
        return nil
    }
}

enum SparkDealBody {
    /// Merge the Spark deal fields into a deal-create body: the customer account,
    /// originating lead, primary contact, quotation number and the product lines.
    /// Blank values are left out. With lines, `amount` is set to their total (the
    /// backend recomputes it from `items` either way).
    static func apply(
        to body: inout [String: Any],
        accountId: String?,
        leadId: String?,
        primaryContactId: String? = nil,
        quotationNo: String,
        lines: [DealLineDraft]
    ) {
        if let accountId, !accountId.isEmpty { body["account_id"] = accountId }
        if let leadId, !leadId.isEmpty { body["lead_id"] = leadId }
        if let primaryContactId, !primaryContactId.isEmpty { body["primary_contact_id"] = primaryContactId }
        let quote = quotationNo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !quote.isEmpty { body["quotation_no"] = quote }
        let items = DealLines.payload(lines)
        if !items.isEmpty {
            body["items"] = items
            body["amount"] = DealLines.grandTotal(lines)
        }
    }
}

// MARK: - Activity bodies

extension Activity {
    /// This activity's Spark extras as they came from the server: assignees (primary
    /// first), product ids and the linked form serial.
    var sparkExtras: SparkActivityExtras {
        var people = (assignees ?? []).map { $0.id }
        // An activity assigned before the assignee list existed carries only `assigned_to` (the primary).
        // Treat that person as the one assignee so the edit form shows them and removing them clears it.
        if people.isEmpty, let primary = assignedTo, !primary.isEmpty { people = [primary] }
        let productIdList = productIds ?? (products ?? []).map { $0.id }
        return SparkActivityExtras(
            assigneeIds: SparkJourney.deduped(people),
            productIds: SparkJourney.deduped(productIdList),
            formSerial: formRefNo ?? "",
            outcome: outcome ?? ""
        )
    }

    /// id -> name for every assignee / product on the row, to seed the pickers' labels.
    var sparkNames: [String: String] {
        var out: [String: String] = [:]
        for ref in (assignees ?? []) + (products ?? []) where !ref.id.isEmpty && !ref.name.isEmpty {
            out[ref.id] = ref.name
        }
        if let primary = assignedTo, !primary.isEmpty, out[primary] == nil,
           let n = assignedToName, !n.isEmpty {
            out[primary] = n
        }
        return out
    }
}

/// Request bodies for the Spark activity flows. The Spark extras themselves are merged
/// by `CRMService.createActivity(_:spark:)` / `updateActivity(id:body:spark:previous:)`.
enum SparkActivityBody {
    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// POST body from the composer. `scheduled` creates an open activity due at `when`
    /// (what the reminder cron scans for); logging stamps a completed one, except a
    /// task which only gets its due date. `links` are parent ids such as
    /// `["account_id": …]`; blank values are skipped.
    static func createBody(_ r: ActivityComposeResult, scheduled: Bool, links: [String: String]) -> [String: Any] {
        var body: [String: Any] = [
            "type": r.type,
            "subject": r.subject.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        let desc = r.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty { body["description"] = desc }
        if let imageUrl = r.imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
        if scheduled {
            body["status"] = "open"
            body["due_at"] = iso(r.when)
        } else if r.type != "task" {
            body["completed_at"] = iso(r.when)
            body["status"] = "completed"
        } else {
            body["due_at"] = iso(r.when)
        }
        if !r.customFields.isEmpty { body["custom_fields"] = r.customFields }
        for (key, value) in links where !value.isEmpty { body[key] = value }
        return body
    }

    /// PATCH body for an edit. Unlike the generic edit it never flips an open
    /// activity to completed: a completed row keeps its status and gets the new
    /// `completed_at`; any other row gets the new `due_at`.
    static func updateBody(_ r: ActivityComposeResult, existing: Activity) -> [String: Any] {
        var body: [String: Any] = [
            "type": r.type,
            "subject": r.subject.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        // The composer is seeded with the row's remarks; blank + had remarks = cleared on purpose.
        let desc = r.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty {
            body["description"] = desc
        } else if existing.remarksText != nil {
            body["description"] = NSNull()
        }
        if let imageUrl = r.imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
        if r.whenEdited {
            if existing.effectiveStatus == "completed" {
                body["completed_at"] = iso(r.when)
            } else {
                body["due_at"] = iso(r.when)
            }
        }
        if !r.customFields.isEmpty { body["custom_fields"] = r.customFields }
        for (key, value) in r.linkPatch { body[key] = value }
        return body
    }
}
