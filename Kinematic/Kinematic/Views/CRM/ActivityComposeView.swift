import SwiftUI

struct ActivityComposeView: View {
    @Environment(\.dismiss) private var dismiss

    /// Optional prefill — call buttons pass `initialType="call"` and a
    /// subject like "Call with <Name>". Default to the old "call" type
    /// + empty subject so existing callers (e.g. LeadDetailView's
    /// "Log Activity" button) keep their previous behavior.
    let initialType: String
    let initialSubject: String
    let onSubmit: (String, String, String) async -> Void

    @State private var type: String
    @State private var subject: String
    @State private var desc: String = ""

    init(
        initialType: String = "call",
        initialSubject: String = "",
        onSubmit: @escaping (String, String, String) async -> Void
    ) {
        self.initialType = initialType
        self.initialSubject = initialSubject
        self.onSubmit = onSubmit
        _type = State(initialValue: initialType)
        _subject = State(initialValue: initialSubject)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(["call", "email", "meeting", "note", "task"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }.pickerStyle(.segmented)
                }
                Section("Details") {
                    TextField("Subject", text: $subject)
                    TextField("Description", text: $desc, axis: .vertical).lineLimit(3...6)
                }
            }
            .navigationTitle("Log Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        Task {
                            await onSubmit(type, subject, desc)
                            dismiss()
                        }
                    }.disabled(subject.isEmpty)
                }
            }
        }
    }
}
