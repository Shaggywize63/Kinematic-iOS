import SwiftUI
// Combine is NOT re-exported by SwiftUI on the Xcode 26 toolchain — the
// ObservableObject view model below fails to compile without this import.
import Combine

// MARK: - View model

@MainActor
final class VanLoadViewModel: ObservableObject {
    // Today's open/reconciled load (nil until the first fetch, and stays nil when
    // the rep hasn't loaded yet — that's the "start a load" state).
    @Published var load: VanLoad?
    @Published var didLoad = false           // initial /today fetch completed
    @Published var errorMsg: String?

    // Load-in form state.
    @Published var skus: [SkuLite] = []
    @Published var distributors: [DistributorLite] = []
    @Published var selectedDistributorId: String?
    @Published var loadQty: [String: Int] = [:]     // sku_id → loaded qty
    @Published var notes = ""
    @Published var submitting = false

    // Reconcile form state (end-of-day).
    @Published var returnedQty: [String: Int] = [:] // sku_id → returned
    @Published var damagedQty: [String: Int] = [:]  // sku_id → damaged
    @Published var reconcileNotes = ""
    @Published var reconciling = false

    private let api = DistributionAPI.shared

    func refresh() async {
        errorMsg = nil
        do {
            load = try await api.vanLoadToday()
        } catch {
            errorMsg = error.localizedDescription
        }
        // SKUs + distributors back the "start a load" form only; best-effort so a
        // missing/module-gated distributors endpoint never blocks the screen.
        if skus.isEmpty { skus = (try? await api.skus()) ?? [] }
        if distributors.isEmpty { distributors = (try? await api.distributors()) ?? [] }
        didLoad = true
    }

    func setLoadQty(_ skuId: String, _ qty: Int) {
        if qty <= 0 { loadQty.removeValue(forKey: skuId) } else { loadQty[skuId] = qty }
    }

