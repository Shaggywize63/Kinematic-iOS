import SwiftUI

struct EmailComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let templates: [EmailTemplate]
    let onSend: (String, String, String, String?) async -> Void

    @State private var to = ""
    @State private var subject = ""
    @State private var body = ""
    @State private var templateId: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("to@example.com", text: $to).keyboardType(.emailAddress).autocapitalization(.none)
                }
                if !templates.isEmpty {
                    Section("Template") {
                        Picker("Template", selection: $templateId) {
                            Text("None").tag(String?.none)
                            ForEach(templates) { t in
                                Text(t.name).tag(String?.some(t.id))
                            }
                        }
                        .onChange(of: templateId) { newValue in
                            if let id = newValue, let t = templates.first(where: { $0.id == id }) {
                                subject = t.subject
                                body = t.body
                            }
                        }
                    }
                }
                Section("Message") {
                    TextField("Subject", text: $subject)
                    TextEditor(text: $body).frame(minHeight: 160)
                }
            }
            .navigationTitle("New Email")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task {
                            await onSend(to, subject, body, templateId)
                            dismiss()
                        }
                    }.disabled(to.isEmpty || subject.isEmpty)
                }
            }
        }
    }
}
