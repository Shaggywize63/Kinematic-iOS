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

    func load(entity: String) async {
        let all = await CRMService.shared.listCustomFields()
        let roleId = await CRMService.shared.myOrgRoleId()
        defs = all
            .filter { d in
                guard d.entityType == entity else { return false }
                // No roles tagged = universal; otherwise must include my role.
                guard let roles = d.orgRoleIds, !roles.isEmpty else { return true }
                guard let rid = roleId else { return false }
                return roles.contains(rid)
            }
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
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
