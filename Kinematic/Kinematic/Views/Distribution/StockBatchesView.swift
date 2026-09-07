import SwiftUI
// Combine is NOT re-exported by SwiftUI on the Xcode 26 toolchain — the
// ObservableObject view model below fails to compile without this import.
import Combine

// MARK: - View model

@MainActor
final class StockBatchesViewModel: ObservableObject {
    // Distributor scope (picker; defaults to the rep's assigned distributor).
    @Published var distributors: [DistributorLite] = []
    @Published var selectedDistributorId: String?

    // Batch list + expiry rollup.
    @Published var batches: [StockBatch] = []
    @Published var alerts: BatchAlerts?
    @Published var statusFilter = "all"      // all | active | near_expiry | expired

    @Published var loadingDistributors = false
    @Published var loadingBatches = false
    @Published var didLoad = false           // initial distributors + first batch fetch completed
    @Published var errorMsg: String?

    // Receive (GRN) form state — SKUs back the picker; the rest is the form.
    @Published var skus: [SkuLite] = []
    @Published var receiveDistributorId: String?
    @Published var receiveSkuId: String?
    @Published var receiveQty: Int = 1
    @Published var receiveBatchNo = ""
    @Published var includeExpiry = false
    @Published var receiveExpiry: Date = Date()
    @Published var includeMfg = false
    @Published var receiveMfg: Date = Date()
    @Published var receiveUnitCost = ""
    @Published var receiveReference = ""
    @Published var receiving = false
    @Published var receiveError: String?

    private let api = DistributionAPI.shared
    /// Near-expiry window (days) used for both the list's `near_days` and the
    /// alerts rollup's `within_days`, so the pill counts match the tinted rows.
    let nearDays = 30

    var receiveSku: SkuLite? {
        guard let id = receiveSkuId else { return nil }
        return skus.first { $0.id == id }
    }

    func load() async {
        loadingDistributors = true; errorMsg = nil
        defer { loadingDistributors = false; didLoad = true }
        do {
            distributors = try await api.distributors()
        } catch {
            distributors = []
            errorMsg = error.localizedDescription
        }
        // Default to the rep's assigned distributor: the sole / first distributor
        // scoped to them by /distribution/distributors. The picker stays visible
        // so reps who cover more than one can switch.
        if selectedDistributorId == nil, let first = distributors.first {
            selectedDistributorId = first.id
        }
        // SKUs back the Receive form only; best-effort so a missing / module-gated
        // SKU endpoint never blocks the screen.
        if skus.isEmpty { skus = (try? await api.skus()) ?? [] }
        await loadBatches()
    }

    func selectDistributor(_ id: String) async {
        selectedDistributorId = id.isEmpty ? nil : id
        await loadBatches()
    }

    func setStatus(_ s: String) async {
        statusFilter = s
        await loadBatches()
    }

    func loadBatches() async {
        guard let id = selectedDistributorId else { batches = []; alerts = nil; return }
        loadingBatches = true; errorMsg = nil
        defer { loadingBatches = false }
        do {
            async let rows = api.fetchBatches(distributorId: id, status: statusFilter, nearDays: nearDays)
            async let rollup = api.fetchBatchAlerts(distributorId: id, withinDays: nearDays)
            let (fetched, fetchedAlerts) = try await (rows, rollup)
            // FEFO — soonest expiry first. Sort by days_to_expiry (expired rows
            // are negative and sort to the top); rows with no expiry sink last.
            batches = fetched.sorted { Self.fefoBefore($0, $1) }
            alerts = fetchedAlerts
        } catch {
            batches = []; alerts = nil
            errorMsg = error.localizedDescription
        }
    }

    /// FEFO comparator: soonest expiry first, missing expiry last.
    static func fefoBefore(_ a: StockBatch, _ b: StockBatch) -> Bool {
        let av = a.days_to_expiry ?? Int.max
        let bv = b.days_to_expiry ?? Int.max
        if av != bv { return av < bv }
        return (a.expiry_date ?? "~") < (b.expiry_date ?? "~")
    }

