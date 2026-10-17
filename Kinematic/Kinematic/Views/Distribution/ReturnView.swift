import SwiftUI

struct ReturnView: View {
    let outletId: String
    let originalInvoiceId: String

    @Environment(\.dismiss) private var dismiss

    @State private var reasonCode: String = "damaged"
    @State private var skuId: String = ""
    @State private var qty: String = "1"
    @State private var notes: String = ""
    @State private var photoUrl: String? = nil
    @State private var msg: String?
    @State private var busy = false
    // ONE Idempotency-Key per submission, reused by every retry; a refused submit spends it.
    @State private var draftKey: String = DistributionQueuePolicy.newKey(prefix: DistributionQueuePolicy.returnKeyPrefix)
    @State private var doneMessage: String = ""
    @State private var showDone = false

    // A return is booked against one company's invoice, so a rep who sells for several chooses it first.
    @StateObject private var companyVm = DistributionViewModel()
    @State private var companyConfirmed = false
    @State private var changingCompany = false

    private var showCompanyPicker: Binding<Bool> {
        Binding(
            get: { changingCompany || (companyVm.companiesLoaded && companyVm.companyPickRequired && !companyConfirmed) },
            set: { changingCompany = $0 }
        )
    }

    private let reasons = ["damaged", "near_expiry", "wrong_sku", "trade_return"]

    var body: some View {
        Form {
            if companyVm.companyPickRequired, let name = companyVm.activeCompanyName {
                Section {
                    Button { changingCompany = true } label: {
                        HStack {
                            Text("Company").foregroundColor(.secondary)
                            Spacer()
                            Text(name).fontWeight(.semibold)
                            Image(systemName: "chevron.down").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section("Reason") {
                Picker("Reason", selection: $reasonCode) {
                    ForEach(reasons, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section("Item") {
                TextField("SKU ID", text: $skuId)
                TextField("Qty", text: $qty).keyboardType(.numberPad)
                TextField("Notes (optional)", text: $notes)
            }
            Section("Photos") {
                DistributionPhotoRow(kind: "return", attachedTitle: "Photo attached", missingTitle: "Photo of damaged stock required",
                                     hint: "Needed to submit the return", url: $photoUrl)
            }
            if let msg = msg {
                Section { Text(msg).font(.caption).foregroundColor(.red) }
            }
            Section {
                Button(busy ? "Saving…" : "Submit Return") { submit() }
                    .disabled(busy || photoUrl == nil || skuId.isEmpty || !companyConfirmed)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .listRowBackground(Color(red: 208/255, green: 30/255, blue: 44/255))
            }
        }
        .navigationTitle("Return Goods")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await companyVm.loadCompanies()
            if !companyVm.companyPickRequired { companyConfirmed = true }
        }
        .sheet(isPresented: showCompanyPicker) {
            CompanyPickerSheet(companies: companyVm.companies, activeId: companyVm.activeCompanyId, required: !companyConfirmed) { id in
                companyVm.selectCompany(id)
                companyConfirmed = true
                changingCompany = false
            }
        }
        .alert("Return", isPresented: $showDone) {
            Button("OK") { dismiss() }
        } message: {
            Text(doneMessage)
        }
    }

    private func submit() {
        if busy { return }
        guard let q = Int(qty), q > 0 else { msg = "Qty required"; return }
        guard let photo = photoUrl else { msg = "Photo is required"; return }
        busy = true; msg = nil
        let input = ReturnInput(
            outlet_id: outletId,
            original_invoice_id: originalInvoiceId,
            reason_code: reasonCode,
            reason_notes: notes.isEmpty ? nil : notes,
            photo_urls: [photo],
            items: [ReturnLineInput(sku_id: skuId, qty: q, condition: reasonCode == "damaged" ? "damaged" : "saleable", original_invoice_item_id: nil)],
            gps: nil
        )
        let key = draftKey
        Task {
            let outcome = await DistributionSync.shared.recordReturn(input: input, outletName: nil, idempotencyKey: key)
            busy = false
            switch outcome {
            case .synced(_, let number, _):
                doneMessage = "Return submitted" + (number.map { " · " + $0 } ?? "")
                showDone = true
            case .queued:
                doneMessage = DistributionQueuePolicy.savedMessage
                showDone = true
            case .rejected(let message):
                // The server refused it: that key is spent, so a corrected return goes out under a new one.
                msg = message
                draftKey = DistributionQueuePolicy.newKey(prefix: DistributionQueuePolicy.returnKeyPrefix)
            }
        }
    }
}