    func submitLoad() async {
        let items = loadQty.compactMap { (sku, qty) -> VanLoadItemInput? in
            guard qty > 0 else { return nil }
            return VanLoadItemInput(sku_id: sku, loaded_qty: Double(qty))
        }
        guard !items.isEmpty else { errorMsg = "Add at least one SKU."; return }
        submitting = true; errorMsg = nil
        defer { submitting = false }
        let input = VanLoadCreateInput(
            distributor_id: selectedDistributorId,
            route_plan_id: nil,
            load_date: nil,
            notes: notes.isEmpty ? nil : notes,
            items: items
        )
        do {
            load = try await api.createVanLoad(input, idempotencyKey: UUID().uuidString)
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    func submitReconcile() async {
        guard let current = load else { return }
        // One line per loaded SKU; unentered SKUs default to 0 returned/damaged.
        let lines = current.items.map { item -> VanReconcileItemInput in
            VanReconcileItemInput(
                sku_id: item.sku_id,
                returned_qty: Double(returnedQty[item.sku_id] ?? 0),
                damaged_qty: Double(damagedQty[item.sku_id] ?? 0)
            )
        }
        guard !lines.isEmpty else { errorMsg = "Nothing to reconcile."; return }
        reconciling = true; errorMsg = nil
        defer { reconciling = false }
        let input = VanReconcileInput(items: lines, notes: reconcileNotes.isEmpty ? nil : reconcileNotes)
        do {
            load = try await api.reconcileVanLoad(id: current.id, input: input, idempotencyKey: UUID().uuidString)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Root

struct VanLoadView: View {
    @StateObject private var vm = VanLoadViewModel()

    var body: some View {
        Group {
            if !vm.didLoad {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let load = vm.load {
                VanLoadDetail(vm: vm, load: load)
            } else {
                VanLoadStartForm(vm: vm)
            }
        }
        .navigationTitle("Van Load")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !vm.didLoad { await vm.refresh() } }
    }
}

// MARK: - Start a load (day-start load-in)

private struct VanLoadStartForm: View {
    @ObservedObject var vm: VanLoadViewModel
    @State private var showSkuPicker = false

    var body: some View {
        Form {
            if let err = vm.errorMsg {
                Section { Text(err).font(.caption).foregroundColor(.red) }
            }
            Section {
                Text("Load your van for today. Add each SKU with the quantity loaded, then start the load. You'll reconcile returns and damages at end of day.")
                    .font(.caption).foregroundColor(.secondary)
            }
            if !vm.distributors.isEmpty {
                Section("Distributor (optional)") {
                    Picker("Distributor", selection: Binding(
                        get: { vm.selectedDistributorId ?? "" },
                        set: { vm.selectedDistributorId = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(vm.distributors) { d in
                            Text(d.name ?? d.code ?? d.id).tag(d.id)
                        }
                    }
                }
            }
            Section {
                Button { showSkuPicker = true } label: {
                    Label("Add SKUs", systemImage: "plus.circle")
                }
            }
            if selectedSkus.isEmpty {
                Section { Text("No SKUs added yet.").font(.caption).foregroundColor(.secondary) }
            } else {
                Section("Loaded items (\(selectedSkus.count))") {
                    ForEach(selectedSkus) { sku in loadRow(sku) }
                }
            }
            Section("Notes (optional)") {
                TextField("Notes", text: $vm.notes)
            }
            Section {
                Button(vm.submitting ? "Starting…" : "Start Van Load") {
                    Task { await vm.submitLoad() }
                }
                .disabled(vm.submitting || vm.loadQty.isEmpty)
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .listRowBackground(Color(red: 208/255, green: 30/255, blue: 44/255))
            }
        }
        .sheet(isPresented: $showSkuPicker) {
            VanSkuPickerSheet(vm: vm)
        }
    }

    private var selectedSkus: [SkuLite] {
        vm.skus
            .filter { vm.loadQty[$0.id] != nil }
            .sorted { ($0.name ?? $0.id) < ($1.name ?? $1.id) }
    }

    private func loadRow(_ sku: SkuLite) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sku.name ?? sku.sku_code ?? sku.id).font(.subheadline).bold()
                if let code = sku.sku_code {
                    Text(code).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            Stepper(value: Binding(
                get: { vm.loadQty[sku.id] ?? 0 },
                set: { vm.setLoadQty(sku.id, $0) }
            ), in: 0...9999) {
                Text("\(vm.loadQty[sku.id] ?? 0)").font(.subheadline).bold().frame(width: 44)
            }.labelsHidden()
        }
    }
}

// MARK: - SKU picker (searchable)

private struct VanSkuPickerSheet: View {
    @ObservedObject var vm: VanLoadViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { sku in skuRow(sku) }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search name or code")
            .overlay {
                if vm.skus.isEmpty {
                    ContentUnavailableView("No SKUs", systemImage: "shippingbox",
                                           description: Text("No SKUs are available to load."))
                } else if filtered.isEmpty {
                    ContentUnavailableView("No matches", systemImage: "magnifyingglass",
                                           description: Text("No SKUs match “\(query)”."))
                }
            }
            .navigationTitle("Add SKUs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private var filtered: [SkuLite] {
        let active = vm.skus.filter { $0.is_active ?? true }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? active : active.filter {
            ($0.name?.lowercased().contains(q) ?? false)
                || ($0.sku_code?.lowercased().contains(q) ?? false)
                || ($0.category?.lowercased().contains(q) ?? false)
        }
        return base.sorted { ($0.name ?? $0.id) < ($1.name ?? $1.id) }
    }

    private func skuRow(_ sku: SkuLite) -> some View {
        let qty = vm.loadQty[sku.id] ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sku.name ?? sku.sku_code ?? sku.id).font(.subheadline).bold()
                Text([sku.sku_code, sku.category].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if qty == 0 {
                Button { vm.setLoadQty(sku.id, 1) } label: { Text("Add").bold() }
                    .buttonStyle(.bordered)
            } else {
                Stepper(value: Binding(
                    get: { vm.loadQty[sku.id] ?? 0 },
                    set: { vm.setLoadQty(sku.id, $0) }
                ), in: 0...9999) {
                    Text("\(qty)").font(.subheadline).bold().frame(width: 44)
                }.labelsHidden()
            }
        }
    }
}

// MARK: - Existing load (items table + totals + reconcile)

private struct VanLoadDetail: View {
    @ObservedObject var vm: VanLoadViewModel
    let load: VanLoad

    var body: some View {
        List {
            if let err = vm.errorMsg {
                Section { Text(err).font(.caption).foregroundColor(.red) }
            }
            Section {
                HStack {
                    statusBadge
                    Spacer()
                    Text(load.load_date).font(.caption).foregroundColor(.secondary)
                }
            }
            Section("Items") {
                if load.items.isEmpty {
                    Text("No items on this load.").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(load.items) { item in itemRow(item) }
                }
            }
            if let t = load.totals {
                Section("Totals") {
                    totalRow("Loaded", t.loaded)
                    totalRow("Sold", t.sold)
                    totalRow("Returned", t.returned)
                    totalRow("Damaged", t.damaged)
                }
            }
            if load.status == "open" {
                reconcileSection
            } else {
                Section {
                    Text("This load is \(load.status). Sold quantities are derived from returns and damages.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await vm.refresh() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }

    private var reconcileSection: some View {
        Group {
            Section("Reconcile — returned & damaged") {
                ForEach(load.items) { item in reconcileRow(item) }
            }
            Section("Notes (optional)") {
                TextField("Reconcile notes", text: $vm.reconcileNotes)
            }
            Section {
                Button(vm.reconciling ? "Reconciling…" : "Submit Reconcile") {
                    Task { await vm.submitReconcile() }
                }
                .disabled(vm.reconciling)
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .listRowBackground(Color(red: 208/255, green: 30/255, blue: 44/255))
            }
        }
    }

    private func itemRow(_ item: VanLoadItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.skus?.name ?? item.skus?.sku_code ?? item.sku_id).font(.subheadline).bold()
            HStack(spacing: 16) {
                qtyPill("Loaded", item.loaded_qty)
                qtyPill("Sold", item.sold_qty)
                qtyPill("Ret", item.returned_qty)
                qtyPill("Dmg", item.damaged_qty)
            }
        }
        .padding(.vertical, 2)
    }

    private func reconcileRow(_ item: VanLoadItem) -> some View {
        let loaded = Int(item.loaded_qty.rounded())
        let returned = vm.returnedQty[item.sku_id] ?? 0
        let damaged = vm.damagedQty[item.sku_id] ?? 0
        let derivedSold = max(0, loaded - returned - damaged)
        return VStack(alignment: .leading, spacing: 8) {
            Text(item.skus?.name ?? item.skus?.sku_code ?? item.sku_id).font(.subheadline).bold()
            Text("Loaded \(loaded)  ·  Sold (derived) \(derivedSold)")
                .font(.caption2).foregroundColor(.secondary)
            HStack {
                Text("Returned").font(.caption)
                Spacer()
                Stepper(value: Binding(
                    get: { vm.returnedQty[item.sku_id] ?? 0 },
                    set: { vm.returnedQty[item.sku_id] = max(0, $0) }
                ), in: 0...max(0, loaded)) {
                    Text("\(returned)").font(.subheadline).bold().frame(width: 44)
                }.labelsHidden()
            }
            HStack {
                Text("Damaged").font(.caption)
                Spacer()
                Stepper(value: Binding(
                    get: { vm.damagedQty[item.sku_id] ?? 0 },
                    set: { vm.damagedQty[item.sku_id] = max(0, $0) }
                ), in: 0...max(0, loaded)) {
                    Text("\(damaged)").font(.subheadline).bold().frame(width: 44)
                }.labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }

    private func qtyPill(_ label: String, _ v: Double) -> some View {
        VStack(spacing: 1) {
            Text(vanFmtQty(v)).font(.subheadline).bold()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    private func totalRow(_ label: String, _ v: Double) -> some View {
        HStack { Text(label); Spacer(); Text(vanFmtQty(v)).bold() }
    }

    private var statusBadge: some View {
        let s = load.status
        let color: Color = s == "open" ? .green : (s == "reconciled" ? .blue : .gray)
        return Text(s.capitalized)
            .font(.caption).bold()
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// Trim a whole-value Double to an integer string; keep one decimal otherwise.
private func vanFmtQty(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}
