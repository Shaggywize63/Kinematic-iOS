import SwiftUI

struct DealsListView: View {
    @StateObject var vm = DealsViewModel()
    @State private var showCreate = false
    @State private var showDateFilter = false
    @State private var isExporting = false
    @State private var exportShareItem: ShareItem?
    @State private var exportError: String?
    @AppStorage("crm.deals.showWeighted") private var showWeighted: Bool = false
    let statusOptions = ["open", "won", "lost", "all"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: showWeighted ? "scalemass.fill" : "indianrupeesign.circle.fill")
                    .foregroundColor(showWeighted ? .indigo : .green)
                    .font(.caption)
                Text(showWeighted ? "Weighted" : "Cost")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $showWeighted).labelsHidden().tint(.indigo)
            }
            .padding(.horizontal).padding(.top, 8)
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(statusOptions, id: \.self) { s in
                            Button {
                                vm.statusFilter = s
                                Task { await vm.refresh() }
                            } label: {
                                Text(s.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(vm.statusFilter == s ? Color.indigo : Color(uiColor: .secondarySystemBackground))
                                    .foregroundColor(vm.statusFilter == s ? .white : .gray)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.leading)
                }
                Button { showDateFilter = true } label: {
                    Image(systemName: "calendar")
                        .foregroundColor(vm.dateFrom != nil || vm.dateTo != nil ? .indigo : .gray)
                        .padding(.trailing, 12)
                }
                if vm.dateFrom != nil || vm.dateTo != nil {
                    Button { vm.dateFrom = nil; vm.dateTo = nil; Task { await vm.refresh() } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red).padding(.trailing, 8)
                    }
                }
            }
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.deals.isEmpty {
                        Text("No deals.").foregroundColor(.gray).padding(.top, 60)
                    } else {
                        ForEach(vm.deals) { d in
                            NavigationLink(destination: DealDetailView(dealId: d.id, initialDeal: d)) {
                                DealCard(deal: d)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .refreshable { await vm.refresh() }
        }
        .navigationTitle("Deals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await downloadCSV() }
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.down.doc")
                    }
                }
                .disabled(isExporting)
                .accessibilityLabel("Download CSV")
            }
        }
        .sheet(isPresented: $showCreate) {
            DealCreateView { body in
                await vm.create(body: body)
            }
        }
        .sheet(isPresented: $showDateFilter) {
            DateRangeFilterSheet(from: $vm.dateFrom, to: $vm.dateTo, label: "Close date") {
                Task { await vm.refresh() }
            }
        }
        .sheet(item: $exportShareItem) { item in
            ActivityShareSheet(items: [item.url])
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .task { await vm.refresh() }
    }

    /// Calls the server-side deals export endpoint and presents the resulting
    /// CSV via UIActivityViewController. Same pattern CRMReportsView uses so
    /// we get identical line-item / custom-field column coverage.
    private func downloadCSV() async {
        await MainActor.run { isExporting = true; exportError = nil }
        defer { Task { @MainActor in isExporting = false } }
        do {
            let data = try await CRMService.shared.exportDealsCSV()
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            let filename = "deals-\(fmt.string(from: Date())).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run { exportShareItem = ShareItem(url: url) }
        } catch {
            await MainActor.run { exportError = error.localizedDescription }
        }
    }
}
