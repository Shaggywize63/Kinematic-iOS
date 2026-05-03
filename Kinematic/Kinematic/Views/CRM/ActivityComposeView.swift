import SwiftUI

struct ActivityComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var type = "call"
    @State private var subject = ""
    @State private var desc = ""

    let onSubmit: (String, String, String) async -> Void

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
