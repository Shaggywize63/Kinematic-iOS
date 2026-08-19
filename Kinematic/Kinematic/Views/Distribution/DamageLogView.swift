import SwiftUI
// Combine is NOT re-exported by SwiftUI on the Xcode 26 toolchain — the
// ObservableObject view model below fails to compile without this import.
import Combine

// MARK: - View model

@MainActor
final class DamageLogViewModel: ObservableObject {
    // Pickers.
    @Published var distributors: [DistributorLite] = []
    @Published var skus: [SkuLite] = []
    @Published var selectedDistributorId: String?
    @Published var selectedSkuId: String?

    // Entry form state.
    @Published var qty: Int = 1
    @Published var reason: String = "damaged"
    @Published var batchNo = ""
    @Published var includeExpiry = false
    @Published var expiryDate: Date = Date()
    @Published var unitValue = ""
    @Published var note = ""

    // Recent entries (scoped to the selected distributor once one is chosen).
    @Published var entries: [DamageEntry] = []

    @Published var didLoad = false           // initial pickers + list fetch completed
    @Published var submitting = false
    @Published var errorMsg: String?

    private let api = DistributionAPI.shared

    var selectedSku: SkuLite? {
        guard let id = selectedSkuId else { return nil }
        return skus.first { $0.id == id }
    }

    func refresh() async {
        errorMsg = nil
        // Pickers back the form only; best-effort so a missing / module-gated
        // distributors endpoint never blocks the screen.
        if skus.isEmpty { skus = (try? await api.skus()) ?? [] }
        if distributors.isEmpty { distributors = (try? await api.distributors()) ?? [] }
        await loadEntries()
        didLoad = true
    }

    func loadEntries() async {
        do {
            entries = try await api.damageEntries(distributorId: selectedDistributorId)
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    /// Distributor picker changed — scope the recent-entries list to it.
    func selectDistributor(_ id: String) async {
        selectedDistributorId = id.isEmpty ? nil : id
        await loadEntries()
    }

    func submit() async {
        guard let distributorId = selectedDistributorId, !distributorId.isEmpty else {
            errorMsg = "Select a distributor."; return
        }
        guard let skuId = selectedSkuId, !skuId.isEmpty else {
            errorMsg = "Select a SKU."; return
        }
        guard qty > 0 else { errorMsg = "Quantity must be at least 1."; return }
        submitting = true; errorMsg = nil
        defer { submitting = false }

        let expiryString: String? = includeExpiry ? Self.dateFmt.string(from: expiryDate) : nil
        let unit = Double(unitValue.trimmingCharacters(in: .whitespaces))
        let input = DamageEntryInput(
            distributor_id: distributorId,
            sku_id: skuId,
            qty: qty,
            reason: reason,
            batch_no: batchNo.isEmpty ? nil : batchNo,
            expiry_date: expiryString,
            unit_value: unit,
            note: note.isEmpty ? nil : note
        )
        do {
            // Fresh idempotency key per submit — a retry of the SAME tap reuses it,
            // a new tap gets a new one.
            _ = try await api.logDamage(input, idempotencyKey: UUID().uuidString)
            clearForm()
            await loadEntries()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func clearForm() {
        selectedSkuId = nil
        qty = 1
        reason = "damaged"
        batchNo = ""
        includeExpiry = false
        expiryDate = Date()
        unitValue = ""
        note = ""
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

struct DamageLogView: View {
    @StateObject private var vm = DamageLogViewModel()
    @State private var showSkuPicker = false

    private let reasons = ["damaged", "expired", "near_expiry", "breakage", "other"]
    private let brandRed = Color(red: 208/255, green: 30/255, blue: 44/255)

    var body: some View {
        Group {
            if !vm.didLoad {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                form
            }
        }
        .navigationTitle("Log Damage")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !vm.didLoad { await vm.refresh() } }
        .sheet(isPresented: $showSkuPicker) { DamageSkuPickerSheet(vm: vm) }
    }

    private var form: some View {
        Form {
            if let err = vm.errorMsg {
                Section { Text(err).font(.caption).foregroundColor(.red) }
            }
            Section {
                Text("Log damaged, expired or breakage stock against a distributor. Submitted entries enter the damage register for confirmation and claims.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Distributor") {
                if vm.distributors.isEmpty {
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
            Section("SKU") {
                Button { showSkuPicker = true } label: {
                    HStack {
                        Label(vm.selectedSku == nil
                              ? "Select SKU"
                              : (vm.selectedSku?.name ?? vm.selectedSku?.sku_code ?? "SKU"),
                              systemImage: "shippingbox")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
                if let sku = vm.selectedSku, let code = sku.sku_code {
                    Text(code).font(.caption2).foregroundColor(.secondary)
                }
            }
            Section("Quantity") {
                Stepper(value: $vm.qty, in: 1...9999) {
                    Text("\(vm.qty)").font(.subheadline).bold()
                }
            }
            Section("Reason") {
                Picker("Reason", selection: $vm.reason) {
                    ForEach(reasons, id: \.self) {
                        Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                    }
                }
            }
            Section("Batch (optional)") {
                TextField("Batch no.", text: $vm.batchNo)
            }
            Section("Expiry (optional)") {
                Toggle("Has expiry date", isOn: $vm.includeExpiry)
                if vm.includeExpiry {
                    DatePicker("Expiry date", selection: $vm.expiryDate, displayedComponents: .date)
                }
            }
            Section("Unit value (optional)") {
                TextField("Unit value", text: $vm.unitValue).keyboardType(.decimalPad)
            }
            Section("Note (optional)") {
                TextField("Note", text: $vm.note)
            }
            Section {
                Button(vm.submitting ? "Logging…" : "Log Damage") {
                    Task { await vm.submit() }
                }
                .disabled(vm.submitting || vm.selectedDistributorId == nil || vm.selectedSkuId == nil)
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .listRowBackground(brandRed)
            }
            Section("Recent entries") {
                if vm.entries.isEmpty {
                    Text("No damage entries yet.").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(vm.entries) { entry in entryRow(entry) }
                }
            }
        }
    }

    private func entryRow(_ e: DamageEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(e.sku_name ?? e.sku_code ?? e.sku_id).font(.subheadline).bold()
                Text("Qty \(e.qty)  ·  \(reasonLabel(e.reason))")
                    .font(.caption2).foregroundColor(.secondary)
                if let created = e.created_at {
                    Text(shortDate(created)).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            statusPill(e.status)
        }
        .padding(.vertical, 2)
    }

    private func statusPill(_ s: String) -> some View {
        let color: Color
        switch s {
        case "logged":      color = .orange
        case "confirmed":   color = .blue
        case "claimed":     color = .green
        case "written_off": color = .gray
        case "rejected":    color = .red
        default:            color = .gray
        }
        return Text(s.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func reasonLabel(_ r: String) -> String {
        r.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // The GET row's created_at is an ISO / SQL timestamp; the leading 10 chars
    // are the YYYY-MM-DD date, which is all the list needs to show.
    private func shortDate(_ iso: String) -> String { String(iso.prefix(10)) }
}

// MARK: - SKU picker (searchable, single-select)

private struct DamageSkuPickerSheet: View {
    @ObservedObject var vm: DamageLogViewModel
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
            vm.selectedSkuId = sku.id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sku.name ?? sku.sku_code ?? sku.id).font(.subheadline).bold()
                    Text([sku.sku_code, sku.category].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                if vm.selectedSkuId == sku.id {
                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