    func submitReceive() async {
        let distId = receiveDistributorId ?? selectedDistributorId
        guard let distributorId = distId, !distributorId.isEmpty else {
            receiveError = "Select a distributor."; return
        }
        guard let skuId = receiveSkuId, !skuId.isEmpty else {
            receiveError = "Select a SKU."; return
        }
        guard receiveQty > 0 else { receiveError = "Quantity must be at least 1."; return }
        receiving = true; receiveError = nil
        defer { receiving = false }

        let unit = Double(receiveUnitCost.trimmingCharacters(in: .whitespaces))
        let input = ReceiveBatchInput(
            distributor_id: distributorId,
            sku_id: skuId,
            qty: Double(receiveQty),
            batch_no: receiveBatchNo.isEmpty ? nil : receiveBatchNo,
            expiry_date: includeExpiry ? Self.dateFmt.string(from: receiveExpiry) : nil,
            mfg_date: includeMfg ? Self.dateFmt.string(from: receiveMfg) : nil,
            unit_cost: unit,
            reference: receiveReference.isEmpty ? nil : receiveReference
        )
        do {
            // Fresh idempotency key per submit — a retry of the SAME tap reuses
            // it, a new tap gets a new one.
            _ = try await api.receiveBatch(input, idempotencyKey: UUID().uuidString)
            clearReceiveForm()
            await loadBatches()
        } catch {
            receiveError = error.localizedDescription
        }
    }

    /// Reset the Receive form and default its distributor to the one in view.
    func resetReceiveForm() {
        receiveDistributorId = selectedDistributorId ?? distributors.first?.id
        clearReceiveForm()
        receiveError = nil
    }

    private func clearReceiveForm() {
        receiveSkuId = nil
        receiveQty = 1
        receiveBatchNo = ""
        includeExpiry = false
        receiveExpiry = Date()
        includeMfg = false
        receiveMfg = Date()
        receiveUnitCost = ""
        receiveReference = ""
    }

    static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Root

struct StockBatchesView: View {
    @StateObject private var vm = StockBatchesViewModel()
    @State private var showReceive = false

    private let statuses = ["all", "active", "near_expiry", "expired"]

    var body: some View {
        Group {
            if !vm.didLoad {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .navigationTitle("Stock & Batches")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Receive (GRN) — STRICT distribution_receiving gate. Only reps whose
            // org explicitly holds the module see the control; empty legacy
            // sessions never do.
            if ClientFeatures.hasDistributionReceiving {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.resetReceiveForm()
                        showReceive = true
                    } label: {
                        Label("Receive", systemImage: "plus.circle")
                    }
                }
            }
        }
        .task { if !vm.didLoad { await vm.load() } }
        .sheet(isPresented: $showReceive) { ReceiveBatchSheet(vm: vm) }
    }

