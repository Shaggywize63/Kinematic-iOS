//
//  OrderShareImage.swift
//  Kinematic
//
//  The order as a PNG the rep can send over WhatsApp (or anywhere else): company, order number, outlet, date, every
//  line with quantity, rate, discount and amount, then the tax split and the grand total. `OrderShareModel` works
//  every figure out (pure, unit-tested); `OrderShareCard` only lays them out; `OrderShareImage.png(for:)` renders
//  the card with ImageRenderer and writes the file the share sheet sends.
//

import SwiftUI
import UIKit

struct OrderShareRow: Equatable {
    let name: String
    let qtyLabel: String
    let rate: Double
    /// (MRP − rate) × qty when the rep's price is below MRP; 0 otherwise (and for free goods).
    let discount: Double
    let amount: Double
    let freeGood: Bool
}

struct OrderShareTax: Equatable {
    let label: String
    let amount: Double
}

struct OrderShareModel: Equatable {
    let company: String?
    let orderNo: String
    let outlet: String?
    let placed: String?
    let status: String
    let rows: [OrderShareRow]
    let totalDiscount: Double
    let taxable: Double
    /// Tax lines worth printing, in order; a zero line is left out.
    let taxLines: [OrderShareTax]
    let grandTotal: Double

    var hasDiscount: Bool { rows.contains { $0.discount > 0.004 } }
}

enum OrderShare {
    /// IST "17 Oct 2026, 04:00 PM" for an ISO timestamp; the raw text when it can't be read; nil when blank.
    static func placedLabel(_ iso: String?) -> String? {
        let raw = (iso ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        let withFraction = ISO8601DateFormatter(); withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        guard let date = withFraction.date(from: raw) ?? plain.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = TimeZone(identifier: "Asia/Kolkata")
        out.dateFormat = "dd MMM yyyy, hh:mm a"
        return out.string(from: date)
    }

    /// "12 case" / "3 btl"; the unit as the server sent it, "pcs" when blank.
    static func qtyLabel(_ qty: Int, _ uom: String?) -> String {
        let unit = (uom ?? "").trimmingCharacters(in: .whitespaces)
        return "\(qty) \(unit.isEmpty ? "pcs" : unit)"
    }

    static func lineDiscount(_ l: PricedLine) -> Double {
        if l.is_free_good == true { return 0 }
        let per = l.mrp - l.unit_price
        return per > 0.005 ? per * Double(l.qty) : 0
    }

    static func row(for l: PricedLine) -> OrderShareRow {
        let name = (l.sku_name?.isEmpty == false ? l.sku_name : nil) ?? l.sku_code ?? l.sku_id
        return OrderShareRow(name: name, qtyLabel: qtyLabel(l.qty, l.uom), rate: l.unit_price,
                             discount: lineDiscount(l), amount: l.total, freeGood: l.is_free_good == true)
    }

    static func build(order: DistOrder, company: String?) -> OrderShareModel {
        let lines = order.order_items ?? []
        let rows = lines.map { row(for: $0) }
        // The order carries only its taxable value, so the tax split is the sum of its lines.
        let tax: [OrderShareTax] = [
            OrderShareTax(label: "CGST", amount: lines.reduce(0) { $0 + $1.cgst }),
            OrderShareTax(label: "SGST", amount: lines.reduce(0) { $0 + $1.sgst }),
            OrderShareTax(label: "IGST", amount: lines.reduce(0) { $0 + $1.igst }),
            OrderShareTax(label: "Cess", amount: lines.reduce(0) { $0 + $1.cess }),
        ].filter { abs($0.amount) > 0.004 }
        let taxable = order.taxable_value ?? lines.reduce(0) { $0 + $1.taxable_value }
        let trimmedCompany = company?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutlet = order.outlet_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return OrderShareModel(
            company: (trimmedCompany?.isEmpty == false) ? trimmedCompany : nil,
            orderNo: order.order_no,
            outlet: (trimmedOutlet?.isEmpty == false) ? trimmedOutlet : nil,
            placed: placedLabel(order.placed_at),
            status: order.status.prefix(1).uppercased() + order.status.dropFirst(),
            rows: rows,
            totalDiscount: rows.reduce(0) { $0 + $1.discount },
            taxable: taxable,
            taxLines: tax,
            grandTotal: order.grand_total)
    }

    static func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return "₹" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }
}

