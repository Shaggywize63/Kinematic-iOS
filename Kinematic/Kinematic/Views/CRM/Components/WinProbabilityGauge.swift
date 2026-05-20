import SwiftUI

struct WinProbabilityGauge: View {
    let probability: Double          // 0..1
    let label: String?
    /// New optional inputs powering the "How?" sheet. When `breakdown` is
    /// non-nil we render a pill the user can tap to see the math; when
    /// nil the gauge falls back to its legacy compact form.
    let reasoning: String?
    let breakdown: WinProbabilityBreakdown?

    @State private var showHow = false

    init(probability: Double,
         label: String? = nil,
         reasoning: String? = nil,
         breakdown: WinProbabilityBreakdown? = nil) {
        self.probability = probability
        self.label = label
        self.reasoning = reasoning
        self.breakdown = breakdown
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(Brand.red)
                Text("POWERED BY KINI AI")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1)
                    .foregroundColor(Brand.red)
                Spacer()
                if breakdown != nil {
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
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(probability))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int(probability * 100))%")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(color)
                    if let label {
                        Text(label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(width: 120, height: 120)
        }
        .sheet(isPresented: $showHow) {
            if let bd = breakdown {
                WinProbabilityHowSheet(
                    probability: probability,
                    color: color,
                    reasoning: reasoning,
                    breakdown: bd
                )
            }
        }
    }

    private var color: Color {
        if probability >= 0.7 { return Brand.red }
        if probability >= 0.4 { return Brand.red }
        return .red
    }
}

/// "How is this calculated?" sheet for the win-probability gauge.
private struct WinProbabilityHowSheet: View {
    let probability: Double
    let color: Color
    let reasoning: String?
    let breakdown: WinProbabilityBreakdown

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headline
                    if let r = reasoning, !r.isEmpty {
                        Text(r)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    if breakdown.shortCircuit != nil {
                        shortCircuitCard
                    } else {
                        steps
                        if let formula = breakdown.formulaText, !formula.isEmpty {
                            formulaCard(formula)
                        }
                    }
                    footnote
                }
                .padding(20)
            }
            .navigationTitle("How is this calculated?")
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
        HStack(spacing: 14) {
            Text("\(Int(probability * 100))%")
                .font(.system(size: 44, weight: .black))
                .foregroundColor(color)
            if let stage = breakdown.stageName {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Win probability").font(.caption).foregroundColor(.secondary)
                    Text(stage).font(.system(size: 14, weight: .bold))
                }
            }
            Spacer()
        }
    }

    // MARK: Short-circuit (won/lost)

    private var shortCircuitCard: some View {
        let isWon = (breakdown.shortCircuit ?? "").lowercased() == "won"
        let tint: Color = isWon ? .green : .red
        let title = "Locked at \(Int(probability * 100))% — deal already \(isWon ? "Won" : "Lost")"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isWon ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundColor(tint)
                Text(title).font(.system(size: 14, weight: .bold))
            }
            if let msg = breakdown.shortCircuitMessage, !msg.isEmpty {
                Text(msg).font(.caption).foregroundColor(.secondary)
            }
            if let stage = breakdown.stageName, !stage.isEmpty {
                Text("Stage: \(stage)").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tint.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.35), lineWidth: 1))
        )
    }

    // MARK: Three numbered steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STEPS").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(.secondary)
            stepRow(
                number: 1,
                title: "Stage probability",
                value: breakdown.stageProbability.map { "\($0)%" } ?? "—",
                subtitle: breakdown.stageName
            )
            stepRow(
                number: 2,
                title: "Deal age",
                value: breakdown.ageMultiplier.map { String(format: "×%.2f", $0) } ?? "—",
                subtitle: breakdown.ageLabel
            )
            stepRow(
                number: 3,
                title: "Engagement",
                value: breakdown.engagementMultiplier.map { String(format: "×%.2f", $0) } ?? "—",
                subtitle: breakdown.engagementLabel
            )
        }
    }

    private func stepRow(number: Int, title: String, value: String, subtitle: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Brand.red.opacity(0.15)).frame(width: 28, height: 28)
                Text("\(number)").font(.system(size: 12, weight: .black)).foregroundColor(Brand.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text(value).font(.system(size: 13, weight: .black)).foregroundColor(Brand.red)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: Formula card

    private func formulaCard(_ formula: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FORMULA").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(.secondary)
            Text(formula)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(Brand.red)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Brand.red.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.red.opacity(0.25), lineWidth: 1))
        )
    }

    // MARK: Footnote

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Powered by KINI AI")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Brand.red)
            Text("Win probability = stage probability × age multiplier × engagement multiplier. Capped between 5% and 95%.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }
}
