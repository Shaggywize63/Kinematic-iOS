import SwiftUI

/// Record a collection from an outlet.
///
///  - `outletId` empty → no outlet preselected: the outlet picker opens first (Collect Payment from the side menu).
///  - Once an outlet is known, its outstanding balance and open invoices load (online only; offline shows a muted
///    "Outstanding unavailable offline"). Recording does NOT wait for or need this.
///  - By default the server allocates the amount to the oldest open invoices (`auto_allocate = true`); the switch keeps
///    it "on account" instead (`auto_allocate = false`, no invoices).
///  - The payment is saved on the phone first under ONE Idempotency-Key (kept for every retry) and sent; with no
///    connection it stays queued and is uploaded when online ("Saved — will upload when online"). A final refusal from
///    the server is shown here and nothing is kept.
///  - GPS is the rep's current fix when available, otherwise omitted.
struct PaymentCollectView: View {
    let outletId: String
    let outletName: String?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cache = OrderCache.shared

    @State private var pickedId: String
    @State private var pickedName: String
    @State private var showPicker: Bool

    @State private var mode: String = "cash"
    @State private var amount: String = ""
    @State private var reference: String = ""
    @State private var chequeBank: String = ""
    @State private var chequeImageURL: String? = nil
    /// true = leave the whole amount on account; false (default) = the server allocates to the oldest open invoices.
    @State private var onAccount = false
    @State private var errorMsg: String? = nil
    @State private var busy = false

    @State private var outstanding: OutstandingResult? = nil
    @State private var outstandingLoading = false

    // ONE Idempotency-Key per payment, made here and reused by every retry; a refused submit spends it.
    @State private var draftKey: String = DistributionQueuePolicy.newKey(prefix: DistributionQueuePolicy.paymentKeyPrefix)
    @State private var doneMessage: String = ""
    @State private var showDone = false

    private let modes = ["cash", "upi", "cheque", "credit_adjustment"]

    init(outletId: String, outletName: String?) {
        self.outletId = outletId
        self.outletName = outletName
        _pickedId = State(initialValue: outletId)
        _pickedName = State(initialValue: outletName ?? "")
        _showPicker = State(initialValue: outletId.isEmpty)
    }

