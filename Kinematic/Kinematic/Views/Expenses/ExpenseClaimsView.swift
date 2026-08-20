import SwiftUI
import UIKit
// Combine is not re-exported by SwiftUI on the Xcode 26 toolchain.
import Combine

// MARK: - View model (shared by claims + approvals views)

@MainActor
final class ExpensesViewModel: ObservableObject {
    @Published var policy: ExpensePolicy?
    @Published var claims: [ExpenseClaim] = []
    @Published var pending: [ExpenseClaim] = []
    @Published var didLoad = false
    @Published var submitting = false
    @Published var busyIds: Set<String> = []
    @Published var errorMsg: String?

    private let api = ExpensesAPI.shared

    // ── Claims ──────────────────────────────────────────────────────────────
    func loadClaims() async {
        errorMsg = nil
        if policy == nil { policy = try? await api.policy() }
        do { claims = try await api.myClaims() }
        catch { errorMsg = error.localizedDescription }
        didLoad = true
    }

    func createClaim(title: String?, items: [ExpenseClaimItemInput]) async -> Bool {
        submitting = true; errorMsg = nil
        defer { submitting = false }
        do { _ = try await api.createClaim(ExpenseClaimInput(title: title, items: items)); await loadClaims(); return true }
        catch { errorMsg = error.localizedDescription; return false }
    }

    func submit(id: String) async {
        busyIds.insert(id); defer { busyIds.remove(id) }
        do { _ = try await api.submit(id: id); await loadClaims() }
        catch { errorMsg = error.localizedDescription }
    }

    func cancel(id: String) async {
        busyIds.insert(id); defer { busyIds.remove(id) }
        do { try await api.cancel(id: id); await loadClaims() }
        catch { errorMsg = error.localizedDescription }
    }

    func scanReceipt(base64: String, mediaType: String) async -> ExpenseReceiptFields? {
        do { return try await api.scanReceipt(imageBase64: base64, mediaType: mediaType) }
        catch { errorMsg = "Couldn't read the receipt."; return nil }
    }

    func mileage(fromISO: String, toISO: String) async -> ExpenseMileageResult? {
        do { return try await api.mileage(fromISO: fromISO, toISO: toISO) }
        catch { errorMsg = "Couldn't compute mileage."; return nil }
    }

    // ── Approvals ───────────────────────────────────────────────────────────
    func loadPending() async {
        errorMsg = nil
        do { pending = try await api.pendingClaims() }
        catch { errorMsg = error.localizedDescription }
        didLoad = true
    }

    func decide(id: String, decision: String, note: String?) async {
        busyIds.insert(id); defer { busyIds.remove(id) }
        do {
            try await api.decide(id: id, decision: decision, note: note)
            pending.removeAll { $0.id == id }   // optimistic
        } catch { errorMsg = error.localizedDescription }
    }
}

// Shared formatting helpers.
func expenseMoney(_ v: Double, _ currency: String) -> String {
    let n = (v == v.rounded()) ? String(Int(v)) : String(format: "%.2f", v)
    return currency == "INR" ? "₹\(n)" : "\(currency) \(n)"
}
func expenseStatusColor(_ status: String?) -> Color {
    switch (status ?? "draft").lowercased() {
    case "approved": return .green
    case "submitted": return .orange
    case "rejected": return .red
    case "reimbursed": return .blue
    default: return .gray
    }
}
let expenseCategories = ExpenseCategory.allCases.map { $0.rawValue }
let expenseDayFmt: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; return f
}()

// MARK: - Claims list

struct ExpenseClaimsView: View {
    @StateObject private var vm = ExpensesViewModel()
    @State private var showCreate = false

