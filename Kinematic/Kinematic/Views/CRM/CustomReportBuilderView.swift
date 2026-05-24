//
//  CustomReportBuilderView.swift
//  Kinematic CRM
//
//  Mobile-friendly equivalent of the web's /dashboard/crm/reports/builder.
//  Lets a user pick an entity, choose built-in + admin-defined custom fields,
//  add filters, fetch the list client-side, then download the result as CSV.
//
//  The filter engine + CSV writer run entirely on-device against the entity
//  list endpoints (CRMService.shared.listLeads/listContacts/...). The web
//  version does the same — server-side filter operators aren't part of the
//  list endpoints' contract.
//

import SwiftUI

// MARK: - Entity / field model

/// Builder-level entity selector. The raw values double as the singular
/// `entity_type` we pass to /api/v1/crm/custom-fields.
enum BuilderEntity: String, CaseIterable, Identifiable {
    case leads      = "lead"
    case contacts   = "contact"
    case accounts   = "account"
    case deals      = "deal"
    case activities = "activity"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .leads:      return "Leads"
        case .contacts:   return "Contacts"
        case .accounts:   return "Accounts"
        case .deals:      return "Deals"
        case .activities: return "Activities"
        }
    }
}

/// One column the user can pick. `key` is the JSON / row key we look up.
/// `kind` controls which operators are available in the filter row.
struct BuilderField: Identifiable, Hashable {
    enum Kind { case text, number, date, boolean, `enum` }

    let key: String
    let label: String
    let kind: Kind
    let isCustom: Bool
    let options: [String]?

    var id: String { key }
}

/// Filter operator. The set is intentionally small — matches the web
/// builder's vocabulary so users moving between platforms aren't surprised.
enum FilterOp: String, CaseIterable, Identifiable {
    case equals      = "equals"
    case notEquals   = "not_equals"
    case contains    = "contains"
    case startsWith  = "starts_with"
    case greaterThan = "greater_than"
    case lessThan    = "less_than"
    case isEmpty     = "is_empty"
    case isNotEmpty  = "is_not_empty"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .equals:      return "equals"
        case .notEquals:   return "not equals"
        case .contains:    return "contains"
        case .startsWith:  return "starts with"
        case .greaterThan: return "greater than"
        case .lessThan:    return "less than"
        case .isEmpty:     return "is empty"
        case .isNotEmpty:  return "is not empty"
        }
    }

    /// Operators that don't need a value field.
    var needsValue: Bool {
        switch self {
        case .isEmpty, .isNotEmpty: return false
        default: return true
        }
    }
}

/// One filter row in the UI. Value is stored as a string and coerced at
/// match-time so we don't have to juggle Any across the SwiftUI hierarchy.
struct FilterRow: Identifiable, Hashable {
    let id = UUID()
    var fieldKey: String
    var op: FilterOp
    var value: String
}

// MARK: - Built-in fields per entity

