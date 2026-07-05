import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Renders a `ConversationInsights` payload: summary, intent + sentiment
/// chips, positives / improvements, objections, competitors, extracted deal
/// facts, coaching, next action and a draft follow-up. Reused by the record
/// sheet (inline after processing) and the lead-detail conversation drill-in.
/// Every section renders only when its content is present, so a sparse payload
/// collapses cleanly.
struct ConversationInsightsView: View {
    let insights: ConversationInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = insights.summary, !s.isEmpty { summaryCard(s) }
            chipsRow
            listCard(title: "WHAT WENT WELL", icon: "hand.thumbsup.fill", tint: Brand.success, items: insights.positives)
            listCard(title: "TO IMPROVE", icon: "arrow.up.forward.circle.fill", tint: Brand.caution, items: insights.improvements)
            objectionsCard
            competitorsCard
            listCard(title: "COMMITMENTS", icon: "checkmark.circle.fill", tint: Brand.info, items: insights.commitments)
            extractedCard
            coachingCard
            nextActionCard
            draftFollowupCard
            listCard(title: "RISK FLAGS", icon: "exclamationmark.triangle.fill", tint: Brand.red, items: insights.riskFlags)
        }
    }

    // MARK: - Summary

    @ViewBuilder private func summaryCard(_ text: String) -> some View {
        sectionCard(title: "SUMMARY", icon: "text.alignleft") {
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Intent / sentiment chips

    @ViewBuilder private var chipsRow: some View {
        let hasIntent = (insights.intent?.stage?.isEmpty == false) || (insights.intent?.score != nil)
        let hasSentiment = (insights.sentiment?.overall?.isEmpty == false) || (insights.sentiment?.trajectory?.isEmpty == false)
        let signals = insights.intent?.signals ?? []
        if hasIntent || hasSentiment {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 8) {
                    if hasIntent {
                        InsightChip(label: "Intent", value: intentValue(insights.intent), tint: Brand.red)
                    }
                    if let overall = insights.sentiment?.overall, !overall.isEmpty {
                        InsightChip(label: "Sentiment", value: overall.capitalized, tint: sentimentTint(overall))
                    }
                    if let traj = insights.sentiment?.trajectory, !traj.isEmpty {
                        InsightChip(label: "Trend", value: traj.capitalized, tint: Brand.info)
                    }
                }
                if !signals.isEmpty {
                    Text("Signals: " + signals.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func intentValue(_ intent: ConversationIntent?) -> String {
        guard let intent else { return "—" }
        var parts: [String] = []
        if let s = intent.stage, !s.isEmpty { parts.append(s.capitalized) }
        if let sc = intent.score { parts.append("\(sc)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func sentimentTint(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "positive", "good", "warm", "happy": return Brand.success
        case "negative", "bad", "cold", "angry", "frustrated": return Brand.red
        default: return Brand.caution
        }
    }

    // MARK: - Simple bullet lists

    @ViewBuilder private func listCard(title: String, icon: String, tint: Color, items: [String]?) -> some View {
        if let items, !items.isEmpty {
            sectionCard(title: title, icon: icon, tint: tint) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        bullet(item, tint: tint)
                    }
                }
            }
        }
    }

    private func bullet(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundColor(tint)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Objections

    @ViewBuilder private var objectionsCard: some View {
        if let objections = insights.objections, !objections.isEmpty {
            sectionCard(title: "OBJECTIONS", icon: "hand.raised.fill", tint: Brand.caution) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(objections) { o in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text((o.type ?? "Objection").capitalized)
                                    .font(.system(size: 14, weight: .semibold))
                                if let handled = o.handled {
                                    Text(handled ? "Handled" : "Open")
                                        .font(.caption2).fontWeight(.bold)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background((handled ? Brand.success : Brand.red).opacity(0.15))
                                        .foregroundColor(handled ? Brand.success : Brand.red)
                                        .cornerRadius(5)
                                }
                            }
                            if let note = o.note, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Competitors

    @ViewBuilder private var competitorsCard: some View {
        if let competitors = insights.competitors, !competitors.isEmpty {
            sectionCard(title: "COMPETITORS", icon: "building.2.fill", tint: Brand.info) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(competitors) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.name ?? "Competitor")
                                .font(.system(size: 14, weight: .semibold))
                            if let ctx = c.context, !ctx.isEmpty {
                                Text(ctx)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Extracted deal facts

    @ViewBuilder private var extractedCard: some View {
        if let ex = insights.extracted, !ex.isEmpty {
            sectionCard(title: "DEAL FACTS", icon: "list.bullet.clipboard.fill", tint: Brand.red) {
                VStack(alignment: .leading, spacing: 6) {
                    factRow("Grade", ex.grade)
                    factRow("Quantity (t)", ex.quantityTonnes)
                    factRow("Budget", ex.budget)
                    factRow("Timeline", ex.timeline)
                    factRow("Project stage", ex.projectStage)
                    factRow("Decision maker", ex.decisionMaker)
                }
            }
        }
    }

    @ViewBuilder private func factRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 120, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Coaching

    @ViewBuilder private var coachingCard: some View {
        if let coaching = insights.coaching, !coaching.isEmpty {
            sectionCard(title: "COACHING", icon: "figure.wave", tint: Brand.info) {
                VStack(alignment: .leading, spacing: 10) {
                    if let ratio = coaching.talkListenRatio, !ratio.isEmpty {
                        factRow("Talk : Listen", ratio)
                    }
                    if let missed = coaching.missedQuestions, !missed.isEmpty {
                        Text("Missed questions")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                        ForEach(Array(missed.enumerated()), id: \.offset) { _, q in
                            bullet(q, tint: Brand.caution)
                        }
                    }
                    if let tips = coaching.tips, !tips.isEmpty {
                        Text("Tips")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                        ForEach(Array(tips.enumerated()), id: \.offset) { _, t in
                            bullet(t, tint: Brand.success)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Next action

    @ViewBuilder private var nextActionCard: some View {
        if let na = insights.nextAction, !na.isEmpty {
            sectionCard(title: "NEXT ACTION", icon: "arrow.right.circle.fill", tint: Brand.red) {
                Text(na)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Draft follow-up

    @ViewBuilder private var draftFollowupCard: some View {
        if let draft = insights.draftFollowup, !draft.isEmpty {
            sectionCard(title: "DRAFT FOLLOW-UP", icon: "text.bubble.fill", tint: Brand.info) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(draft)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = draft
                        #endif
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Brand.red)
                    }
                }
            }
        }
    }

    // MARK: - Section chrome

    @ViewBuilder private func sectionCard<Content: View>(
        title: String,
        icon: String,
        tint: Color = Brand.red,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 11, weight: .black)).tracking(0.8)
                    .foregroundColor(tint)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }
}

// MARK: - Insight chip

private struct InsightChip: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black)).tracking(0.5)
                .foregroundColor(tint.opacity(0.85))
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(tint.opacity(0.12))
        .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 1))
        .clipShape(Capsule())
    }
}

// MARK: - Detail sheet (drill-in from the lead's Conversations list)

/// Full-screen presentation of a completed conversation: its AI insights plus
/// (optionally) the raw transcript. Presented via `.sheet(item:)` from the
/// lead-detail Conversations list.
struct ConversationDetailSheet: View {
    let detail: ConversationDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let insights = detail.insights {
                        ConversationInsightsView(insights: insights)
                    } else {
                        Text("No insights were returned for this recording.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let transcript = detail.transcript, !transcript.isEmpty {
                        DisclosureGroup {
                            Text(transcript)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 8)
                        } label: {
                            Text("TRANSCRIPT")
                                .font(.system(size: 11, weight: .black)).tracking(0.8)
                                .foregroundColor(Brand.red)
                        }
                        .tint(Brand.red)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
                    }
                }
                .padding(20)
            }
            .navigationTitle("Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.tint(Brand.red)
                }
            }
        }
    }
}

// MARK: - Flow layout (wraps chips onto multiple lines)

/// Minimal wrapping layout so the intent/sentiment chips flow onto new rows on
/// narrow phones instead of clipping. Mirrors the `FlexibleHStack` used on the
/// lead-detail action bar (kept local so this file is self-contained).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width + spacing
                rowHeight = size.height
            } else {
                rowWidth += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
