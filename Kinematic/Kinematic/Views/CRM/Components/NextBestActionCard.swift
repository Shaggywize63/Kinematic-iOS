import SwiftUI

struct NextBestActionCard: View {
    let action: NextBestAction
    let onAccept: () -> Void

    @State private var showHow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: section title + Kini badge + optional How? pill.
            // Web parity: the card keeps the "NEXT BEST ACTION" title and
            // the Kini AI attribution renders as a separate pill chip — it
            // does NOT replace the title (see issue: "Kini AI is not
            // visible").
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(Brand.red)
                Text("NEXT BEST ACTION")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .foregroundColor(Brand.red)
                PoweredByKiniAIBadge(compact: true)
                Spacer()
                if action.methodology != nil {
                    Button { showHow = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                            Text("How?")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.red.opacity(0.12)))
                        .foregroundColor(Brand.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(Self.displayAction(action.action))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(uiColor: .label))
            if let r = action.reason ?? action.rationale, !r.isEmpty {
                Text(r).font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                if let p = action.priority, !p.isEmpty {
                    NBAChip(text: "\(Self.normalizePriority(p)) priority".uppercased(),
                            tint: Self.priorityColor(p))
                }
                if let w = action.suggestedWhen, !w.isEmpty {
                    NBAChip(text: Self.displayWhen(w).uppercased(),
                            tint: Self.whenColor(w))
                }
                Spacer(minLength: 0)
            }
            Button(action: onAccept) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Schedule it")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Brand.red)
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Brand.red.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.red.opacity(0.25), lineWidth: 1))
        )
        .sheet(isPresented: $showHow) {
            if let m = action.methodology {
                NextBestActionHowSheet(action: action, methodology: m)
            }
        }
    }

    // MARK: Helpers shared with the sheet

    static func displayAction(_ raw: String) -> String {
        switch raw.lowercased() {
        case "call":          return "Call"
        case "meeting":       return "Schedule a meeting"
        case "send_proposal": return "Send proposal"
        case "nurture":       return "Nurture"
        case "disqualify":    return "Disqualify"
        default:              return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func displayWhen(_ raw: String) -> String {
        switch raw.lowercased() {
        case "now":       return "Now"
        case "today":     return "Today"
        case "this_week": return "This week"
        case "next_week": return "Next week"
        default:          return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func normalizePriority(_ raw: String) -> String {
        switch raw.lowercased() {
        case "high": return "High"
        case "med", "medium": return "Medium"
        case "low":  return "Low"
        default:     return raw.capitalized
        }
    }

    static func priorityColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "high":          return .red
        case "med", "medium": return .orange
        case "low":           return .blue
        default:              return .secondary
        }
    }

    static func whenColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "now", "today":  return .red
        case "this_week":     return .orange
        case "next_week":     return .blue
        default:              return .secondary
        }
    }
}

// MARK: - "How?" sheet

private struct NextBestActionHowSheet: View {
    let action: NextBestAction
    let methodology: NextBestActionMethodology

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headline
                    if let reason = action.reason ?? action.rationale ?? methodology.reasoning,
                       !reason.isEmpty {
                        Text(reason)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    if let signals = methodology.signals {
                        signalsSection(signals)
                    }
                    if let plan = methodology.closingPlan, !plan.isEmpty {
                        planSection(plan)
                    }
                    footnote
                }
                .padding(20)
            }
            .navigationTitle("How was this recommended?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NextBestActionCard.displayAction(action.action))
                .font(.system(size: 22, weight: .black))
                .foregroundColor(Color(uiColor: .label))
            HStack(spacing: 6) {
                if let p = action.priority, !p.isEmpty {
                    NBAChip(text: "\(NextBestActionCard.normalizePriority(p)) priority".uppercased(),
                            tint: NextBestActionCard.priorityColor(p))
                }
                if let w = action.suggestedWhen, !w.isEmpty {
                    NBAChip(text: NextBestActionCard.displayWhen(w).uppercased(),
                            tint: NextBestActionCard.whenColor(w))
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Signals

    private func signalsSection(_ s: NextBestActionSignals) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SIGNALS CONSIDERED")
                .font(.system(size: 10, weight: .black))
                .tracking(1)
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: 10) {
                signalChip(title: "Stage", value: s.stage?.name ?? "—")
                signalChip(title: "Days in stage",
                           value: s.daysInStage.map { "\($0)d" } ?? "—")
                signalChip(title: "Deal age",
                           value: s.dealAgeDays.map { "\($0)d" } ?? "—")
                signalChip(title: "Win probability",
                           value: s.winProbability.map { "\($0)%" } ?? "—")
                signalChip(title: "Activities (30d)",
                           value: activitiesValue(s))
                signalChip(title: "Last touch",
                           value: lastTouchValue(s))
            }
            // Stage transitions takes its own full-width row so the grid
            // stays balanced when there are 7 chips total.
            signalChip(title: "Stage transitions",
                       value: s.stageTransitions.map { "\($0)" } ?? "—",
                       fullWidth: true)
        }
    }

    private func activitiesValue(_ s: NextBestActionSignals) -> String {
        let total = s.activities30dTotal.map { "\($0)" } ?? "—"
        if let breakdown = s.activities30dByType, !breakdown.isEmpty {
            let parts = breakdown
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { "\($0.value) \($0.key)" }
                .joined(separator: ", ")
            return "\(total) (\(parts))"
        }
        return total
    }

    private func lastTouchValue(_ s: NextBestActionSignals) -> String {
        let days = s.daysSinceLastTouch.map { "\($0)d ago" } ?? "—"
        if let type = s.lastActivityType, !type.isEmpty {
            return "\(type) · \(days)"
        }
        return days
    }

    private func signalChip(title: String, value: String, fullWidth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(uiColor: .label))
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: Closing plan

    private func planSection(_ steps: [NextBestActionPlanStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLOSING PLAN")
                .font(.system(size: 10, weight: .black))
                .tracking(1)
                .foregroundColor(.secondary)
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(Brand.red.opacity(0.15)).frame(width: 28, height: 28)
                        Text("\(step.step)").font(.system(size: 12, weight: .black))
                            .foregroundColor(Brand.red)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(step.action)
                                .font(.system(size: 13, weight: .bold))
                            Spacer(minLength: 8)
                            if let w = step.when, !w.isEmpty {
                                NBAChip(text: NextBestActionCard.displayWhen(w).uppercased(),
                                        tint: NextBestActionCard.whenColor(w))
                            }
                        }
                        if let r = step.rationale, !r.isEmpty {
                            Text(r).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
            }
        }
    }

    // MARK: Footnote

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Powered by KINI AI")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Brand.red)
            Text("Recommendations are derived from deal stage, age, win probability, recent activity volume, and time since last touch.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }
}

// MARK: - Tiny chip helper shared by the card and sheet

struct NBAChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .black))
            .tracking(0.8)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundColor(tint)
    }
}