    var body: some View {
        Group {
            if !vm.didLoad {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let err = vm.errorMsg {
                        Section { Text(err).font(.caption).foregroundColor(.red) }
                    }
                    if vm.claims.isEmpty {
                        Section { Text("No claims yet. Tap + to file one.").font(.caption).foregroundColor(.secondary) }
                    } else {
                        Section("My Claims") {
                            ForEach(vm.claims) { claim in ClaimRow(claim: claim, vm: vm) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") } } }
        .task { if !vm.didLoad { await vm.loadClaims() } }
        .sheet(isPresented: $showCreate) { NewClaimSheet(vm: vm) }
    }
}

private struct ClaimRow: View {
    let claim: ExpenseClaim
    @ObservedObject var vm: ExpensesViewModel

    var body: some View {
        let status = (claim.status ?? "draft").lowercased()
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(claim.title ?? claim.claim_no ?? "Expense claim").font(.subheadline).bold()
                Spacer()
                Text(claim.statusLabel).font(.caption2).bold()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(expenseStatusColor(claim.status).opacity(0.15))
                    .foregroundColor(expenseStatusColor(claim.status)).clipShape(Capsule())
            }
            Text(expenseMoney(claim.total_amount, claim.currency)
                 + (status == "submitted" && claim.approver_name != nil ? " · with \(claim.approver_name!) (L\(claim.current_level ?? 1))" : ""))
                .font(.caption).foregroundColor(.secondary)
            if let s = claim.ai_summary, !s.isEmpty {
                Text("🧠 \(s)").font(.caption2).foregroundColor(.secondary)
            }
            if let flags = claim.ai_flags, !flags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(flags.prefix(4)) { f in
                        Text(f.code.replacingOccurrences(of: "_", with: " "))
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().stroke(flagColor(f.severity), lineWidth: 1))
                            .foregroundColor(flagColor(f.severity))
                    }
                }
            }
            if status == "rejected", let note = claim.review_note, !note.isEmpty {
                Text("Rejected: \(note)").font(.caption2).foregroundColor(.red)
            }
            if status == "draft" || status == "submitted" {
                HStack {
                    Spacer()
                    if status == "draft" {
                        Button("Submit") { Task { await vm.submit(id: claim.id) } }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(vm.busyIds.contains(claim.id))
                    }
                    Button(status == "draft" ? "Cancel" : "Withdraw", role: .destructive) {
                        Task { await vm.cancel(id: claim.id) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(vm.busyIds.contains(claim.id))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func flagColor(_ severity: String?) -> Color {
        switch severity { case "high": return .red; case "warn": return .orange; default: return .blue }
    }
}

// MARK: - New claim sheet

private struct ClaimLineDraft: Identifiable {
    let id = UUID()
    var category: String = "food"
    var itemDate: Date = Date()
    var amount: String = ""
    var merchant: String = ""
    var desc: String = ""
    var fromLocation: String = ""
    var toLocation: String = ""
    var distanceKm: String = ""
    var scanning = false
    var suggesting = false
}

private struct NewClaimSheet: View {
    @ObservedObject var vm: ExpensesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var lines: [ClaimLineDraft] = [ClaimLineDraft()]
    @State private var pickedImage: UIImage?
    @State private var showPicker = false
    @State private var scanIndex: Int?

    private var currency: String { vm.policy?.currency ?? "INR" }
    private var total: Double { lines.reduce(0) { $0 + (Double($1.amount) ?? 0) } }

    var body: some View {
        NavigationStack {
            Form {
                if let err = vm.errorMsg { Section { Text(err).font(.caption).foregroundColor(.red) } }
                Section { TextField("Title (optional)", text: $title) }
                if let p = vm.policy {
                    Section {
                        Text("Mileage \(expenseMoney(p.mileage_rate, currency))/km · receipt required over \(expenseMoney(p.require_receipt_over, currency))"
                             + (p.escalate_over.map { " · escalates over \(expenseMoney($0, currency))" } ?? ""))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                ForEach($lines) { $line in
                    Section {
                        Picker("Category", selection: $line.category) {
                            ForEach(expenseCategories, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                        DatePicker("Date", selection: $line.itemDate, displayedComponents: .date)
                        if line.category == "mileage" {
                            TextField("From", text: $line.fromLocation)
                            TextField("To", text: $line.toLocation)
                            HStack {
                                TextField("Distance km", text: $line.distanceKm).keyboardType(.decimalPad)
                                Button { suggestMileage(for: line.id) } label: {
                                    if line.suggesting { ProgressView() } else { Label("GPS", systemImage: "location.fill") }
                                }.buttonStyle(.bordered).controlSize(.small).disabled(line.suggesting)
                            }
                            TextField("Amount", text: $line.amount).keyboardType(.decimalPad)
                        } else {
                            TextField("Merchant", text: $line.merchant)
                            HStack {
                                TextField("Amount", text: $line.amount).keyboardType(.decimalPad)
                                Button { scanReceipt(for: line.id) } label: {
                                    if line.scanning { ProgressView() } else { Label("Scan", systemImage: "doc.viewfinder") }
                                }.buttonStyle(.bordered).controlSize(.small).disabled(line.scanning)
                            }
                            TextField("Description (optional)", text: $line.desc)
                        }
                        if lines.count > 1 {
                            Button("Remove line", role: .destructive) { lines.removeAll { $0.id == line.id } }
                        }
                    }
                }
                Section {
                    Button { lines.append(ClaimLineDraft()) } label: { Label("Add line", systemImage: "plus") }
                    HStack { Text("Total").bold(); Spacer(); Text(expenseMoney(total, currency)).bold() }
                }
                Section {
                    Button(vm.submitting ? "Saving…" : "Create draft") { Task { await create() } }
                        .disabled(vm.submitting || !hasValidLine)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("New Claim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showPicker, onDismiss: handlePicked) {
                ImagePicker(image: $pickedImage, sourceType: .camera, cameraDevice: .rear)
            }
        }
    }

    private var hasValidLine: Bool {
        lines.contains { (Double($0.amount) ?? 0) > 0 || ($0.category == "mileage" && (Double($0.distanceKm) ?? 0) > 0) }
    }

    private func create() async {
        let items: [ExpenseClaimItemInput] = lines.compactMap { l in
            let amt = Double(l.amount) ?? 0
            let dist = Double(l.distanceKm)
            if amt <= 0 && !(l.category == "mileage" && (dist ?? 0) > 0) { return nil }
            return ExpenseClaimItemInput(
                category: l.category,
                item_date: expenseDayFmt.string(from: l.itemDate),
                description: l.desc.isEmpty ? nil : l.desc,
                amount: amt,
                distance_km: l.category == "mileage" ? dist : nil,
                from_location: l.fromLocation.isEmpty ? nil : l.fromLocation,
                to_location: l.toLocation.isEmpty ? nil : l.toLocation,
                merchant: l.merchant.isEmpty ? nil : l.merchant,
                receipt_url: nil
            )
        }
        guard !items.isEmpty else { return }
        if await vm.createClaim(title: title.isEmpty ? nil : title, items: items) { dismiss() }
    }

    // ── receipt scan ──
    private func scanReceipt(for id: UUID) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        scanIndex = idx
        lines[idx].scanning = true
        showPicker = true
    }

    private func handlePicked() {
        guard let idx = scanIndex else { return }
        guard let image = pickedImage else { if lines.indices.contains(idx) { lines[idx].scanning = false }; return }
        pickedImage = nil
        Task {
            guard let data = KinematicRepository.compressForUpload(image, maxDim: 1024, targetKB: 1500), !data.isEmpty else {
                if lines.indices.contains(idx) { lines[idx].scanning = false }; return
            }
            let fields = await vm.scanReceipt(base64: data.base64EncodedString(), mediaType: "image/jpeg")
            guard lines.indices.contains(idx) else { return }
            lines[idx].scanning = false
            if let f = fields {
                if let a = f.amount { lines[idx].amount = (a == a.rounded()) ? String(Int(a)) : String(format: "%.2f", a) }
                if let m = f.merchant, !m.isEmpty { lines[idx].merchant = m }
                if let c = f.category, expenseCategories.contains(c) { lines[idx].category = c }
                if let d = f.txn_date, let parsed = expenseDayFmt.date(from: String(d.prefix(10))) { lines[idx].itemDate = parsed }
            }
        }
    }

    // ── GPS mileage ──
    private func suggestMileage(for id: UUID) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[idx].suggesting = true
        let day = expenseDayFmt.string(from: lines[idx].itemDate)
        Task {
            let m = await vm.mileage(fromISO: "\(day)T00:00:00.000Z", toISO: "\(day)T23:59:59.999Z")
            guard lines.indices.contains(idx) else { return }
            lines[idx].suggesting = false
            if let m = m {
                lines[idx].distanceKm = (m.distance_km == m.distance_km.rounded()) ? String(Int(m.distance_km)) : String(format: "%.1f", m.distance_km)
                lines[idx].amount = (m.suggested_amount == m.suggested_amount.rounded()) ? String(Int(m.suggested_amount)) : String(format: "%.2f", m.suggested_amount)
                if lines[idx].desc.isEmpty { lines[idx].desc = "Auto: \(lines[idx].distanceKm) km from GPS trail" }
            }
        }
    }
}