/// Hardcoded built-in fields, kept in sync with the web builder's spec.
private enum BuiltInFields {
    static func forEntity(_ entity: BuilderEntity) -> [BuilderField] {
        switch entity {
        case .leads:
            return [
                f("first_name",  "First Name"),
                f("last_name",   "Last Name"),
                f("email",       "Email"),
                f("phone",       "Phone"),
                f("company",     "Company"),
                f("title",       "Title"),
                f("industry",    "Industry"),
                f("status",      "Status"),
                f("score",       "Score", kind: .number),
                f("score_grade", "Score Grade"),
                f("source_name", "Source"),
                f("owner_name",  "Owner"),
                f("city",        "City"),
                f("state",       "State"),
                f("country",     "Country"),
                f("is_b2c",      "Is B2C", kind: .boolean),
                f("created_at",  "Created At", kind: .date),
            ]
        case .contacts:
            return [
                f("first_name",      "First Name"),
                f("last_name",       "Last Name"),
                f("email",           "Email"),
                f("phone",           "Phone"),
                f("title",           "Title"),
                f("department",      "Department"),
                f("account_name",    "Account"),
                f("owner_name",      "Owner"),
                f("city",            "City"),
                f("state",           "State"),
                f("country",         "Country"),
                f("do_not_contact",  "Do Not Contact", kind: .boolean),
                f("email_opt_out",   "Email Opt-Out",  kind: .boolean),
                f("created_at",      "Created At", kind: .date),
            ]
        case .accounts:
            return [
                f("name",           "Name"),
                f("domain",         "Domain"),
                f("industry",       "Industry"),
                f("annual_revenue", "Annual Revenue", kind: .number),
                f("phone",          "Phone"),
                f("email",          "Email"),
                f("city",           "City"),
                f("state",          "State"),
                f("country",        "Country"),
                f("owner_name",     "Owner"),
                f("created_at",     "Created At", kind: .date),
            ]
        case .deals:
            return [
                f("name",                "Name"),
                f("amount",              "Amount", kind: .number),
                f("currency",            "Currency"),
                f("status",              "Status"),
                f("stage_name",          "Stage"),
                f("pipeline_name",       "Pipeline"),
                f("probability",         "Probability", kind: .number),
                f("expected_close_date", "Expected Close", kind: .date),
                f("actual_close_date",   "Actual Close",   kind: .date),
                f("account_name",        "Account"),
                f("owner_name",          "Owner"),
                f("lost_reason",         "Lost Reason"),
                f("created_at",          "Created At", kind: .date),
            ]
        case .activities:
            return [
                f("type",         "Type"),
                f("subject",      "Subject"),
                f("status",       "Status"),
                f("priority",     "Priority"),
                f("due_at",       "Due At",       kind: .date),
                f("completed_at", "Completed At", kind: .date),
                f("owner_name",   "Owner"),
                f("created_at",   "Created At",   kind: .date),
            ]
        }
    }

    private static func f(_ key: String, _ label: String, kind: BuilderField.Kind = .text) -> BuilderField {
        BuilderField(key: key, label: label, kind: kind, isCustom: false, options: nil)
    }
}

/// Translate a CRM custom-field type → builder field kind. The web does the
/// same mapping in `mapCustomFieldType`.
private func mapCustomFieldKind(_ type: String) -> BuilderField.Kind {
    switch type {
    case "number", "currency":             return .number
    case "date", "datetime":               return .date
    case "boolean":                        return .boolean
    case "select", "multiselect", "radio": return .enum
    default:                               return .text
    }
}

// MARK: - View

struct CustomReportBuilderView: View {
    @State private var entity: BuilderEntity = .leads
    @State private var customFieldsCache: [BuilderEntity: [CRMCustomField]] = [:]
    @State private var selectedKeys: Set<String> = []
    @State private var filters: [FilterRow] = []

    @State private var isLoadingCustomFields = false
    @State private var isRunning = false
    @State private var errorMessage: String?

    /// Resolved rows from the latest "Run report" press. Stored as
    /// `[String: String]` because the UI doesn't care about original JSON
    /// types — display + CSV both need strings.
    @State private var results: [[String: String]] = []
    @State private var resultsEntity: BuilderEntity = .leads
    @State private var resultsFields: [BuilderField] = []
    @State private var shareItem: ShareItem?
    @State private var showResults = false

