import SwiftUI

/// Lead → opportunity conversion sheet. Mirrors web `LeadConvertModal.tsx`:
/// the rep picks whether to spin up a contact / account / deal, names the
/// deal, optionally sizes it via rupees or a product picker.
///
/// Volume (kg) is omitted on mobile until iOS Product carries `weight_kg`
/// — the web's volume↔amount autosync depends on that field, and the
/// backend still derives amount when only the product is supplied.
struct LeadConvertOptionsView: View {
    let lead: Lead
    let products: [Product]
    @Binding var busy: Bool
    let onLoadProducts: () -> Void
    let onConvert: (ConvertOptions) -> Void

    @Environment(\.dismiss) private var dismiss

    // Tata Tiscon flow no longer offers the "create account" leg —
    // the toggle was confusing reps into spawning duplicate partner
    // records on every conversion. Held constant at false so the
    // backend short-circuits the account creation; UI row removed.
    private let createAccount: Bool = false
    @State private var createDeal: Bool = true
    @State private var dealName: String = ""
    @State private var dealAmountText: String = ""
    @State private var dealProductId: String = ""

    struct ConvertOptions {
        let createAccount: Bool
        let createDeal: Bool
        let dealName: String?
        let dealAmount: Double?
        let dealProductId: String?
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Convert") {
                    Toggle("Create deal", isOn: $createDeal).tint(Brand.red)
                }

                if createDeal {
                    Section("Deal") {
                        TextField("Deal name", text: $dealName)
                            .submitLabel(.next)
                        TextField("Amount (₹)", text: $dealAmountText)
                            .keyboardType(.decimalPad)
                        if !products.isEmpty {
                            Picker("Product", selection: $dealProductId) {
                                Text("None").tag("")
                                ForEach(products) { p in
                                    Text(productLabel(p)).tag(p.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Brand.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Convert Lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(Brand.red).disabled(busy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onConvert(ConvertOptions(
                            createAccount: createAccount,
                            createDeal: createDeal,
                            dealName: dealName.isEmpty ? nil : dealName,
                            dealAmount: Double(dealAmountText),
                            dealProductId: dealProductId.isEmpty ? nil : dealProductId
                        ))
                    } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().tint(.white).scaleEffect(0.8) }
                            Text(busy ? "Converting…" : "Convert")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Brand.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(busy)
                }
            }
            .task {
                // Default the deal name to "{company} Opportunity" when the
                // lead is B2B, matching the web modal's default.
                if dealName.isEmpty {
                    if let co = lead.company, !co.isEmpty {
                        dealName = "\(co) Opportunity"
                    } else {
                        dealName = "\(lead.displayName) Opportunity"
                    }
                }
                onLoadProducts()
            }
        }
    }

    private func productLabel(_ p: Product) -> String {
        if let price = p.unitPrice, price > 0 {
            return "\(p.name) — ₹\(Int(price))"
        }
        return p.name
    }
}
