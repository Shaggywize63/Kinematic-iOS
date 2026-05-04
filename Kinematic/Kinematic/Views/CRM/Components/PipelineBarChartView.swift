import SwiftUI
import Charts

struct PipelineBarChartView: View {
    let buckets: [WinRateBucket]

    var body: some View {
        if #available(iOS 16.0, *) {
            Chart(buckets) { b in
                BarMark(
                    x: .value("Period", b.period),
                    y: .value("Won", b.won)
                )
                .foregroundStyle(.green)
                BarMark(
                    x: .value("Period", b.period),
                    y: .value("Lost", b.lost)
                )
                .foregroundStyle(.red.opacity(0.7))
            }
            .frame(height: 180)
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(buckets) { b in
                    VStack(spacing: 2) {
                        Rectangle().fill(Color.green).frame(width: 14, height: CGFloat(b.won) * 4)
                        Rectangle().fill(Color.red.opacity(0.7)).frame(width: 14, height: CGFloat(b.lost) * 4)
                        Text(b.period).font(.system(size: 8))
                    }
                }
            }
        }
    }
}