    var body: some View {
        Form {
            queueBanner
            outletSection
            if !pickedId.isEmpty { outstandingSection }
            modeSection
            amountSection
            allocationSection
            if mode == "cheque" { chequeSection }
            if let message = errorMsg {
                Section { Text(message).font(.caption).foregroundColor(.red) }
            }
            submitSection
        }
        .navigationTitle("Collect Payment")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            OutletPickerView(onPick: { outlet in
                pickedId = outlet.id
                pickedName = OutletPickerLogic.displayName(outlet)
                showPicker = false
                errorMsg = nil
            })
        }
        .task(id: pickedId) { await loadOutstanding() }
        .alert("Payment", isPresented: $showDone) {
            Button("OK") { dismiss() }
        } message: {
            Text(doneMessage)
        }
    }

    // MARK: - Sections

    /// Orders / payments / returns saved on the phone and waiting (or refused) — tap to review them.
    @ViewBuilder private var queueBanner: some View {
        let summary = DistributionQueuePolicy.summary(of: cache.queueItemsForCurrentUser())
        if let line = DistributionQueuePolicy.summaryLine(summary) {
            Section {
                NavigationLink(destination: OrderHistoryView()) {
                    Text(line)
                        .font(.caption)
                        .foregroundColor(summary.failed > 0 ? Color.red : Color.orange)
                }
            }
        }
    }

    private var outletSection: some View {
        Section("Outlet") {
            HStack {
                Text(pickedName.isEmpty ? "No outlet chosen" : pickedName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(pickedId.isEmpty ? "Choose outlet" : "Change") { showPicker = true }
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder private var outstandingSection: some View {
        Section("Outstanding") {
            if outstandingLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking outstanding…").font(.caption).foregroundColor(.secondary)
                }
            } else if let loaded = outstanding?.loadedValue {
                outstandingDetail(loaded)
            } else if outstanding?.isOffline == true {
                Text("Outstanding unavailable offline").font(.caption).foregroundColor(.secondary)
            } else {
                Text("Outstanding unavailable").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder private func outstandingDetail(_ loaded: OutletOutstanding) -> some View {
        let invoices = loaded.openInvoices
        let balance: Double = loaded.balance ?? invoices.reduce(0.0) { (sum: Double, inv: OpenInvoice) -> Double in sum + (inv.balance ?? 0) }
        Text(DistributionMoney.rupees(balance)).font(.title3.bold())
        if let limit = loaded.creditLimit {
            Text("Credit limit " + DistributionMoney.rupees(limit)).font(.caption).foregroundColor(.secondary)
        }
        if invoices.isEmpty {
            Text("No open invoices").font(.caption).foregroundColor(.secondary)
        } else {
            Text("Open invoices (\(invoices.count))").font(.caption).foregroundColor(.secondary)
            ForEach(Array(invoices.prefix(Self.openInvoicesShown))) { inv in
                invoiceRow(inv)
            }
            if invoices.count > Self.openInvoicesShown {
                Text("+ \(invoices.count - Self.openInvoicesShown) more").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private static let openInvoicesShown = 5

    private func invoiceRow(_ inv: OpenInvoice) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(inv.invoiceNo ?? String(inv.invoiceId.prefix(8))).font(.subheadline)
                let dates = invoiceDates(inv)
                if !dates.isEmpty {
                    Text(dates).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(DistributionMoney.rupees(inv.balance)).font(.subheadline.weight(.semibold))
        }
    }

    private func invoiceDates(_ inv: OpenInvoice) -> String {
        var parts: [String] = []
        if let date = inv.invoiceDate, !date.isEmpty { parts.append(String(date.prefix(10))) }
        if let due = inv.dueDate, !due.isEmpty { parts.append("due " + String(due.prefix(10))) }
        return parts.joined(separator: " · ")
    }

    private var modeSection: some View {
        Section("Mode") {
            Picker("Mode", selection: $mode) {
                ForEach(modes, id: \.self) { m in Text(DistributionQueuePolicy.modeLabel(m)).tag(m) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var amountSection: some View {
        Section("Amount") {
            TextField("₹", text: $amount)
                .keyboardType(.decimalPad)
                .onChange(of: amount) { _, newValue in
                    let cleaned = PaymentAllocation.sanitizeAmountInput(newValue)
                    if cleaned != newValue { amount = cleaned }
                }
            TextField(referenceLabel, text: $reference)
        }
    }

    private var referenceLabel: String {
        switch mode {
        case "upi": return "UPI transaction ID"
        case "cheque": return "Cheque number"
        default: return "Reference (optional)"
        }
    }

    /// "Apply to open invoices" (default) or keep the whole amount on account, with an estimate of where it lands.
    private var allocationSection: some View {
        Section {
            Toggle(isOn: Binding(get: { !onAccount }, set: { onAccount = !$0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apply to open invoices").font(.subheadline.weight(.semibold))
                    Text(onAccount ? "Off — the whole amount stays on account"
                                   : "On — oldest invoices first, the rest stays on account")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if !onAccount, let parsed = PaymentAllocation.parseAmount(amount), let loaded = outstanding?.loadedValue {
                allocationPreview(PaymentAllocation.preview(amount: parsed, invoices: loaded.openInvoices))
            }
        }
    }

    @ViewBuilder private func allocationPreview(_ preview: PaymentAllocation.Preview) -> some View {
        ForEach(Array(preview.lines.prefix(3)), id: \.invoiceId) { line in
            Text(DistributionMoney.rupees(line.amount) + " → " + (line.invoiceNo ?? String(line.invoiceId.prefix(8))))
                .font(.caption)
        }
        if preview.lines.count > 3 {
            Text("+ \(preview.lines.count - 3) more invoices").font(.caption).foregroundColor(.secondary)
        }
        if preview.onAccount > 0 {
            Text(DistributionMoney.rupees(preview.onAccount) + " stays on account").font(.caption).foregroundColor(.secondary)
        }
    }

    private var chequeSection: some View {
        Section("Cheque") {
            TextField("Bank", text: $chequeBank)
            DistributionPhotoRow(kind: "cheque", attachedTitle: "Cheque image attached", missingTitle: "Add photo of cheque",
                                 hint: "Required for cheque payments", url: $chequeImageURL)
        }
    }

    private var submitSection: some View {
        Section {
            Button(busy ? "Saving…" : "Record Payment") { record() }
                .disabled(busy)
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .listRowBackground(Color(red: 208/255, green: 30/255, blue: 44/255))
        }
    }

    // MARK: - Actions

    private func loadOutstanding() async {
        outstanding = nil
        outstandingLoading = false
        if pickedId.isEmpty { return }
        outstandingLoading = true
        let result = await DistributionAPI.shared.outstanding(outletId: pickedId)
        if Task.isCancelled { return }
        outstanding = result
        outstandingLoading = false
    }

    private func record() {
        if busy { return }
        if let problem = PaymentAllocation.validate(outletId: pickedId, amountText: amount, mode: mode,
                                                    hasChequeImage: chequeImageURL != nil) {
            errorMsg = problem
            return
        }
        guard let amt = PaymentAllocation.parseAmount(amount) else { return }
        busy = true
        errorMsg = nil
        let key = draftKey
        let outlet = pickedId
        let name: String? = pickedName.isEmpty ? nil : pickedName
        let selectedMode = mode
        let ref: String? = reference.isEmpty ? nil : reference
        let bank: String? = chequeBank.isEmpty ? nil : chequeBank
        let image = chequeImageURL
        let choice: PaymentAllocation.Choice = onAccount ? .onAccount : .autoAllocate
        Task {
            // The rep's current fix, or nil (permission off, no fix in a few seconds): never blocks recording.
            var gps: GeoPoint? = nil
            if let fix = await CurrentLocationProvider.oneShot(timeout: 4) {
                gps = GeoPoint(lat: fix.lat, lng: fix.lng)
            }
            let base = PaymentInput(outlet_id: outlet, mode: selectedMode, amount: amt, reference: ref, cheque_bank: bank,
                                    cheque_date: nil, cheque_image_url: image, applied_to_invoices: nil, gps: gps)
            let outcome = await DistributionSync.shared.recordPayment(input: base, payload: PaymentAllocation.payload(choice: choice),
                                                                      outletName: name, idempotencyKey: key)
            busy = false
            switch outcome {
            case .synced(_, let number, let detail):
                var lines: [String] = ["Payment recorded" + (number.map { " · " + $0 } ?? "")]
                if let detail = detail { lines.append(detail) }
                doneMessage = lines.joined(separator: "\n")
                showDone = true
            case .queued:
                doneMessage = DistributionQueuePolicy.savedMessage
                showDone = true
            case .rejected(let message):
                // The server refused it: that key is spent, so a corrected payment goes out under a new one.
                errorMsg = message
                draftKey = DistributionQueuePolicy.newKey(prefix: DistributionQueuePolicy.paymentKeyPrefix)
            }
        }
    }
}
