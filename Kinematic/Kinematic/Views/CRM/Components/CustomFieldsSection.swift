//
//  CustomFieldsSection.swift
//  Kinematic CRM
//
//  Renders admin-defined custom fields (from /api/v1/crm/custom-fields) as
//  inline form inputs inside a Form section. Mirrors the web pattern of
//  interleaving extras with the built-in fields. The parent owns a
//  `CustomFieldValues` binding which is serialized into `custom_fields` on
//  submit.
//
//  File/image fields are intentionally skipped on mobile for now — the
//  control surface is too constrained, and matching the web's drop-zone
//  uploader is out of scope for this pass.
//

import SwiftUI

struct CustomFieldsSection: View {
    let fields: [CRMCustomField]
    @Binding var values: CustomFieldValues

    var body: some View {
        if !fields.isEmpty {
            Section("Additional Information") {
                ForEach(sortedFields) { field in
                    CustomFieldInput(field: field, values: $values)
                }
            }
        }
    }

    private var sortedFields: [CRMCustomField] {
        fields.sorted { lhs, rhs in
            let l = lhs.position ?? Int.max
            let r = rhs.position ?? Int.max
            if l != r { return l < r }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }
}

private struct CustomFieldInput: View {
    let field: CRMCustomField
    @Binding var values: CustomFieldValues

    var body: some View {
        let labelText = field.required == true ? "\(field.label) *" : field.label
        switch field.fieldType {
        case "text", "url", "email", "phone":
            TextField(labelText, text: stringBinding())
                .keyboardType(keyboardType)
                .autocapitalization(field.fieldType == "email" || field.fieldType == "url" ? .none : .sentences)
        case "longtext":
            VStack(alignment: .leading, spacing: 4) {
                Text(labelText).font(.caption).foregroundColor(.secondary)
                TextEditor(text: stringBinding())
                    .frame(minHeight: 80)
            }
        case "number", "currency":
            TextField(labelText, text: stringBinding())
                .keyboardType(.decimalPad)
        case "boolean":
            Toggle(labelText, isOn: boolBinding())
        case "date":
            DatePicker(
                labelText,
                selection: dateBinding(),
                displayedComponents: .date
            )
        case "datetime":
            DatePicker(
                labelText,
                selection: dateBinding(),
                displayedComponents: [.date, .hourAndMinute]
            )
        case "select", "radio":
            Picker(labelText, selection: stringBinding()) {
                Text("—").tag("")
                ForEach(field.options ?? [], id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
        case "multiselect":
            MultiSelectField(label: labelText, options: field.options ?? [], selection: arrayBinding())
        case "image", "file":
            HStack {
                Text(labelText)
                Spacer()
                Text("Not supported on mobile yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        default:
            TextField(labelText, text: stringBinding())
        }
    }

    private var keyboardType: UIKeyboardType {
        switch field.fieldType {
        case "email": return .emailAddress
        case "phone": return .phonePad
        case "url":   return .URL
        case "number", "currency": return .decimalPad
        default: return .default
        }
    }

    // MARK: Bindings

    private func stringBinding() -> Binding<String> {
        Binding(
            get: { values[field.fieldKey] as? String ?? "" },
            set: { values[field.fieldKey] = $0 }
        )
    }

    private func boolBinding() -> Binding<Bool> {
        Binding(
            get: { values[field.fieldKey] as? Bool ?? false },
            set: { values[field.fieldKey] = $0 }
        )
    }

    private func dateBinding() -> Binding<Date> {
        Binding(
            get: { values[field.fieldKey] as? Date ?? Date() },
            set: { values[field.fieldKey] = $0 }
        )
    }

    private func arrayBinding() -> Binding<[String]> {
        Binding(
            get: { values[field.fieldKey] as? [String] ?? [] },
            set: { values[field.fieldKey] = $0 }
        )
    }
}

/// A simple multi-select renderer using a Menu with check marks — matches
/// the iOS form idiom better than a wall of toggles.
private struct MultiSelectField: View {
    let label: String
    let options: [String]
    @Binding var selection: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button {
                    toggle(opt)
                } label: {
                    HStack {
                        Text(opt)
                        if selection.contains(opt) {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(label)
                Spacer()
                Text(selection.isEmpty ? "Select" : selection.joined(separator: ", "))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func toggle(_ opt: String) {
        if let idx = selection.firstIndex(of: opt) {
            selection.remove(at: idx)
        } else {
            selection.append(opt)
        }
    }
}