// MARK: - The card

struct OrderShareCard: View {
    let model: OrderShareModel
    private let red = Color(red: 224/255, green: 30/255, blue: 44/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: 0) {
                columnHeads
                ForEach(Array(model.rows.enumerated()), id: \.offset) { i, r in rowView(r, shaded: i % 2 == 1) }
                Divider().padding(.vertical, 8)
                totals
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
            Text("Shared from Kinematic").font(.footnote).foregroundColor(.gray)
                .padding(.horizontal, 28).padding(.bottom, 20)
        }
        .frame(width: 540)
        .background(Color.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.company ?? "Order").font(.title3.bold()).lineLimit(1)
                Spacer()
                Text(model.status).font(.subheadline.bold())
            }
            Text("Order \(model.orderNo)").font(.title.bold())
            Text([model.outlet, model.placed].compactMap { $0 }.joined(separator: "  ·  "))
                .font(.subheadline).opacity(0.9).lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(red)
    }

    private var columnHeads: some View {
        HStack(spacing: 6) {
            Text("ITEM").frame(maxWidth: .infinity, alignment: .leading)
            Text("QTY").frame(width: 70, alignment: .trailing)
            Text("RATE").frame(width: 78, alignment: .trailing)
            if model.hasDiscount { Text("DISC.").frame(width: 70, alignment: .trailing) }
            Text("AMOUNT").frame(width: 92, alignment: .trailing)
        }
        .font(.caption2.bold()).foregroundColor(.gray)
        .padding(.top, 18).padding(.bottom, 6)
    }

    private func rowView(_ r: OrderShareRow, shaded: Bool) -> some View {
        HStack(spacing: 6) {
            Text(r.freeGood ? "\(r.name) (free)" : r.name).font(.footnote.bold())
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text(r.qtyLabel).frame(width: 70, alignment: .trailing)
            Text(r.freeGood ? "—" : OrderShare.money(r.rate)).frame(width: 78, alignment: .trailing)
            if model.hasDiscount {
                Text(r.discount > 0.004 ? "-" + OrderShare.money(r.discount) : "").foregroundColor(.gray)
                    .frame(width: 70, alignment: .trailing)
            }
            Text(OrderShare.money(r.amount)).bold().frame(width: 92, alignment: .trailing)
        }
        .font(.footnote)
        .padding(.vertical, 7)
        .background(shaded ? Color(red: 245/255, green: 246/255, blue: 248/255) : Color.clear)
    }

    private var totals: some View {
        VStack(spacing: 6) {
            if model.hasDiscount { totalLine("Discount", "-" + OrderShare.money(model.totalDiscount)) }
            totalLine("Taxable value", OrderShare.money(model.taxable))
            ForEach(Array(model.taxLines.enumerated()), id: \.offset) { _, t in totalLine(t.label, OrderShare.money(t.amount)) }
            HStack {
                Text("Grand total").font(.headline)
                Spacer()
                Text(OrderShare.money(model.grandTotal)).font(.title3.bold()).foregroundColor(red)
            }
            .padding(12)
            .background(Color(red: 245/255, green: 246/255, blue: 248/255))
            .padding(.top, 6)
        }
    }

    private func totalLine(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundColor(.gray); Spacer(); Text(value) }.font(.subheadline)
    }
}

// MARK: - Rendering + sharing

enum OrderShareImage {
    /// Renders the card to a PNG in the temporary folder and returns its file URL (nil when rendering failed).
    @MainActor static func png(for model: OrderShareModel, fileName: String) -> URL? {
        let renderer = ImageRenderer(content: OrderShareCard(model: model))
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { return nil }
        let safe = fileName.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("order-\(safe.isEmpty ? "share" : safe).png")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

/// UIKit share sheet (WhatsApp, Messages, Mail, Files …) for the rendered order image.
struct OrderImageShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Identifiable wrapper so a sheet can present the image file.
struct SharedOrderImage: Identifiable { let id = UUID(); let url: URL }
