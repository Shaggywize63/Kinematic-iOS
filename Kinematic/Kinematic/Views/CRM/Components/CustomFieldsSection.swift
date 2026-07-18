import SwiftUI
import Combine

/// Loads + holds the values for an entity's custom fields, scoped to the
/// signed-in user's org role. Owned by the create form; `jsonValues` is merged
/// into the create body under `custom_fields`.
@MainActor
final class CustomFieldsModel: ObservableObject {
    @Published var defs: [CRMCustomFieldDef] = []
    // Per-type value stores keyed by field_key.
    @Published var text: [String: String] = [:]
    @Published var bool: [String: Bool] = [:]
    @Published var multi: [String: Set<String>] = [:]
    // Lookup-field options, keyed by field_key. Populated after load() when
    // any def has fieldType == "lookup". One entry per row holds the id
    // (used in `text` as the stored value) and a human label for display.
    @Published var lookupOptions: [String: [(id: String, label: String)]] = [:]

    func load(entity: String) async {
        let all = await CRMService.shared.listCustomFields()
        let roleId = await CRMService.shared.myOrgRoleId()
        defs = all
            .filter { d in
                guard d.entityType == entity else { return false }
                // The four product-line keys are rendered by the dedicated
                // ProductLinesSection card on the lead form, so drop them
                // here to avoid double-rendering.
                let productLineKeys: Set<String> = [
                    "product_interested", "quantity", "measuring_unit", "estimated_amount",
                ]
                if entity == "lead", productLineKeys.contains(d.fieldKey) { return false }
                // No roles tagged = universal; otherwise must include my role.
                guard let roles = d.orgRoleIds, !roles.isEmpty else { return true }
                guard let rid = roleId else { return false }
                return roles.contains(rid)
            }
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        // Fetch lookup target rows so each lookup field renders as a Picker
        // instead of a free-text input. Uses the generic /lookup/search
        // endpoint so any admin-configured target_table works (not just
        // crm_products — matches the web behaviour).
        for d in defs where d.fieldType == "lookup" {
            guard let target = d.targetTable, !target.isEmpty else { continue }
            let filterJson: String? = {
                guard let clauses = d.lookupFilter, !clauses.isEmpty else { return nil }
                let encoder = JSONEncoder()
                guard let data = try? encoder.encode(clauses) else { return nil }
                return String(data: data, encoding: .utf8)
            }()
            let opts = await CRMService.shared.lookupSearch(target: target, q: nil, filter: filterJson)
            if !opts.isEmpty {
                lookupOptions[d.fieldKey] = opts.map { ($0.id, $0.label) }
            }
        }
    }

    /// Seed the per-type stores from a record's existing `custom_fields`
    /// blob so the Edit screen shows the current values. Idempotent —
    /// keys not present in `defs` are ignored, and missing values default
    /// to empty/false so the form is always renderable.
    func hydrate(from raw: [String: AnyCodable]?) {
        guard let raw else { return }
        for d in defs {
            let stored = raw[d.fieldKey]?.value
            switch d.fieldType {
            case "boolean":
                if let s = stored?.lowercased() {
                    bool[d.fieldKey] = (s == "true" || s == "1" || s == "yes")
                }
            case "multiselect":
                // Stored as JSON-encoded array string by AnyCodable. We
                // accept both a CSV fallback and JSON for forward-compat.
                if let s = stored {
                    let trimmed = s.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("["),
                       let data = trimmed.data(using: .utf8),
                       let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                        multi[d.fieldKey] = Set(arr)
                    } else if !trimmed.isEmpty {
                        multi[d.fieldKey] = Set(trimmed.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
                    }
                }
            default:
                if let s = stored { text[d.fieldKey] = s }
            }
        }
    }

