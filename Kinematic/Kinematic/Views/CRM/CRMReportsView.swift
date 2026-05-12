import SwiftUI
import UniformTypeIdentifiers

/// CRM reports — client-side CSV export for Leads, Contacts, and Deals.
/// Matches the dashboard's reports/builder behaviour (fetch → format → blob).
/// Saves to a temp file and presents UIActivityViewController for share/save.
struct CRMReportsView: View {
    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                exportCard(
                    title: "Leads",
                    subtitle: "All leads with status, score, contact info",
                    icon: "person.crop.circle.badge.plus",
                    color: .blue,
                    action: exportLeads
                )

                exportCard(
                    title: "Contacts",
                    subtitle: "All contacts with email, phone, account",
                    icon: "person.2.fill",
                    color: .purple,
                    action: exportContacts
                )

                exportCard(
                    title: "Deals",
                    subtitle: "Open + won + lost deals with amount, stage",
                    icon: "square.stack.3d.up.fill",
                    color: .green,
                    action: exportDeals
                )

                if let msg = statusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
            }
            .padding()
        }
        .navigationTitle("Reports")
        .sheet(item: ShareIdentifiable.binding($shareURL)) { item in
            ActivityShareSheet(items: [item.url])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export CRM data").font(.headline)
            Text("Download leads, contacts, or deals as a CSV file. Filters from the global location bar are applied.")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func exportCard(title: String, subtitle: String, icon: String, color: Color, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: icon).foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(Color(uiColor: .label))
                    Text(subtitle).font(.caption).foregroundColor(.gray)
                }
                Spacer()
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.doc.fill").foregroundColor(color)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    // MARK: Export logic

    private func exportLeads() async {
        await runExport(filenamePrefix: "leads") {
            let rows = try await CRMService.shared.listLeads()
            let headers = ["id","first_name","last_name","email","phone","company","title","status","score","city","state","is_b2c","created_at"]
            var lines: [String] = [headers.joined(separator: ",")]
            for l in rows {
                lines.append([
                    l.id, l.firstName ?? "", l.lastName ?? "", l.email ?? "", l.phone ?? "",
                    l.company ?? "", l.title ?? "", l.status ?? "", String(l.score ?? 0),
                    l.city ?? "", l.state ?? "", String(l.isB2c ?? false), l.createdAt ?? "",
                ].map(escape).joined(separator: ","))
            }
            return lines.joined(separator: "\n")
        }
    }

    private func exportContacts() async {
        await runExport(filenamePrefix: "contacts") {
            let rows = try await CRMService.shared.listContacts()
            let headers = ["id","first_name","last_name","email","phone","account_name","title","city","created_at"]
            var lines: [String] = [headers.joined(separator: ",")]
            for c in rows {
                lines.append([
                    c.id, c.firstName ?? "", c.lastName ?? "", c.email ?? "", c.phone ?? "",
                    c.accountName ?? "", c.title ?? "", c.city ?? "", c.createdAt ?? "",
                ].map(escape).joined(separator: ","))
            }
            return lines.joined(separator: "\n")
        }
    }

    private func exportDeals() async {
        await runExport(filenamePrefix: "deals") {
            let rows = try await CRMService.shared.listDeals()
            let headers = ["id","name","amount","currency","status","stage_id","win_probability","expected_close_date","account_id","created_at"]
            var lines: [String] = [headers.joined(separator: ",")]
            for d in rows {
                lines.append([
                    d.id, d.name, String(d.amount ?? 0), d.currency ?? "INR",
                    d.status ?? "", d.stageId ?? "", String(d.winProbability ?? 0),
                    d.expectedCloseDate ?? "", d.accountId ?? "", d.createdAt ?? "",
                ].map(escape).joined(separator: ","))
            }
            return lines.joined(separator: "\n")
        }
    }

    private func runExport(filenamePrefix: String, build: () async throws -> String) async {
        isBusy = true; statusMessage = nil
        defer { isBusy = false }
        do {
            let csv = try await build()
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            let filename = "\(filenamePrefix)-\(formatter.string(from: Date())).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            shareURL = url
            statusMessage = "Exported \(filename)"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func escape(_ s: String) -> String {
        let needsQuoting = s.contains(",") || s.contains("\"") || s.contains("\n")
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuoting ? "\"\(escaped)\"" : escaped
    }
}

// Helper to make an optional URL identifiable for .sheet(item:)
private struct ShareIdentifiable: Identifiable {
    let id = UUID()
    let url: URL
    static func binding(_ source: Binding<URL?>) -> Binding<ShareIdentifiable?> {
        Binding(
            get: { source.wrappedValue.map { ShareIdentifiable(url: $0) } },
            set: { source.wrappedValue = $0?.url }
        )
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