    private var list: some View {
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
                alertsSection
                Section {
                    Picker("Status", selection: Binding(
                        get: { vm.statusFilter },
                        set: { s in Task { await vm.setStatus(s) } }
                    )) {
                        ForEach(statuses, id: \.self) { s in
                            Text(statusLabel(s)).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Batches — soonest expiry first") {
                    if vm.loadingBatches {
                        ProgressView()
                    } else if vm.batches.isEmpty {
                        Text(emptyMessage).font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(vm.batches) { batch in
                            batchRow(batch)
                                .listRowBackground(batch.status == "expired" ? Color.red.opacity(0.06) : nil)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.loadBatches() }
    }

    // ── Expiry alerts summary ──────────────────────────────────────────────
    @ViewBuilder
    private var alertsSection: some View {
        if let counts = vm.alerts?.counts {
            Section("Expiry alerts") {
                if counts.near_expiry == 0 && counts.expired == 0 {
                    Label("No near-expiry or expired batches.", systemImage: "checkmark.seal")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    HStack(spacing: 12) {
                        alertPill("Near expiry", counts.near_expiry, .orange)
                        alertPill("Expired", counts.expired, .red)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(counts.total)").font(.subheadline).bold()
                            Text("batches").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func alertPill(_ label: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title3).bold().foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(minWidth: 68)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ── Batch row ──────────────────────────────────────────────────────────
    private func batchRow(_ b: StockBatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.sku_name ?? b.sku_code ?? b.sku_id).font(.subheadline).bold()
                    let sub = [b.sku_code, b.batch_no.map { "Batch \($0)" }].compactMap { $0 }.joined(separator: " · ")
                    if !sub.isEmpty {
                        Text(sub).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                statusPill(b.status)
            }
            HStack {
                let exp = expiryText(b)
                Text(exp.0).font(.caption).foregroundColor(exp.1)
                Spacer()
                Text("Rem \(batchFmt(b.qty_remaining))  ·  Recd \(batchFmt(b.qty_received))")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusPill(_ s: String) -> some View {
        let color: Color
        switch s {
        case "active":      color = .green
        case "near_expiry": color = .orange
        case "expired":     color = .red
        default:            color = .gray
        }
        return Text(s.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    /// Expiry line + days-to-expiry, coloured by urgency.
    private func expiryText(_ b: StockBatch) -> (String, Color) {
        guard let exp = b.expiry_date else { return ("No expiry", .secondary) }
        let date = String(exp.prefix(10))
        guard let d = b.days_to_expiry else { return ("Exp \(date)", .secondary) }
        if d < 0 { return ("Expired \(date) · \(-d)d ago", .red) }
        if b.status == "near_expiry" { return ("Exp \(date) · \(d)d left", .orange) }
        return ("Exp \(date) · \(d)d left", .secondary)
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "all":         return "All"
        case "near_expiry": return "Near"
        default:            return s.capitalized
        }
    }

    private var emptyMessage: String {
        switch vm.statusFilter {
        case "near_expiry": return "No near-expiry batches."
        case "expired":     return "No expired batches."
        case "active":      return "No active batches."
        default:            return "No batches for this distributor."
        }
    }
}

// MARK: - Receive (GRN) form (sheet)

private struct ReceiveBatchSheet: View {
    @ObservedObject var vm: StockBatchesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSkuPicker = false

    private let brandRed = Brand.red

    var body: some View {
        NavigationStack {
            Form {
                if let err = vm.receiveError {
                    Section { Text(err).font(.caption).foregroundColor(.red) }
                }
                Section {
                    Text("Receive stock into a distributor (goods receipt). This opens a new batch — or tops up an existing one — and updates on-hand stock.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("Distributor") {
                    if vm.distributors.isEmpty {
                        Text("No distributors available. Ask your administrator to enable distributor access.")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Picker("Distributor", selection: Binding(
                            get: { vm.receiveDistributorId ?? "" },
                            set: { vm.receiveDistributorId = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Select…").tag("")
                            ForEach(vm.distributors) { d in
                                Text(d.name ?? d.code ?? d.id).tag(d.id)
                            }
                        }
                    }
                }
                Section("SKU") {
                    Button { showSkuPicker = true } label: {
                        HStack {
                            Label(vm.receiveSku == nil
                                  ? "Select SKU"
                                  : (vm.receiveSku?.name ?? vm.receiveSku?.sku_code ?? "SKU"),
                                  systemImage: "shippingbox")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    if let sku = vm.receiveSku, let code = sku.sku_code {
                        Text(code).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Section("Quantity received") {
                    Stepper(value: $vm.receiveQty, in: 1...99999) {
                        Text("\(vm.receiveQty)").font(.subheadline).bold()
                    }
                }
                Section("Batch (optional)") {
                    TextField("Batch no.", text: $vm.receiveBatchNo)
                }
                Section("Expiry (optional)") {
                    Toggle("Has expiry date", isOn: $vm.includeExpiry)
                    if vm.includeExpiry {
                        DatePicker("Expiry date", selection: $vm.receiveExpiry, displayedComponents: .date)
                    }
                }
                Section("Manufacture (optional)") {
                    Toggle("Has manufacture date", isOn: $vm.includeMfg)
                    if vm.includeMfg {
                        DatePicker("Mfg date", selection: $vm.receiveMfg, displayedComponents: .date)
                    }
                }
                Section("Unit cost (optional)") {
                    TextField("Unit cost", text: $vm.receiveUnitCost).keyboardType(.decimalPad)
                }
                Section("Reference (optional)") {
                    TextField("GRN / invoice reference", text: $vm.receiveReference)
                }
                Section {
                    Button(vm.receiving ? "Receiving…" : "Receive Stock") {
                        Task {
                            await vm.submitReceive()
                            if vm.receiveError == nil { dismiss() }
                        }
                    }
                    .disabled(vm.receiving || vm.receiveDistributorId == nil || vm.receiveSkuId == nil)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .listRowBackground(brandRed)
                }
            }
            .navigationTitle("Receive (GRN)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showSkuPicker) { ReceiveSkuPickerSheet(vm: vm) }
        }
    }
}

// MARK: - SKU picker (searchable, single-select)

private struct ReceiveSkuPickerSheet: View {
    @ObservedObject var vm: StockBatchesViewModel
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
                                           description: Text("No SKUs are available."))
                } else if filtered.isEmpty {
                    ContentUnavailableView("No matches", systemImage: "magnifyingglass",
                                           description: Text("No SKUs match “\(query)”."))
                }
            }
            .navigationTitle("Select SKU")
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
        Button {
            vm.receiveSkuId = sku.id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sku.name ?? sku.sku_code ?? sku.id).font(.subheadline).bold()
                    Text([sku.sku_code, sku.category].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                if vm.receiveSkuId == sku.id {
                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// Trim a whole-value Double to an integer string; keep one decimal otherwise.
private func batchFmt(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}