    /// Plain JSON-serialisable values (String / Double / Bool / [String]) for
    /// the create body. Empty entries are skipped. Formula fields are
    /// skipped entirely — the backend recomputes + stamps them on save,
    /// so writing a stale client value would only race the server.
    var jsonValues: [String: Any] {
        var out: [String: Any] = [:]
        for d in defs {
            switch d.fieldType {
            case "boolean":
                if let b = bool[d.fieldKey] { out[d.fieldKey] = b }
            case "multiselect":
                if let s = multi[d.fieldKey], !s.isEmpty { out[d.fieldKey] = Array(s) }
            case "number", "currency":
                if let t = text[d.fieldKey], !t.isEmpty, let n = Double(t) { out[d.fieldKey] = n }
            case "formula":
                continue
            default:
                if let t = text[d.fieldKey], !t.isEmpty { out[d.fieldKey] = t }
            }
        }
        return out
    }
}

/// Renders the entity's custom fields as a Form section. Pass the same
/// `CustomFieldsModel` the parent reads `jsonValues` from at submit.
struct CustomFieldsSection: View {
    @ObservedObject var model: CustomFieldsModel

    var body: some View {
        if !model.defs.isEmpty {
            Section("Additional details") {
                ForEach(model.defs) { d in
                    row(d)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ d: CRMCustomFieldDef) -> some View {
        switch d.fieldType {
        case "boolean":
            Toggle(d.label, isOn: Binding(
                get: { model.bool[d.fieldKey] ?? false },
                set: { model.bool[d.fieldKey] = $0 }))
        case "select", "radio":
            Picker(d.label, selection: Binding(
                get: { model.text[d.fieldKey] ?? "" },
                set: { model.text[d.fieldKey] = $0 })) {
                    Text("—").tag("")
                    ForEach(d.options ?? [], id: \.self) { Text($0).tag($0) }
                }
        case "lookup":
            // Live-search picker — the picker sheet calls /lookup/search
            // on every keystroke so tenants with 200+ rows in the
            // target table (People Directory dealers / engineers, etc.)
            // can find what they want instead of being capped by the
            // initial 50-row fetch a plain Picker shows.
            LookupSearchPickerRow(
                def: d,
                value: model.text[d.fieldKey] ?? "",
                seedOptions: model.lookupOptions[d.fieldKey] ?? [],
                onPick: { id, label in
                    model.text[d.fieldKey] = id
                    // Cache the label so the row keeps displaying it
                    // after the sheet dismisses even if the seed list
                    // didn't contain this row.
                    var existing = model.lookupOptions[d.fieldKey] ?? []
                    if !existing.contains(where: { $0.id == id }) {
                        existing.append((id: id, label: label))
                        model.lookupOptions[d.fieldKey] = existing
                    }
                }
            )
        case "multiselect":
            VStack(alignment: .leading, spacing: 6) {
                Text(d.label).font(.caption).foregroundColor(.secondary)
                ForEach(d.options ?? [], id: \.self) { opt in
                    Toggle(opt, isOn: Binding(
                        get: { model.multi[d.fieldKey]?.contains(opt) ?? false },
                        set: { on in
                            var s = model.multi[d.fieldKey] ?? []
                            if on { s.insert(opt) } else { s.remove(opt) }
                            model.multi[d.fieldKey] = s
                        }))
                }
            }
        case "formula":
            // Backend evaluates the formula and stamps the result back
            // into custom_fields on save. We show the most recent value
            // (from hydrate()) read-only so the rep can preview it.
            HStack {
                Text(d.label)
                Spacer()
                let stored = model.text[d.fieldKey] ?? ""
                Text(stored.isEmpty ? "—" : stored)
                    .foregroundColor(.secondary)
            }
        case "image":
            // Photo/Camera field — capture or pick per the admin's config
            // tokens in def.options; stores the uploaded URL in model.text.
            ImageCustomFieldRow(def: d, model: model)

        case "date":
            // Render a native DatePicker so reps don't have to type
            // YYYY-MM-DD by hand. Stored value stays a plain string in
            // the same format the backend / web write, so this round-trips
            // through hydrate(from:) without a schema change.
            DatePicker(
                d.label,
                selection: Binding(
                    get: { Self.parseISODate(model.text[d.fieldKey]) ?? Date() },
                    set: { newDate in model.text[d.fieldKey] = Self.formatISODate(newDate) }
                ),
                displayedComponents: .date
            )
        case "datetime":
            DatePicker(
                d.label,
                selection: Binding(
                    get: { Self.parseISODateTime(model.text[d.fieldKey]) ?? Date() },
                    set: { newDate in model.text[d.fieldKey] = Self.formatISODateTime(newDate) }
                )
            )
        default:
            // text / longtext / number / currency / url / email / phone
            HStack {
                Text(d.label)
                Spacer()
                TextField(d.fieldType == "number" || d.fieldType == "currency" ? "0" : "",
                          text: Binding(get: { model.text[d.fieldKey] ?? "" },
                                        set: { model.text[d.fieldKey] = $0 }))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboard(for: d.fieldType))
            }
        }
    }

    // Date helpers — kept static so the row builder can call them from
    // its Binding closures without capturing self. Format YYYY-MM-DD
    // matches what the backend stores in custom_fields for date types
    // (and what the web DatePicker writes), so round-tripping doesn't
    // need a server-side migration.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let dateTimeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    fileprivate static func parseISODate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        // Tolerate full ISO datetimes too — the backend sometimes stores
        // a timestamp where a date is expected.
        if let d = dateFormatter.date(from: String(s.prefix(10))) { return d }
        return dateTimeFormatter.date(from: s)
    }
    fileprivate static func formatISODate(_ d: Date) -> String { dateFormatter.string(from: d) }
    fileprivate static func parseISODateTime(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = dateTimeFormatter.date(from: s) { return d }
        return dateFormatter.date(from: String(s.prefix(10)))
    }
    fileprivate static func formatISODateTime(_ d: Date) -> String { dateTimeFormatter.string(from: d) }

    private func keyboard(for type: String) -> UIKeyboardType {
        switch type {
        case "number", "currency": return .decimalPad
        case "phone": return .phonePad
        case "email": return .emailAddress
        case "url": return .URL
        default: return .default
        }
    }
}

// MARK: - Lookup search picker

/// One row of the form: shows the currently picked label (or "—") and opens
/// a search sheet on tap. The sheet calls /lookup/search live so tenants
/// with hundreds of dealers / engineers / blocks aren't capped by the
/// initial 50-row fetch a plain Picker shows.
private struct LookupSearchPickerRow: View {
    let def: CRMCustomFieldDef
    let value: String
    let seedOptions: [(id: String, label: String)]
    let onPick: (_ id: String, _ label: String) -> Void

