import SwiftUI

struct PaymentCollectView: View {
    let outletId: String
    let outletName: String?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cache = OrderCache.shared

    @State private var mode: String = "cash"
    @State private var amount: String = ""
    @State private var reference: String = ""
    @State private var chequeBank: String = ""
    @State private var chequeImageURL: String?
    @State private var msg: String?
    @State private var busy = false

    private let modes = ["cash", "upi", "cheque", "credit_adjustment"]

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $mode) {
                    ForEach(modes, id: \.self) { m in Text(m.replacingOccurrences(of: "_", with: " ")).tag(m) }
                }.pickerStyle(.segmented)
            }
            Section("Amount") {
                TextField("₹", text: $amount).keyboardType(.decimalPad)
            }
            Section("Reference") {
                TextField(referenceLabel, text: $reference)
            }
            if mode == "cheque" {
                Section("Cheque") {
                    TextField("Bank", text: $chequeBank)
                    Button {
                        // Real flow: present camera, upload via /uploads/sign, store URL.
                        // Stub: drop a placeholder so the flow proceeds for testing.
                        chequeImageURL = "https://placeholder.local/distribution/cheque/\(UUID().uuidString).jpg"
                    } label: {
                        Label(chequeImageURL == nil ? "Capture cheque photo" : "Cheque image attached",
                              systemImage: chequeImageURL == nil ? "camera" : "checkmark.seal")
                            .foregroundColor(chequeImageURL == nil ? Color.red : Color.green)
                    }
                }
            }
            if let msg = msg {
                Section { Text(msg).font(.caption).foregroundColor(.red) }
            }
            Section {
                Button(busy ? "Saving…" : "Record Payment") { record() }
                    .disabled(busy || amount.isEmpty || (mode == "cheque" && chequeImageURL == nil))
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .listRowBackground(Color(red: 208/255, green: 30/255, blue: 44/255))
            }
        }
        .navigationTitle("Collect Payment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var referenceLabel: String {
        switch mode { case "upi": return "UPI Txn ID"; case "cheque": return "Cheque Number"; default: return "Reference (optional)" }
    }

    private func record() {
        guard let amt = Double(amount), amt > 0 else { msg = "Enter a valid amount"; return }
        if mode == "cheque", chequeImageURL == nil { msg = "Cheque image is required"; return }
        busy = true; msg = nil
        let input = PaymentInput(
            outlet_id: outletId, mode: mode, amount: amt,
            reference: reference.isEmpty ? nil : reference,
            cheque_bank: chequeBank.isEmpty ? nil : chequeBank,
            cheque_date: nil,
            cheque_image_url: chequeImageURL,
            applied_to_invoices: nil,
            gps: nil
        )
        let pending = cache.enqueuePayment(input)
        Task {
            do {
                _ = try await DistributionAPI.shared.submitPayment(input, idempotencyKey: pending.idempotencyKey)
                cache.markPaymentSynced(pending.id)
                await MainActor.run { dismiss() }
            } catch {
                cache.recordPaymentError(pending.id, error: error.localizedDescription)
                await MainActor.run { msg = "Queued — will sync when online."; busy = false }
            }
        }
    }
}
