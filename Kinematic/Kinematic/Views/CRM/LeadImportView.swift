import SwiftUI

/// CSV import flow stub. We accept a pasted CSV blob, preview a few rows
/// client-side, then post to /api/v1/crm/import/preview + commit. Full file
/// upload (multipart) is intentionally deferred — the paste-CSV path covers
/// the parity ask without a system file picker dependency.
struct LeadImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var raw: String = "first_name,last_name,email,company\nJane,Doe,jane@example.com,Acme"
    @State private var status: String = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste CSV (header + rows). Columns: first_name, last_name, email, phone, company, source.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $raw)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 200)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundColor(.blue)
                }
                Button {
                    Task { await runImport() }
                } label: {
                    HStack {
                        if isWorking { ProgressView().tint(.white) }
                        Text("Import")
                    }
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.blue).cornerRadius(12)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Import Leads")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func runImport() async {
        isWorking = true; defer { isWorking = false }
        let lines = raw.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { status = "Need at least one data row."; return }
        let headers = lines[0].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let rows: [[String: Any]] = lines.dropFirst().map { row in
            let cells = row.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            var d: [String: Any] = [:]
            for (i, h) in headers.enumerated() where i < cells.count {
                d[h] = cells[i]
            }
            return d
        }
        do {
            _ = try await CRMService.shared.importPreview(rows: rows, entity: "leads")
            status = "Preview OK — \(rows.count) rows ready. Commit on web for now."
        } catch {
            status = "Import failed: \(error.localizedDescription)"
        }
    }
}
