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
        // instead of a free-text input. Only crm_products is fully wired
        // today — other targets fall back to the generic text input until
        // their own picker is added.
        for d in defs where d.fieldType == "lookup" {
            switch d.targetTable {
            case "crm_products":
                if let items = try? await CRMService.shared.listProducts() {
                    lookupOptions[d.fieldKey] = items.map { ($0.id, $0.name) }
                }
            default:
                break
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
    /// the create body. Empty entries are skipped.
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
            // Stored value is the picked row's UUID; the label is what the
            // rep sees in the dropdown. Falls back to a text input when
            // the lookup target hasn't been wired yet (no options loaded).
            if let opts = model.lookupOptions[d.fieldKey], !opts.isEmpty {
                Picker(d.label, selection: Binding(
                    get: { model.text[d.fieldKey] ?? "" },
                    set: { model.text[d.fieldKey] = $0 })) {
                        Text("—").tag("")
                        ForEach(opts, id: \.id) { opt in
                            Text(opt.label).tag(opt.id)
                        }
                    }
            } else {
                HStack {
                    Text(d.label)
                    Spacer()
                    Text("—").foregroundColor(.secondary)
                }
            }
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
        default:
            // text / longtext / number / currency / url / email / phone / date / datetime
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
