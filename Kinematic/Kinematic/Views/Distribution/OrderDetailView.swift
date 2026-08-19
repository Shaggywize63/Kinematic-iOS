import SwiftUI

struct OrderDetailView: View {
    let orderId: String
    @StateObject private var vm = DistributionViewModel()
    @StateObject private var printer = BluetoothPrinterManager()
    @State private var showCancelConfirm = false
    @State private var cancelReason = ""

    // Bluetooth bill printing. `pendingReceipt` holds the built ESC/POS bytes
    // while the picker is up so we can fire the job the moment a printer
    // becomes ready.
    @State private var showPrinterPicker = false
    @State private var pendingReceipt: Data?
    @State private var printMessage: String?

    // GST invoice document. Offered only for invoiced orders; the invoice is
    // fetched lazily inside InvoiceView on present.
    @State private var showInvoice = false

    /// Distribution package gate — mirrors SideMenu / StoreVisit. Legacy
    /// sessions (empty entitlements) default to `true` so we never hide the
    /// action from an existing van-sales user mid-deploy; non-distribution
    /// tenants never see the button.
    private var hasDistribution: Bool { Session.currentUser?.hasDistribution ?? true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let o = vm.currentOrder {
                    HStack { Text(o.order_no).font(.title3).bold(); Spacer(); statusPill(o.status) }
                    Text(o.placed_at).font(.caption).foregroundColor(.secondary)
                    Divider().padding(.vertical, 8)
                    ForEach(o.order_items ?? []) { line in
                        HStack {
                            Text("\(line.qty) × \(line.sku_name ?? line.sku_id)")
                            Spacer()
                            Text("₹\(fmt(line.total))").bold()
                        }
                        .padding(.vertical, 2)
                    }
                    Divider().padding(.vertical, 8)
                    HStack { Text("Grand total").bold(); Spacer(); Text("₹\(fmt(o.grand_total))").bold() }

                    // VIEW INVOICE — only once the order is invoiced. Opens the
                    // formal GST invoice document (InvoiceView loads it on
                    // present and shows a graceful state if it isn't ready).
                    if hasDistribution && o.status.lowercased() == "invoiced" {
                        Button {
                            showInvoice = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                Text("View invoice").bold()
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(red: 208/255, green: 30/255, blue: 44/255)).foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.top, 16)
                    }

                    // PRINT BILL — 58mm Bluetooth thermal receipt. Gated on the
                    // distribution package so non-distribution tenants are
                    // unaffected. If a printer is already connected we print
                    // straight away; otherwise we present the picker and print
                    // as soon as one connects.
                    if hasDistribution {
                        Button {
                            printBill(o)
                        } label: {
                            HStack {
                                Image(systemName: "printer.fill")
                                Text("Print Bill").bold()
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.indigo).foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.top, 16)

                        if let m = printMessage {
                            Text(m).font(.caption).foregroundColor(.secondary)
                        }
                    }

                    // CANCEL — only for orders still in a cancellable state.
                    // The server is the source of truth for what's allowed;
                    // we gate the button on the obvious terminal states so we
                    // don't show a destructive action for a completed order.
                    if canCancel(o.status) {
                        Button(role: .destructive) {
                            showCancelConfirm = true
                        } label: {
                            HStack {
                                if vm.cancelling { ProgressView().tint(.white) }
                                else { Image(systemName: "xmark.circle.fill") }
                                Text("Cancel Order").bold()
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.red).foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.top, 16)
                        .disabled(vm.cancelling)
                    }
                    if let err = vm.cancelError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadOrder(orderId) }
        .task { if hasDistribution { printer.reconnectLast() } }
        .sheet(isPresented: $showPrinterPicker) {
            PrinterPickerView(manager: printer) {
                // A printer became ready — flush the pending bill and close.
                if let data = pendingReceipt {
                    printer.print(data) { ok in
                        printMessage = ok ? "Bill sent to printer." : "Couldn't send to printer."
                    }
                    pendingReceipt = nil
                }
                showPrinterPicker = false
            }
        }
        .sheet(isPresented: $showInvoice) {
            NavigationStack {
                InvoiceView(orderId: orderId)
            }
        }
        .alert("Cancel this order?", isPresented: $showCancelConfirm) {
            TextField("Reason (optional)", text: $cancelReason)
            Button("Keep order", role: .cancel) { }
            Button("Cancel order", role: .destructive) {
                let reason = cancelReason.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { _ = await vm.cancelCurrentOrder(reason: reason.isEmpty ? nil : reason) }
            }
        } message: {
            Text("This can't be undone. The customer-facing record will move to cancelled.")
        }
    }

    // MARK: - Printing

    /// Build the receipt and either print immediately (printer ready) or
    /// present the picker to connect one first.
    private func printBill(_ order: DistOrder) {
        let data = ESCPOSReceipt.build(buildReceipt(from: order))
        if printer.isReady {
            printMessage = "Sending bill…"
            printer.print(data) { ok in
                printMessage = ok ? "Bill sent to printer." : "Couldn't send to printer."
            }
        } else {
            pendingReceipt = data
            printMessage = nil
            showPrinterPicker = true
        }
    }

    /// Map the loaded order + line items onto the receipt model. CGST/SGST are
    /// summed from the per-line tax fields; the subtotal prefers the order's
    /// taxable value and falls back to the line sum. The company header, address
    /// and GSTIN come from the order's nested `distributor` when present, falling
    /// back to the tenant constant.
    private func buildReceipt(from order: DistOrder) -> ReceiptBill {
        let lines = order.order_items ?? []
        let items = lines.map {
            ReceiptLineItem(
                name: $0.sku_name ?? $0.sku_code ?? $0.sku_id,
                qty: $0.qty,
                unitPrice: $0.unit_price,
                amount: $0.total
            )
        }
        let subtotal = order.taxable_value ?? lines.reduce(0) { $0 + $1.taxable_value }
        let cgst = lines.reduce(0) { $0 + $1.cgst }
        let sgst = lines.reduce(0) { $0 + $1.sgst }

        let dist = order.distributor
        let fallbackName = ClientFeatures.isTataTiscon ? "TATA TISCON" : "KINEMATIC"
        let companyName: String = {
            if let name = dist?.name, !name.isEmpty { return name }
            return fallbackName
        }()
        let gstin: String? = {
            if let g = dist?.gstin, !g.isEmpty { return g }
            return nil
        }()
        let address: String? = {
            guard let a = dist?.address else { return nil }
            let parts = [a.line1, a.city, a.state, a.pincode]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }()

        return ReceiptBill(
            companyName: companyName,
            address: address,
            gstin: gstin,
            outletName: order.outlet_name,
            billNo: order.order_no,
            date: receiptDate(order.placed_at),
            items: items,
            subtotal: subtotal,
            cgst: cgst,
            sgst: sgst,
            grandTotal: order.grand_total
        )
    }

    /// Parse the ISO `placed_at` and render a compact local date/time; fall
    /// back to the raw string if it doesn't parse.
    private func receiptDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? {
            parser.formatOptions = [.withInternetDateTime]
            return parser.date(from: iso)
        }()
        guard let d = date else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_IN")
        out.dateFormat = "dd MMM yyyy, h:mm a"
        return out.string(from: d)
    }

    private func canCancel(_ s: String) -> Bool {
        let t = s.lowercased()
        return !(t == "cancelled" || t == "delivered" || t == "invoiced" || t == "dispatched")
    }

    private func statusPill(_ s: String) -> some View {
        Text(s)
            .font(.caption2).bold()
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(8)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "0"
    }
}
