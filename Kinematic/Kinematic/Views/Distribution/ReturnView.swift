import SwiftUI

struct ReturnView: View {
    let outletId: String
    let originalInvoiceId: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cache = OrderCache.shared

    @State private var reasonCode: String = "damaged"
    @State private var skuId: String = ""
    @State private var qty: String = "1"
    @State private var notes: String = ""
    @State private var photoUrls: [String] = []
    @State private var msg: String?
    @State private var busy = false

    private let reasons = ["damaged", "near_expiry", "wrong_sku", "trade_return"]

    var body: some View {
        Form {
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
                Button {
                    // Real flow: launch camera + /uploads/sign + persist URL.
                    photoUrls.append("https://placeholder.local/distribution/return/\(UUID().uuidString).jpg")
                } label: {
                    Label(photoUrls.isEmpty ? "Photo of damaged stock required" : "\(photoUrls.count) photo(s) attached",
                          systemImage: photoUrls.isEmpty ? "camera" : "checkmark.seal")
                        .foregroundColor(photoUrls.isEmpty ? .red : .green)
                }
            }
            if let msg = msg {
                Section { Text(msg).font(.caption).foregroundColor(.red) }
            }
            Section {
                Button(busy ? "Saving…" : "Submit Return") { submit() }
                    .disabled(busy || photoUrls.isEmpty || skuId.isEmpty)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .listRowBackground(Color(red: 208/255, green: 30/255, blue: 44/255))
            }
        }
        .navigationTitle("Return Goods")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        guard let q = Int(qty), q > 0 else { msg = "Qty required"; return }
        busy = true; msg = nil
        let input = ReturnInput(
            outlet_id: outletId,
            original_invoice_id: originalInvoiceId,
            reason_code: reasonCode,
            reason_notes: notes.isEmpty ? nil : notes,
            photo_urls: photoUrls,
            items: [ReturnLineInput(sku_id: skuId, qty: q, condition: reasonCode == "damaged" ? "damaged" : "saleable", original_invoice_item_id: nil)],
            gps: nil
        )
        let pending = cache.enqueueReturn(input)
        Task {
            do {
                _ = try await DistributionAPI.shared.submitReturn(input, idempotencyKey: pending.idempotencyKey)
                cache.markReturnSynced(pending.id)
                await MainActor.run { dismiss() }
            } catch {
                cache.recordReturnError(pending.id, error: error.localizedDescription)
                await MainActor.run { msg = "Queued — will sync when online."; busy = false }
            }
        }
    }
}
