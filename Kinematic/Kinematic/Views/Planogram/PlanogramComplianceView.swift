//
//  PlanogramComplianceView.swift
//  Kinematic
//
//  Shows the compliance result after a capture: score breakdown,
//  bounding-box overlay on the shelf image, missing/misplaced lists,
//  and prioritized recommendations.
//

import SwiftUI

struct PlanogramComplianceView: View {
    let response: CaptureResponse
    let image: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var showFeedback = false
    @State private var feedbackText = ""
    @State private var feedbackBusy = false
    @State private var feedbackSent = false
    @State private var feedbackError: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    if let image {
                        ShelfOverlayView(
                            image: image,
                            detected: response.recognition.detected_skus,
                            missingIds: missingIdSet
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    scoreBreakdown

                    availabilitySection

                    posmSection

                    // Grouped so the two new sections count as ONE child of the
                    // outer VStack (the ViewBuilder buildBlock caps at 10). Group
                    // is a transparent layout container, so the outer VStack's
                    // 16pt spacing still applies between them and empty (pre-v2)
                    // sections add no gap.
                    Group {
                        shareOfShelfSection

                        pricingSection
                    }

                    if !response.result.recommendations.isEmpty {
                        section("Recommended actions") {
                            ForEach(response.result.recommendations) { r in
                                recommendationRow(r)
                            }
                        }
                    }

                    if !response.result.missing_skus.isEmpty {
                        section("Missing on shelf") {
                            ForEach(response.result.missing_skus) { m in
                                row(left: m.sku_name, right: "\(m.expected_facings) expected")
                            }
                        }
                    }

                    if !response.result.misplaced_skus.isEmpty {
                        section("Misplaced") {
                            ForEach(response.result.misplaced_skus) { m in
                                row(left: m.sku_name,
                                    right: "shelf \(m.actual_shelf) → \(m.expected_shelf)")
                            }
                        }
                    }

                    // FEEDBACK — Android/dashboard parity. Lets the field rep
                    // flag an obvious AI mistake (e.g. "this SKU is actually
                    // present") so supervisors can correct the model.
                    feedbackPanel
                }
                .padding(16)
            }
            .navigationTitle("Compliance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showFeedback) {
                feedbackSheet
            }
        }
    }

    private var feedbackPanel: some View {
        Group {
            if feedbackSent {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                    Text("Thanks — feedback recorded").font(.subheadline)
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.1)))
            } else {
                Button {
                    showFeedback = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.bubble.fill")
                        Text("Report inaccuracy").bold()
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.1)))
                    .foregroundColor(.orange)
                }
            }
        }
    }

    private var feedbackSheet: some View {
        NavigationStack {
            Form {
                Section("What looks wrong?") {
                    TextEditor(text: $feedbackText)
                        .frame(minHeight: 120)
                }
                if let err = feedbackError {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }
            }
            .navigationTitle("Report inaccuracy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showFeedback = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if feedbackBusy {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await sendFeedback() } }
                            .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func sendFeedback() async {
        let notes = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return }
        feedbackBusy = true; feedbackError = nil
        defer { feedbackBusy = false }
        do {
            _ = try await PlanogramService.shared.submitCaptureFeedback(
                captureId: response.capture_id, notes: notes)
            feedbackSent = true
            showFeedback = false
        } catch {
            feedbackError = error.localizedDescription
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(response.result.score))")
                    .font(.system(size: 56, weight: .black, design: .default))
                    .foregroundColor(scoreColor(response.result.score))
                Text("%")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(scoreColor(response.result.score))
                Spacer()
                if response.recognition.needs_review {
                    badge("Review needed", color: .orange)
                }
            }
            Text("Compliance score")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var scoreBreakdown: some View {
        VStack(spacing: 10) {
            scoreRow("Presence", value: response.result.presence_score)
            scoreRow("Facings",  value: response.result.facing_score)
            scoreRow("Position", value: response.result.position_score)
            scoreRow("Competitor share", value: response.result.competitor_share, inverted: true)
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func scoreRow(_ title: String, value: Double, inverted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
                Text("\(Int(value))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(scoreColor(value, inverted: inverted))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(scoreColor(value, inverted: inverted))
                        .frame(width: geo.size.width * CGFloat(min(100, value) / 100))
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: Stock & availability (retail execution)

    /// Detected SKUs that carry a unit estimate or stock status — the only ones
    /// worth listing per-SKU. Empty on captures that predate stock estimation.
    private var perSkuStockRows: [DetectedSKU] {
        response.recognition.detected_skus.filter {
            $0.units_estimate != nil || $0.stock_status != nil
        }
    }

    @ViewBuilder
    private var availabilitySection: some View {
        if let stock = response.result.stock_summary {
            let rate = response.result.availability_rate ?? stock.availability_rate
            VStack(alignment: .leading, spacing: 6) {
                Text("Stock & availability").font(.system(size: 14, weight: .heavy))
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(rate))")
                            .font(.system(size: 34, weight: .black))
                            .foregroundColor(scoreColor(rate))
                        Text("%")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(scoreColor(rate))
                        Text("in stock")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        stockStat("Total units", value: stock.total_units, color: .primary)
                        stockStat("Own", value: stock.own_units, color: .green)
                        stockStat("Competitor", value: stock.competitor_units, color: .red)
                    }
                    if !stock.out_of_stock_skus.isEmpty {
                        stockList(title: "Out of stock",
                                  skus: stock.out_of_stock_skus,
                                  chip: ("Out", .red))
                    }
                    if !stock.low_stock_skus.isEmpty {
                        stockList(title: "Low stock",
                                  skus: stock.low_stock_skus,
                                  chip: ("Low", .yellow),
                                  showUnits: true)
                    }
                    if !perSkuStockRows.isEmpty {
                        perSkuUnits(perSkuStockRows)
                    }
                }
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func stockStat(_ label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stockList(title: String,
                           skus: [StockSkuRef],
                           chip: (String, Color),
                           showUnits: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
            ForEach(Array(skus.enumerated()), id: \.offset) { _, sku in
                HStack(spacing: 8) {
                    Text(sku.sku_name).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if showUnits, let u = sku.units_estimate {
                        Text("\(u) left").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    badge(chip.0, color: chip.1)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func perSkuUnits(_ skus: [DetectedSKU]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Per-SKU units".uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
            ForEach(Array(skus.enumerated()), id: \.offset) { _, sku in
                HStack(spacing: 8) {
                    Text(sku.sku_name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if let u = sku.units_estimate {
                        Text("\(u)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    if let status = sku.stock_status {
                        stockStatusChip(status)
                    }
                }
                .padding(.vertical, 5)
            }
        }
    }

    @ViewBuilder
    private func stockStatusChip(_ status: String) -> some View {
        switch status {
        case "in_stock": badge("In stock", color: .green)
        case "low":      badge("Low", color: .yellow)
        case "out":      badge("Out", color: .red)
        default:         badge(status, color: .gray)
        }
    }

    // MARK: POSM compliance (retail execution)

    @ViewBuilder
    private var posmSection: some View {
        if let posm = response.result.posm {
            VStack(alignment: .leading, spacing: 6) {
                Text("POSM compliance").font(.system(size: 14, weight: .heavy))
                VStack(alignment: .leading, spacing: 14) {
                    if posm.expected_count == 0 {
                        Text("No POSM expected for this planogram.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if let score = response.result.posm_score ?? posm.score {
                                Text("\(Int(score))")
                                    .font(.system(size: 34, weight: .black))
                                    .foregroundColor(scoreColor(score))
                                Text("%")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundColor(scoreColor(score))
                            } else {
                                Text("N/A")
                                    .font(.system(size: 28, weight: .black))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(posm.found_count)/\(posm.expected_count) found")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        if !posm.missing.isEmpty {
                            posmItemList(title: "Missing", items: posm.missing, chip: nil)
                        }
                        if !posm.damaged.isEmpty {
                            posmItemList(title: "Damaged", items: posm.damaged, chip: ("Damaged", .red))
                        }
                        if !posm.found.isEmpty {
                            posmFoundList(posm.found)
                        }
                    }
                }
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func posmItemList(title: String,
                              items: [PosmItem],
                              chip: (String, Color)?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Text(item.name).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(posmTypeLabel(item.type))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if let chip {
                        badge(chip.0, color: chip.1)
                    }
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func posmFoundList(_ found: [PosmFound]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Found".uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
            ForEach(Array(found.enumerated()), id: \.offset) { _, f in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(posmTypeLabel(f.type))
                            if let brand = f.brand, !brand.isEmpty {
                                Text("· \(brand)")
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    posmConditionChip(f.condition)
                }
                .padding(.vertical, 5)
            }
        }
    }

    @ViewBuilder
    private func posmConditionChip(_ condition: String) -> some View {
        switch condition {
        case "good":     badge("Good", color: .green)
        case "obscured": badge("Obscured", color: .yellow)
        case "damaged":  badge("Damaged", color: .red)
        default:         badge(condition, color: .gray)
        }
    }

    private func posmTypeLabel(_ type: String) -> String {
        switch type {
        case "poster":       return "Poster"
        case "dangler":      return "Dangler"
        case "wobbler":      return "Wobbler"
        case "shelf_strip":  return "Shelf strip"
        case "standee":      return "Standee"
        case "gondola_end":  return "Gondola end"
        case "cooler":       return "Cooler"
        case "branded_rack": return "Branded rack"
        case "tent_card":    return "Tent card"
        case "bunting":      return "Bunting"
        case "banner":       return "Banner"
        case "other":        return "Other"
        default:             return type.capitalized
        }
    }

    // MARK: Share of shelf (retail execution v2)

    @ViewBuilder
    private var shareOfShelfSection: some View {
        let own = response.result.shelf_share_own
        let comp = response.result.shelf_share_competitor
        let categories = response.result.category_breakdown ?? []
        if own != nil || comp != nil || !categories.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Share of shelf").font(.system(size: 14, weight: .heavy))
                VStack(alignment: .leading, spacing: 14) {
                    if own != nil || comp != nil {
                        shareHeadline(own: own, competitor: comp)
                    }
                    if let occ = response.result.occupancy_score {
                        HStack {
                            Text("Occupancy")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(occ))%")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(scoreColor(occ))
                        }
                    }
                    if !categories.isEmpty {
                        categoryShareList(categories)
                    }
                }
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func shareHeadline(own: Double?, competitor: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                shareStat("Own", value: own, color: .green)
                shareStat("Competitor", value: competitor, color: .red)
                Spacer()
            }
            shareBar(own: own, competitor: competitor)
        }
    }

    private func shareStat(_ label: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value.map { "\(Int($0))" } ?? "—")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(color)
                if value != nil {
                    Text("%")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(color)
                }
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    /// Two-tone proportion bar: own (green) then competitor (red) as fractions
    /// of the full width, remainder is the empty-shelf track. Widths clip to the
    /// capsule so an over-100 sum can never overflow.
    private func shareBar(own: Double?, competitor: Double?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                HStack(spacing: 0) {
                    if let own {
                        Rectangle().fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, own / 100))))
                    }
                    if let competitor {
                        Rectangle().fill(Color.red)
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, competitor / 100))))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
    }

    private func categoryShareList(_ cats: [CategoryBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("By category".uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
            ForEach(Array(cats.enumerated()), id: \.offset) { _, c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(c.category)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text("\(c.facings) facings")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    shareBar(own: c.own_share, competitor: c.competitor_share)
                    HStack(spacing: 8) {
                        Text("Own \(Int(c.own_share))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                        Text("· Comp \(Int(c.competitor_share))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                        Spacer()
                        if let ao = c.avg_own_price, let ac = c.avg_competitor_price {
                            Text("Avg \(priceText(ao)) vs \(priceText(ac))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: Pricing / competitor price (retail execution v2)

    @ViewBuilder
    private var pricingSection: some View {
        let rows = response.result.pricing ?? []
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pricing").font(.system(size: 14, weight: .heavy))
                VStack(alignment: .leading, spacing: 14) {
                    let compare = avgPriceCompareLines
                    if !compare.isEmpty {
                        priceCompareBlock(compare)
                    }
                    pricingList(rows)
                }
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    /// Categories where BOTH an average own and competitor price were read — the
    /// clearest own-vs-competitor price comparison. Empty when a side has none.
    private var avgPriceCompareLines: [(category: String, own: Double, comp: Double)] {
        (response.result.category_breakdown ?? []).compactMap { c in
            guard let own = c.avg_own_price, let comp = c.avg_competitor_price else { return nil }
            return (c.category, own, comp)
        }
    }

    private func priceCompareBlock(_ lines: [(category: String, own: Double, comp: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Avg price · own vs competitor".uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 8) {
                    Text(line.category)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(priceText(line.own))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                    Text("vs")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(priceText(line.comp))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func pricingList(_ rows: [PricingRow]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prices read".uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                pricingRow(r)
            }
        }
    }

    private func pricingRow(_ r: PricingRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(r.sku_name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(r.is_competitor ? .red : .primary)
                        .lineLimit(1)
                    if r.is_competitor {
                        badge("Competitor", color: .red)
                    }
                }
                if let brand = r.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let p = r.price {
                    Text(priceText(p, currency: r.currency))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                } else {
                    Text("—")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                if !r.is_competitor {
                    mrpDeltaChip(r)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// Delta chip for an OWN row vs its expected MRP — red when the shelf price
    /// is above MRP, green when below. Uses the backend `delta` when present,
    /// else derives it from price − expected. Renders nothing without an MRP.
    @ViewBuilder
    private func mrpDeltaChip(_ r: PricingRow) -> some View {
        if let expected = r.expected_price,
           let d = r.delta ?? r.price.map({ $0 - expected }) {
            let sign = d > 0 ? "+" : ""
            let color: Color = d > 0 ? .red : (d < 0 ? .green : .gray)
            badge("\(sign)\(trimNumber(d)) vs MRP", color: color)
        }
    }

    /// Trims a Double for display: whole values show as integers, otherwise up
    /// to two decimals with trailing zeros dropped (249.5, not 249.50).
    private func trimNumber(_ n: Double) -> String {
        let rounded = (n * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%g", rounded)
    }

    /// Formats a shelf price with its currency prefix (₹ when the row omits one).
    private func priceText(_ value: Double, currency: String? = nil) -> String {
        "\(currency ?? "₹")\(trimNumber(value))"
    }

    private func recommendationRow(_ r: ComplianceRecommendation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            badge(r.priority.rawValue.uppercased(), color: priorityColor(r.priority))
            VStack(alignment: .leading, spacing: 4) {
                Text(r.action).font(.system(size: 14, weight: .bold))
                Text(r.rationale).font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func row(left: String, right: String) -> some View {
        HStack {
            Text(left).font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(right).font(.system(size: 12)).foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 14, weight: .heavy))
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Style helpers

    private var missingIdSet: Set<String> {
        Set(response.result.missing_skus.map { $0.sku_id })
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
    }

    private func scoreColor(_ value: Double, inverted: Bool = false) -> Color {
        let good = inverted ? value <= 25 : value >= 80
        let ok   = inverted ? value <= 40 : value >= 65
        return good ? .green : ok ? .yellow : .red
    }

    private func priorityColor(_ p: ComplianceRecommendation.Priority) -> Color {
        switch p {
        case .critical: return .red
        case .high:     return .orange
        case .medium:   return .blue
        case .low:      return .gray
        }
    }
}

// MARK: - Shelf overlay (bounding boxes)

struct ShelfOverlayView: View {
    let image: UIImage
    let detected: [DetectedSKU]
    let missingIds: Set<String>

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                ForEach(detected) { sku in
                    let r = sku.rect
                    Rectangle()
                        .stroke(color(for: sku), lineWidth: 2)
                        .frame(
                            width: max(2, geo.size.width * r.width),
                            height: max(2, geo.size.height * r.height)
                        )
                        .position(
                            x: geo.size.width * (r.minX + r.width / 2),
                            y: geo.size.height * (r.minY + r.height / 2)
                        )
                }
            }
        }
        .aspectRatio(image.size.width / max(1, image.size.height), contentMode: .fit)
    }

    private func color(for sku: DetectedSKU) -> Color {
        if sku.is_competitor { return .red }
        if let id = sku.sku_id, missingIds.contains(id) { return .yellow }
        if sku.sku_id != nil { return .green }
        return .gray
    }
}
