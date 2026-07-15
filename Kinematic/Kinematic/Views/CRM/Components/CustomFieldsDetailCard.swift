import SwiftUI

/// Read-only card that surfaces admin-defined custom fields on the
/// lead / deal detail screen. The lead detail page previously had no
/// generic custom-field view at all — values entered on the form (DOB,
/// monthly volume, gender, lookup picks, formula results) were stored
/// but never displayed back. This card iterates the field defs for the
/// entity, looks up each value in `customFields`, and renders one
/// labelled row per non-empty entry.
///
/// Product-line keys are skipped — LeadProductsCard / DealProductsCard
/// already render them in their own multi-column tables.
struct CustomFieldsDetailCard: View {
    let entity: String                // "lead" | "deal" | "contact" | "account"
    let customFields: [String: AnyCodable]?
    /// Optional client_id so the def lookup honours per-client scoping
    /// (today the iOS service hits the universal endpoint, which is
    /// already filtered server-side by client_id — passed through here
    /// for forward-compat).
    var clientId: String? = nil

    @State private var defs: [CRMCustomFieldDef] = []
    @State private var loading: Bool = true
    /// Per-target `id → label` cache for lookup fields. Populated once
    /// the defs land + we see which UUIDs the row stores. Previously the
    /// card rendered lookup values as raw UUIDs ("Block: 8fefca98-…")
    /// which read as garbage on the detail screen.
    @State private var lookupLabels: [String: String] = [:]

    private static let productLineKeys: Set<String> = [
        "product_interested", "quantity", "measuring_unit", "estimated_amount", "product_lines",
    ]

    var body: some View {
        // Drop the card entirely when there's nothing to show — avoids a
        // blank "Additional details" header on leads with no custom data.
        let rows = visibleRows()
        if !loading && rows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // Eyebrow header — matches the sectioned card headers on
                // the lead / deal detail screens.
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11))
                        .foregroundColor(Brand.red)
                    Text("ADDITIONAL DETAILS")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1)
                        .foregroundColor(Brand.red)
                    Spacer()
                }
                if loading {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading…").font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    ForEach(rows, id: \.key) { row in
                        HStack(alignment: .top) {
                            Text(row.label)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(row.display)
                                .font(.subheadline)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .task { await load() }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        let all = await CRMService.shared.listCustomFields()
        defs = all
            .filter { $0.entityType == entity }
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        await loadLookupLabels()
    }

    /// One `/lookup/search` per unique target_table referenced by the
    /// loaded defs that has at least one UUID-only value in the row.
    /// Resolved labels populate `lookupLabels` and re-render the card.
    @MainActor
    private func loadLookupLabels() async {
        guard let raw = customFields, !raw.isEmpty, !defs.isEmpty else { return }
        var targets = Set<String>()
        for d in defs where d.fieldType == "lookup" {
            guard let table = d.targetTable, !table.isEmpty else { continue }
            guard let any = raw[d.fieldKey]?.raw?.any else { continue }
            // New shape `{ id, label }` already carries a label — skip
            // those. Only refetch when we'd otherwise show a UUID.
            if let obj = any as? [String: Any] {
                if (obj["label"] as? String)?.isEmpty == false { continue }
                if (obj["id"] as? String)?.isEmpty == false { targets.insert(table) }
            } else if let s = any as? String, !s.isEmpty {
                targets.insert(table)
            }
        }
        var next: [String: String] = [:]
        for target in targets {
            let opts = await CRMService.shared.lookupSearch(target: target, q: nil, filter: nil)
            for o in opts { next["\(target):\(o.id)"] = o.label }
        }
        if !next.isEmpty { lookupLabels = next }
    }

    private struct Row {
        let key: String
        let label: String
        let display: String
    }

    /// Walk the loaded defs and pull a display string for each one that
    /// has a populated value. Format depends on type:
    ///   boolean   → Yes / No
    ///   number    → grouped thousands
    ///   currency  → ₹X,XXX
    ///   date      → 13 Jun 2026
    ///   multiselect → comma-joined
    ///   lookup    → raw id (label hydration is a future iteration —
    ///               keeps the card cheap, no per-row API calls)
    ///   default   → raw string
    private func visibleRows() -> [Row] {
        guard let raw = customFields, !raw.isEmpty else { return [] }
        var out: [Row] = []
        for d in defs {
            if Self.productLineKeys.contains(d.fieldKey) { continue }
            guard let any = raw[d.fieldKey]?.raw?.any else { continue }
            let display: String?
            if d.fieldType == "lookup" {
                display = resolveLookup(any, target: d.targetTable)
            } else {
                display = formatValue(any, type: d.fieldType)
            }
            guard let display, !display.isEmpty else { continue }
            out.append(Row(key: d.fieldKey, label: d.label, display: display))
        }
        return out
    }

    /// Map a lookup value (raw UUID string OR `{ id, label }` dict) to
    /// the display label via the cached lookup map. Falls back to the
    /// short UUID so a cache miss is still recognisable instead of a
    /// 36-char string.
    private func resolveLookup(_ v: Any, target: String?) -> String? {
        if let dict = v as? [String: Any] {
            if let label = dict["label"] as? String, !label.isEmpty { return label }
            if let id = dict["id"] as? String, !id.isEmpty {
                if let t = target, let resolved = lookupLabels["\(t):\(id)"] { return resolved }
                return String(id.prefix(8))
            }
            return nil
        }
        if let id = v as? String, !id.isEmpty {
            if let t = target, let resolved = lookupLabels["\(t):\(id)"] { return resolved }
            return String(id.prefix(8))
        }
        return String(describing: v)
    }

    private func formatValue(_ v: Any, type: String) -> String? {
        switch type {
        case "boolean":
            if let b = v as? Bool { return b ? "Yes" : "No" }
            if let s = v as? String { return s.lowercased() == "true" ? "Yes" : "No" }
            return nil
        case "number":
            if let n = v as? Double { return Self.numberFmt.string(from: NSNumber(value: n)) }
            if let n = v as? Int { return Self.numberFmt.string(from: NSNumber(value: n)) }
            if let s = v as? String, let n = Double(s) { return Self.numberFmt.string(from: NSNumber(value: n)) }
            return nil
        case "currency":
            if let n = v as? Double { return "₹" + (Self.intFmt.string(from: NSNumber(value: n)) ?? "0") }
            if let n = v as? Int { return "₹" + (Self.intFmt.string(from: NSNumber(value: n)) ?? "0") }
            if let s = v as? String, let n = Double(s) { return "₹" + (Self.intFmt.string(from: NSNumber(value: n)) ?? "0") }
            return nil
        case "date":
            if let s = v as? String, let d = Self.parseIso(s) {
                return Self.displayDate.string(from: d)
            }
            return v as? String
        case "datetime":
            if let s = v as? String, let d = Self.parseIso(s) {
                return Self.displayDateTime.string(from: d)
            }
            return v as? String
        case "multiselect":
            if let arr = v as? [Any] { return arr.map { String(describing: $0) }.joined(separator: ", ") }
            return v as? String
        case "formula":
            return String(describing: v)
        default:
            if let s = v as? String { return s }
            return String(describing: v)
        }
    }

    // MARK: – Formatters

    private static let numberFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }()
    private static let intFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()
    private static let displayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()
    private static let displayDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy · h:mm a"
        return f
    }()
    private static let isoDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let isoDateTimeFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static func parseIso(_ s: String) -> Date? {
        if let d = isoDateFmt.date(from: String(s.prefix(10))) { return d }
        return isoDateTimeFmt.date(from: s)
    }
}
