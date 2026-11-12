import SwiftUI

// Connected-B2B (Spark & Ray): the "Lead" and "Deal" pickers on the expense claim editor. The lead picker reuses
// the activity composer's `LeadSearchPickerSheet`; the deal picker is a searchable list narrowed to the chosen
// lead's deals (the deals endpoint has no search, so the name filter runs here). The rules that keep the two
// consistent live in `ExpenseLinkState` / `ExpenseLinkLogic`.

/// One tappable "label ... value" row with a clear button once something is picked.
struct ExpenseLinkPickRow: View {
    let label: String
    /// The picked record's name; nil when nothing is picked.
    let value: String?
    let placeholder: String
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack {
                    Text(label).foregroundColor(.primary)
                    Spacer()
                    Text(value ?? placeholder)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            if value != nil {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear \(label.lowercased())")
            }
        }
    }
}

/// Searchable deal list for the expense editor. With `leadId` it lists only that lead's deals.
struct ExpenseDealPickerSheet: View {
    let leadId: String?
    let onPick: (Deal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var deals: [Deal] = []
    @State private var loading = false

    private var shown: [Deal] {
        ExpenseLinkLogic.dealOptions(deals, leadId: leadId, query: search)
    }

    var body: some View {
        NavigationStack {
            List(shown) { deal in
                Button {
                    onPick(deal)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deal.name).foregroundColor(.primary)
                        let sub = [deal.leadName, deal.stageName]
                            .compactMap { ExpenseLinkLogic.clean($0) }
                            .joined(separator: " · ")
                        if !sub.isEmpty {
                            Text(sub).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if loading {
                    ProgressView()
                } else if shown.isEmpty {
                    Text(leadId == nil ? "No deals found" : "No deals for this lead")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .searchable(text: $search, prompt: "Search deals")
            .navigationTitle("Select deal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                loading = true
                defer { loading = false }
                deals = (try? await CRMService.shared.listDeals()) ?? []
            }
        }
    }
}