    @State private var sheetOpen = false

    private var displayLabel: String {
        if value.isEmpty { return "—" }
        return seedOptions.first(where: { $0.id == value })?.label ?? value
    }

    var body: some View {
        Button {
            sheetOpen = true
        } label: {
            HStack {
                Text(def.label)
                    .foregroundColor(.primary)
                Spacer()
                Text(displayLabel)
                    .foregroundColor(value.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $sheetOpen) {
            LookupSearchSheet(
                def: def,
                onPick: { id, label in
                    onPick(id, label)
                    sheetOpen = false
                },
                onClear: {
                    onPick("", "")
                    sheetOpen = false
                }
            )
        }
    }
}

/// Bottom sheet that lists options for a lookup field and re-fetches on
/// every search keystroke. Empty query returns the first 500 rows (server
/// cap); typing narrows server-side via the curated `search` columns the
/// backend exposes for the target table.
private struct LookupSearchSheet: View {
    let def: CRMCustomFieldDef
    let onPick: (_ id: String, _ label: String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var results: [CRMLookupOption] = []
    @State private var loading: Bool = false

    private var filterJson: String? {
        guard let clauses = def.lookupFilter, !clauses.isEmpty,
              let data = try? JSONEncoder().encode(clauses),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider()
                if loading && results.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text(query.isEmpty ? "No options." : "No matches for \"\(query)\".")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach(results) { opt in
                            Button {
                                onPick(opt.id, opt.label)
                            } label: {
                                Text(opt.label)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(def.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) { onClear() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await refetch() }
            .onChange(of: query) { _, _ in
                Task { await refetch() }
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Search…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func refetch() async {
        guard let target = def.targetTable, !target.isEmpty else { return }
        loading = true
        defer { loading = false }
        let opts = await CRMService.shared.lookupSearch(
            target: target,
            q: query.isEmpty ? nil : query,
            filter: filterJson
        )
        results = opts
    }
}
