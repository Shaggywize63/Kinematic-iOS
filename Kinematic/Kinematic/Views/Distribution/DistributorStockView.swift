import SwiftUI
// Combine is NOT re-exported by SwiftUI on the Xcode 26 toolchain — the
// ObservableObject view model below fails to compile without this import.
import Combine

// MARK: - View model

@MainActor
final class DistributorStockViewModel: ObservableObject {
    @Published var distributors: [DistributorLite] = []
    @Published var selectedDistributorId: String?
    @Published var rows: [DistributorStockRow] = []
    @Published var lowOnly = false
    @Published var loadingDistributors = false
    @Published var loadingStock = false
    @Published var didLoad = false           // initial distributors fetch completed
    @Published var errorMsg: String?

    private let api = DistributionAPI.shared

    func loadDistributors() async {
        loadingDistributors = true; errorMsg = nil
        defer { loadingDistributors = false; didLoad = true }
        do {
            distributors = try await api.distributors()
        } catch {
            distributors = []
            errorMsg = error.localizedDescription
        }
    }

    func selectDistributor(_ id: String) async {
        selectedDistributorId = id.isEmpty ? nil : id
        await loadStock()
    }

    func setLowOnly(_ on: Bool) async {
        lowOnly = on
        await loadStock()
    }

    func loadStock() async {
        guard let id = selectedDistributorId else { rows = []; return }
        loadingStock = true; errorMsg = nil
        defer { loadingStock = false }
        do {
            rows = try await api.distributorStock(distributorId: id, lowOnly: lowOnly)
        } catch {
            rows = []
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - View

struct DistributorStockView: View {
    @StateObject private var vm = DistributorStockViewModel()

    var body: some View {
        List {
            if let err = vm.errorMsg {
                Section { Text(err).font(.caption).foregroundColor(.red) }
            }
            Section("Distributor") {
                if vm.loadingDistributors {
                    ProgressView()
                } else if vm.distributors.isEmpty {
                    Text("No distributors available. Ask your administrator to enable distributor access.")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Picker("Distributor", selection: Binding(
                        get: { vm.selectedDistributorId ?? "" },
                        set: { id in Task { await vm.selectDistributor(id) } }
                    )) {
                        Text("Select…").tag("")
                        ForEach(vm.distributors) { d in
                            Text(d.name ?? d.code ?? d.id).tag(d.id)
                        }
                    }
                }
            }
            if vm.selectedDistributorId != nil {
                Section {
                    Toggle("Low / out of stock only", isOn: Binding(
                        get: { vm.lowOnly },
                        set: { on in Task { await vm.setLowOnly(on) } }
                    ))
                }
                Section("On-hand") {
                    if vm.loadingStock {
                        ProgressView()
                    } else if vm.rows.isEmpty {
                        Text(vm.lowOnly ? "Nothing low or out of stock." : "No stock rows for this distributor.")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(vm.rows) { row in stockRow(row) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Distributor Stock")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !vm.didLoad { await vm.loadDistributors() } }
    }

    private func stockRow(_ row: DistributorStockRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.sku_name ?? row.sku_code ?? row.sku_id).font(.subheadline).bold()
                Text([row.sku_code, row.category].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Avail \(stockFmt(row.available))")
                    .font(.subheadline).bold()
                    .foregroundColor(row.available <= 0 ? .red : .primary)
                Text("Qty \(stockFmt(row.qty))  ·  Rsv \(stockFmt(row.reserved))")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// Trim a whole-value Double to an integer string; keep one decimal otherwise.
private func stockFmt(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}
