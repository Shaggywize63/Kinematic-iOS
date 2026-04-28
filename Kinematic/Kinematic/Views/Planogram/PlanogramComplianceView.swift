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
