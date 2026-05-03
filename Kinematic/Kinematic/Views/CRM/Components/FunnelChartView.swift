import SwiftUI
import Charts

struct FunnelChartView: View {
    let stages: [FunnelStageMetric]

    var body: some View {
        if #available(iOS 16.0, *) {
            Chart(stages) { stage in
                BarMark(
                    x: .value("Count", stage.count),
                    y: .value("Stage", stage.stageName)
                )
                .foregroundStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text("\(stage.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: max(120, CGFloat(stages.count) * 40))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(stages) { s in
                    HStack {
                        Text(s.stageName).font(.caption).frame(width: 100, alignment: .leading)
                        GeometryReader { geo in
                            Rectangle()
                                .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * widthFactor(for: s))
                                .cornerRadius(4)
                        }.frame(height: 16)
                        Text("\(s.count)").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func widthFactor(for s: FunnelStageMetric) -> CGFloat {
        let max = stages.map(\.count).max() ?? 1
        return max == 0 ? 0 : CGFloat(s.count) / CGFloat(max)
    }
}
