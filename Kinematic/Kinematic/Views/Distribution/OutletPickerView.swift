import SwiftUI

/// Searchable list of the outlets in the rep's scope (`GET /salesman/outlets?search=&limit=` — today's route-plan
/// outlets first), shown with what the outlet owes where the server sends it. Shared by Collect Payment (when no
/// outlet is preselected) and by Book Order ("Choose another outlet" / the Book Order menu entry). Searching needs a
/// connection: offline it says so instead of showing an empty list. Present it in a sheet; the caller closes the
/// sheet from `onPick`.
struct OutletPickerView: View {
    let onPick: (SalesmanOutlet) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var outlets: [SalesmanOutlet] = []
    /// The normalized query `outlets` was fetched for (nil = the empty query).
    @State private var resultsQuery: String? = nil
    @State private var loading = true
    @State private var problem: String? = nil

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Choose outlet")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search by outlet name or code")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .task(id: query) { await load() }
        }
    }

    private var shown: [SalesmanOutlet] {
        OutletPickerLogic.displayed(results: outlets, resultsQuery: resultsQuery, currentQuery: query)
    }

    @ViewBuilder private var content: some View {
        if let problem = problem {
            messageView(problem)
        } else if loading && shown.isEmpty {
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading outlets…").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if shown.isEmpty {
            messageView(OutletPickerLogic.emptyMessage(forQuery: query))
        } else {
            List(shown) { outlet in
                Button { onPick(outlet) } label: { row(outlet) }
                    .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func messageView(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ outlet: SalesmanOutlet) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(OutletPickerLogic.displayName(outlet)).font(.subheadline.weight(.semibold)).lineLimit(2)
                let detail = OutletPickerLogic.detailLine(outlet)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if let due = OutletPickerLogic.dueLabel(outlet) {
                Text(due).font(.caption.weight(.semibold)).foregroundColor(.red)
            }
        }
        .contentShape(Rectangle())
    }

    /// Fetches the outlets for the current query. `.task(id: query)` cancels the previous run when the text changes,
    /// so a slow answer for an old query is dropped and typing is debounced.
    private func load() async {
        let normalized = OutletPickerLogic.normalizedQuery(query)
        if normalized != nil {
            try? await Task.sleep(nanoseconds: 300_000_000)      // debounce typing; the first (empty) load is immediate
            if Task.isCancelled { return }
        }
        loading = true
        let result = await DistributionAPI.shared.searchOutlets(query: normalized, limit: OutletPickerLogic.pageSize)
        if Task.isCancelled { return }
        switch result {
        case .found(let list):
            outlets = list
            resultsQuery = normalized
            problem = nil
        case .offline:
            outlets = []
            resultsQuery = normalized
            problem = OutletPickerLogic.offlineMessage
        case .failed(let reason):
            outlets = []
            resultsQuery = normalized
            problem = OutletPickerLogic.failedMessage(reason)
        }
        loading = false
    }
}

/// "Book Order" with no outlet preselected (the side menu entry): the outlet picker first, then the order cart for the
/// outlet picked — with its distributor. Closing the picker without choosing closes the screen.
struct OrderOutletPickView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var picked: SalesmanOutlet? = nil
    @State private var showPicker = true

    var body: some View {
        Group {
            if let outlet = picked {
                let target = OutletPickerLogic.orderTarget(for: outlet)
                OrderCartView(outletId: target.outletId, outletName: target.outletName, visitId: nil,
                              distributorId: target.distributorId)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "storefront").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("Choose the outlet to book an order for").font(.subheadline).foregroundColor(.secondary)
                    Button("Choose outlet") { showPicker = true }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Book Order")
            }
        }
        .sheet(isPresented: $showPicker, onDismiss: pickerClosed) {
            OutletPickerView(onPick: { outlet in
                picked = outlet
                showPicker = false
            })
        }
    }

    private func pickerClosed() {
        // Closed without choosing anyone: there is nothing to show, go back.
        if picked == nil { dismiss() }
    }
}