    var body: some View {
        Form {
            Section {
                Picker("Entity", selection: $entity) {
                    ForEach(BuilderEntity.allCases) { e in
                        Text(e.label).tag(e)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: entity) { _, newValue in
                    selectedKeys.removeAll()
                    filters.removeAll()
                    Task { await loadCustomFields(for: newValue) }
                }
            } header: {
                Text("Entity")
            } footer: {
                Text("Pick what you want to report on. Filters and fields reset when you change entity.")
            }

            Section("Fields") {
                if isLoadingCustomFields {
                    HStack { ProgressView(); Text("Loading custom fields...").foregroundColor(.secondary) }
                }
                ForEach(allFields(for: entity), id: \.key) { field in
                    Button { toggle(field) } label: {
                        HStack {
                            Image(systemName: selectedKeys.contains(field.key) ? "checkmark.square.fill" : "square")
                                .foregroundColor(selectedKeys.contains(field.key) ? .indigo : .gray)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(field.label)
                                    .foregroundColor(Color(uiColor: .label))
                                if field.isCustom {
                                    Text("Custom").font(.caption2).foregroundColor(.indigo)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                ForEach(filters.indices, id: \.self) { idx in
                    FilterRowView(
                        row: $filters[idx],
                        availableFields: allFields(for: entity),
                        onDelete: { filters.remove(at: idx) }
                    )
                }
                Button {
                    addFilterRow()
                } label: {
                    Label("Add filter", systemImage: "plus.circle.fill")
                }
                .disabled(allFields(for: entity).isEmpty)
            } header: {
                Text("Filters")
            } footer: {
                Text("Filters are AND'ed. Empty value with 'equals' matches blank cells.")
            }

            Section {
                Button {
                    Task { await runReport() }
                } label: {
                    HStack {
                        if isRunning { ProgressView() }
                        Text(isRunning ? "Running..." : "Run Report")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "play.fill")
                    }
                    .foregroundColor(canRun ? .white : .gray)
                    .padding(.vertical, 6)
                }
                .listRowBackground(canRun ? Color.indigo : Color(uiColor: .secondarySystemBackground))
                .disabled(!canRun || isRunning)

                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Report Builder")
        .navigationDestination(isPresented: $showResults) {
            ReportResultsView(
                entity: resultsEntity,
                fields: resultsFields,
                rows: results,
                onDownload: { exportResultsCSV() }
            )
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.url])
        }
        .task { await loadCustomFields(for: entity) }
    }

    // MARK: Derived

    private var canRun: Bool { !selectedKeys.isEmpty }

    private func allFields(for entity: BuilderEntity) -> [BuilderField] {
        let builtIns = BuiltInFields.forEntity(entity)
        let custom = (customFieldsCache[entity] ?? []).map { def -> BuilderField in
            BuilderField(
                key: def.fieldKey,
                label: def.label,
                kind: mapCustomFieldKind(def.fieldType),
                isCustom: true,
                options: def.options
            )
        }
        return builtIns + custom
    }

    // MARK: Mutations

    private func toggle(_ field: BuilderField) {
        if selectedKeys.contains(field.key) {
            selectedKeys.remove(field.key)
        } else {
            selectedKeys.insert(field.key)
        }
    }

    private func addFilterRow() {
        guard let first = allFields(for: entity).first else { return }
        filters.append(FilterRow(fieldKey: first.key, op: .equals, value: ""))
    }

    // MARK: Network

    private func loadCustomFields(for entity: BuilderEntity) async {
        if customFieldsCache[entity] != nil { return }
        await MainActor.run { isLoadingCustomFields = true }
        defer { Task { @MainActor in isLoadingCustomFields = false } }
        do {
            let defs = try await CRMService.shared.listCustomFields(entityType: entity.rawValue)
            await MainActor.run { customFieldsCache[entity] = defs }
        } catch {
            // Soft-fail — built-in fields still work; just no custom columns.
            await MainActor.run { customFieldsCache[entity] = [] }
        }
    }

    // MARK: Run / filter / project

    private func runReport() async {
        await MainActor.run { isRunning = true; errorMessage = nil }
        defer { Task { @MainActor in isRunning = false } }

        let selectedFields = allFields(for: entity).filter { selectedKeys.contains($0.key) }
        do {
            let rows = try await fetchRows(for: entity)
            let filtered = rows.filter { row in filters.allSatisfy { rowMatchesFilter(row, $0) } }
            let projected = filtered.map { project($0, fields: selectedFields) }
            await MainActor.run {
                self.results = projected
                self.resultsEntity = entity
                self.resultsFields = selectedFields
                self.showResults = true
            }
        } catch {
            await MainActor.run { errorMessage = "Failed: \(error.localizedDescription)" }
        }
    }

    /// Fetch entity rows and return them as `[String: Any]` so the filter +
    /// projection layer can treat them uniformly. We round-trip through
    /// JSONEncoder → JSONSerialization which gives us the snake-case keys
    /// the field specs reference.
    private func fetchRows(for entity: BuilderEntity) async throws -> [[String: Any]] {
        let encoder = JSONEncoder()
        switch entity {
        case .leads:
            let list = try await CRMService.shared.listLeads()
            return try list.map { try Self.toDict($0, encoder: encoder) }
        case .contacts:
            let list = try await CRMService.shared.listContacts()
            return try list.map { try Self.toDict($0, encoder: encoder) }
        case .accounts:
            let list = try await CRMService.shared.listAccounts()
            return try list.map { try Self.toDict($0, encoder: encoder) }
        case .deals:
            let list = try await CRMService.shared.listDeals()
            return try list.map { try Self.toDict($0, encoder: encoder) }
        case .activities:
            // Empty filters = all activities the API exposes for the user.
            let list = try await CRMService.shared.listActivities()
            return try list.map { try Self.toDict($0, encoder: encoder) }
        }
    }

    private static func toDict<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> [String: Any] {
        let data = try encoder.encode(value)
        if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return [:]
    }

    /// Pull a value out of a row by key. Custom fields live under
    /// `custom_fields[<key>]`. Built-in fields are top-level. We return a
    /// String so filters + CSV agree on the comparison shape.
    private func valueFor(key: String, row: [String: Any], isCustom: Bool) -> String {
        if isCustom {
            if let cf = row["custom_fields"] as? [String: Any], let raw = cf[key] {
                return stringify(raw)
            }
            return ""
        }
        if let raw = row[key] { return stringify(raw) }
        return ""
    }

    private func stringify(_ raw: Any) -> String {
        if raw is NSNull { return "" }
        if let s = raw as? String { return s }
        if let b = raw as? Bool { return b ? "true" : "false" }
        if let n = raw as? NSNumber {
            // NSNumber backs both Int and Double; trim trailing .0 on whole numbers.
            let d = n.doubleValue
            if d.rounded() == d && abs(d) < 1e15 { return String(Int64(d)) }
            return String(d)
        }
        if let arr = raw as? [Any] { return arr.map { stringify($0) }.joined(separator: "; ") }
        return String(describing: raw)
    }

    private func project(_ row: [String: Any], fields: [BuilderField]) -> [String: String] {
        var out: [String: String] = [:]
        for f in fields {
            out[f.key] = valueFor(key: f.key, row: row, isCustom: f.isCustom)
        }
        return out
    }

    /// Apply a single filter row to a fetched record.
    private func rowMatchesFilter(_ row: [String: Any], _ filter: FilterRow) -> Bool {
        let field = allFields(for: entity).first(where: { $0.key == filter.fieldKey })
        let isCustom = field?.isCustom ?? false
        let lhs = valueFor(key: filter.fieldKey, row: row, isCustom: isCustom)

        switch filter.op {
        case .isEmpty:    return lhs.isEmpty
        case .isNotEmpty: return !lhs.isEmpty
        case .equals:     return lhs.caseInsensitiveCompare(filter.value) == .orderedSame
        case .notEquals:  return lhs.caseInsensitiveCompare(filter.value) != .orderedSame
        case .contains:   return lhs.lowercased().contains(filter.value.lowercased())
        case .startsWith: return lhs.lowercased().hasPrefix(filter.value.lowercased())
        case .greaterThan, .lessThan:
            // Numeric comparison when both sides parse, else lexical.
            if let l = Double(lhs), let r = Double(filter.value) {
                return filter.op == .greaterThan ? l > r : l < r
            }
            let cmp = lhs.compare(filter.value)
            return filter.op == .greaterThan ? cmp == .orderedDescending : cmp == .orderedAscending
        }
    }

    // MARK: CSV export

    private func exportResultsCSV() {
        let csv = buildCSV(fields: resultsFields, rows: results)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let filename = "report-\(resultsEntity.rawValue)-\(fmt.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            shareItem = ShareItem(url: url)
        } catch {
            errorMessage = "Could not write CSV: \(error.localizedDescription)"
        }
    }

    private func buildCSV(fields: [BuilderField], rows: [[String: String]]) -> String {
        var lines: [String] = []
        lines.append(fields.map { escape($0.label) }.joined(separator: ","))
        for row in rows {
            lines.append(fields.map { escape(row[$0.key] ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func escape(_ s: String) -> String {
        let needsQuoting = s.contains(",") || s.contains("\"") || s.contains("\n")
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuoting ? "\"\(escaped)\"" : escaped
    }
}

// MARK: - Filter row UI

private struct FilterRowView: View {
    @Binding var row: FilterRow
    let availableFields: [BuilderField]
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Field", selection: $row.fieldKey) {
                    ForEach(availableFields, id: \.key) { f in
                        Text(f.label).tag(f.key)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Picker("Op", selection: $row.op) {
                    ForEach(availableOps, id: \.self) { op in
                        Text(op.label).tag(op)
                    }
                }
                .pickerStyle(.menu)
                if row.op.needsValue {
                    valueField
                } else {
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var currentField: BuilderField? {
        availableFields.first(where: { $0.key == row.fieldKey })
    }

    /// Restrict the operator list by field kind. Numbers / dates get the
    /// comparison operators; booleans only support equals / not-equals;
    /// enums get equals / not-equals / is empty.
    private var availableOps: [FilterOp] {
        switch currentField?.kind ?? .text {
        case .number, .date:
            return [.equals, .notEquals, .greaterThan, .lessThan, .isEmpty, .isNotEmpty]
        case .boolean:
            return [.equals, .notEquals]
        case .enum:
            return [.equals, .notEquals, .isEmpty, .isNotEmpty]
        case .text:
            return FilterOp.allCases
        }
    }

    @ViewBuilder
    private var valueField: some View {
        switch currentField?.kind ?? .text {
        case .boolean:
            Picker("Value", selection: $row.value) {
                Text("true").tag("true")
                Text("false").tag("false")
            }
            .pickerStyle(.segmented)
            .onAppear { if row.value.isEmpty { row.value = "true" } }
        case .enum:
            Picker("Value", selection: $row.value) {
                Text("—").tag("")
                ForEach(currentField?.options ?? [], id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.menu)
        case .number:
            TextField("Value", text: $row.value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        case .date:
            TextField("YYYY-MM-DD", text: $row.value)
                .multilineTextAlignment(.trailing)
        case .text:
            TextField("Value", text: $row.value)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Results screen

/// Vertical "card per row" layout — easier to read on a phone than a
/// horizontally-scrolling table. CSV export is the canonical path for
/// users that want to see all columns at once.
private struct ReportResultsView: View {
    let entity: BuilderEntity
    let fields: [BuilderField]
    let rows: [[String: String]]
    let onDownload: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                summary
                if rows.isEmpty {
                    Text("No rows match.")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                } else {
                    ForEach(rows.indices, id: \.self) { idx in
                        rowCard(rows[idx])
                    }
                }
            }
            .padding()
        }
        .navigationTitle("\(entity.label) — \(rows.count)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.doc")
                }
                .accessibilityLabel("Download CSV")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(rows.count) rows · \(fields.count) columns")
                .font(.subheadline).bold()
            Text("Tap the download icon to save as CSV.")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func rowCard(_ row: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(fields, id: \.key) { f in
                HStack(alignment: .top) {
                    Text(f.label)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text(displayValue(row[f.key] ?? "", kind: f.kind))
                        .font(.caption)
                        .foregroundColor(Color(uiColor: .label))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    /// Light formatting so empty cells render as a dash, booleans as Yes/No.
    private func displayValue(_ raw: String, kind: BuilderField.Kind) -> String {
        if raw.isEmpty { return "—" }
        if kind == .boolean {
            if raw == "true"  { return "Yes" }
            if raw == "false" { return "No" }
        }
        return raw
    }
}
