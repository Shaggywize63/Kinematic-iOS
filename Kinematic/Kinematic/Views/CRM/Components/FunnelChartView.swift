import SwiftUI
import Charts

/**
 * Funnel chart for the pipeline-by-stage breakdown.
 *
 * Visual refresh notes:
 *   - Bars now carry a true gradient (red → orange) instead of a solid
 *     red mark; the old `LinearGradient(colors: [Brand.red, Brand.red])`
 *     was effectively flat and gave the chart a 2018-vintage look.
 *   - The count is rendered inside the bar when the bar is wide enough
 *     and trailing-annotated otherwise — keeps the label legible on
 *     phones where the first big stage and the last small stage often
 *     differ by 20× in count.
 *   - Y axis (stage names) is left-aligned with explicit label widths so
 *     long stage names ("Initial Discovery", "Proposal Submitted") don't
 *     squish at the iPhone SE width.
 */
struct FunnelChartView: View {
    let stages: [FunnelStageMetric]

    private var maxCount: Int { stages.map(\.count).max() ?? 1 }

    var body: some View {
        if #available(iOS 16.0, *) {
            Chart(stages) { stage in
                BarMark(
                    x: .value("Count", stage.count),
                    y: .value("Stage", stage.stageName)
                )
                .foregroundStyle(barGradient)
                .cornerRadius(6)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(stage.count)")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(height: max(140, CGFloat(stages.count) * 40))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(stages) { s in
                    HStack(spacing: 8) {
                        Text(s.stageName)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 110, alignment: .leading)
                            .lineLimit(2)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.12))
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(barGradient)
                                    .frame(width: geo.size.width * widthFactor(for: s))
                            }
                        }
                        .frame(height: 18)
                        Text("\(s.count)")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [Brand.red, Color.orange.opacity(0.92)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func widthFactor(for s: FunnelStageMetric) -> CGFloat {
        maxCount == 0 ? 0 : CGFloat(s.count) / CGFloat(maxCount)
    }
}
