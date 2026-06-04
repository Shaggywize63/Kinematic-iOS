import SwiftUI

/// "How was this recommended?" — the NBA explainer, mirroring the web
/// NextBestActionCard methodology popover. Shows the recommendation, the
/// reasoning, the suggested step-by-step plan, and the key signals.
struct NbaHowSheet: View {
    let nba: NextBestAction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Recommendation") {
                        Text(nba.action.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.headline)
                        if let r = nba.reason ?? nba.rationale, !r.isEmpty {
                            Text(r).font(.subheadline).foregroundColor(.secondary)
                        }
                        HStack(spacing: 8) {
                            if let p = nba.priority { tag("Priority: \(p.capitalized)") }
                            if let w = nba.suggestedWhen {
                                tag("When: \(w.replacingOccurrences(of: "_", with: " "))")
                            }
                        }
                    }

                    if let m = nba.methodology {
                        if let reasoning = m.reasoning, !reasoning.isEmpty {
                            section("Why this") { Text(reasoning).font(.subheadline) }
                        }
                        if let plan = m.closingPlan, !plan.isEmpty {
                            section("Suggested plan") {
                                ForEach(plan) { step in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(step.step)")
                                            .font(.system(size: 12, weight: .black)).foregroundColor(Brand.red)
                                            .frame(width: 22, height: 22)
                                            .background(Circle().fill(Brand.red.opacity(0.15)))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(step.action).font(.system(size: 14, weight: .semibold))
                                            if let r = step.rationale, !r.isEmpty {
                                                Text(r).font(.caption).foregroundColor(.secondary)
                                            }
                                            if let w = step.when, !w.isEmpty {
                                                Text(w.replacingOccurrences(of: "_", with: " "))
                                                    .font(.caption2).foregroundColor(Brand.red)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if let sig = m.signals {
                            let rows = signalRows(sig)
                            if !rows.isEmpty {
                                section("Signals considered") {
                                    ForEach(rows, id: \.0) { (k, v) in
                                        HStack {
                                            Text(k).font(.caption).foregroundColor(.secondary)
                                            Spacer()
                                            Text(v).font(.caption.weight(.semibold))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("How this was recommended")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func section<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .black)).tracking(0.8).foregroundColor(Brand.red)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Brand.red.opacity(0.12)))
            .foregroundColor(Brand.red)
    }

    /// Pull the non-nil, lead-relevant signals into label/value rows.
    private func signalRows(_ s: NextBestActionSignals) -> [(String, String)] {
        var out: [(String, String)] = []
        if let v = s.activities30dTotal { out.append(("Activities (30d)", "\(v)")) }
        if let v = s.daysSinceLastTouch { out.append(("Days since last touch", "\(v)")) }
        if let v = s.lastActivityType, !v.isEmpty { out.append(("Last activity", v.capitalized)) }
        if let v = s.winProbability { out.append(("Win probability", "\(v)%")) }
        if let v = s.daysInStage { out.append(("Days in stage", "\(v)")) }
        return out
    }
}
