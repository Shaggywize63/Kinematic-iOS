import SwiftUI

/// Every odometer reading the signed-in person has claimed, newest first: the date, the vehicle, the reading
/// before → after, the distance, and where the claim stands. Tap a photo to see it.
///
/// Offered only by policies that pay mileage by vehicle (see ExpenseClaimsView's toolbar). The list is the
/// caller's own lines — the server decides what comes back.
struct OdometerHistoryView: View {
    @ObservedObject var vm: ExpensesViewModel
    @State private var viewing: ReceiptRef?

    var body: some View {
        Group {
            if let err = vm.odometerError, vm.odometerHistory.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load the history", systemImage: "exclamationmark.triangle")
                } description: { Text(err) } actions: {
                    Button("Try again") { Task { await vm.loadOdometerHistory(force: true) } }
                }
            } else if !vm.odometerLoaded && vm.odometerHistory.isEmpty {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.odometerHistory.isEmpty {
                ContentUnavailableView("No readings yet", systemImage: "speedometer",
                                       description: Text("The odometer readings on your claims will appear here."))
            } else {
                List {
                    ForEach(vm.odometerHistory) { entry in row(entry) }
                }
                .refreshable { await vm.loadOdometerHistory(force: true) }
            }
        }
        .navigationTitle("Odometer history")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadOdometerHistory(force: true) }
        .sheet(item: $viewing) { ReceiptViewerSheet(url: $0.url) }
    }

    private func row(_ e: ExpenseOdometerEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ExpenseLogic.shortDate(e.item_date) ?? "—").font(.subheadline).bold()
                Spacer()
                if let km = e.distance_km {
                    Text("\(ExpenseLogic.trimNumber(km)) km").font(.subheadline).bold()
                }
            }
            if !e.vehicleText.isEmpty {
                Text(e.vehicleText).font(.subheadline).foregroundColor(.secondary)
            }
            if let readings = e.readingsText {
                Text("Odometer \(readings)").font(.subheadline).foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                let color = expenseStatusColor(e.claim_status)
                Text(e.statusText).font(.caption2).bold()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.15)).foregroundColor(color).clipShape(Capsule())
                if let no = e.claim_no, !no.isEmpty {
                    Text(no).font(.caption).foregroundColor(.secondary)
                }
            }
            if !(e.start_photo_url ?? "").isEmpty || !(e.end_photo_url ?? "").isEmpty {
                HStack(spacing: 14) {
                    photoButton("Before", e.start_photo_url)
                    photoButton("After", e.end_photo_url)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func photoButton(_ label: String, _ url: String?) -> some View {
        if let u = url, !u.isEmpty {
            Button { viewing = ReceiptRef(url: u) } label: {
                HStack(spacing: 8) {
                    ReceiptThumbnail(url: u)
                    Text(label).font(.caption).foregroundColor(.accentColor)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
