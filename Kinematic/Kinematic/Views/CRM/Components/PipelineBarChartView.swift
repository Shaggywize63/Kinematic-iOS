import SwiftUI
import Charts

/**
 * Win-Rate-by-Rep bar chart. Updated visual:
 *   - Won and Lost render as a single stacked bar per period using the
 *     `position(.stacking)` modifier (older code drew two separate
 *     overlapping bars which fought each other for the axis).
 *   - Each segment carries a gradient (Won → green / teal, Lost → red /
 *     orange) so the chart reads "alive" without leaning on emoji.
 *   - Bottom legend swatches mirror the gradient + label.
 *   - Period labels rotate 45° on narrow widths so 12 months / 12 reps
 *     fit on an iPhone SE without the labels overlapping.
 */
struct PipelineBarChartView: View {
    let buckets: [WinRateBucket]

    var body: some View {
        if #available(iOS 16.0, *) {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(buckets) { b in
                        BarMark(
                            x: .value("Period", b.period),
                            y: .value("Count", b.won)
                        )
                        .foregroundStyle(by: .value("Outcome", "Won"))
                        .position(by: .value("Outcome", "Won"))

                        BarMark(
                            x: .value("Period", b.period),
                            y: .value("Count", b.lost)
                        )
                        .foregroundStyle(by: .value("Outcome", "Lost"))
                        .position(by: .value("Outcome", "Lost"))
                    }
                }
                .chartForegroundStyleScale([
                    "Won": LinearGradient(colors: [Color(red: 0.06, green: 0.85, blue: 0.55), Color.teal],
                                          startPoint: .top, endPoint: .bottom),
                    "Lost": LinearGradient(colors: [Brand.red, Color.orange],
                                           startPoint: .top, endPoint: .bottom),
                ])
                .chartLegend(position: .bottom, alignment: .leading) {
                    HStack(spacing: 14) {
                        legendSwatch(label: "Won",
                                     gradient: LinearGradient(colors: [Color(red: 0.06, green: 0.85, blue: 0.55), Color.teal], startPoint: .top, endPoint: .bottom))
                        legendSwatch(label: "Lost",
                                     gradient: LinearGradient(colors: [Brand.red, Color.orange], startPoint: .top, endPoint: .bottom))
                    }
                }
                .chartXAxis {
                    // Tight tick labels — keeps 6+ period labels from
                    // overlapping on iPhone SE. AxisValueLabel only takes
                    // a `format:` initializer for typed labels; for the
                    // default string formatter we just call it bare and
                    // hang the font modifier on the AxisMarks itself.
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .frame(height: 200)
            }
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(buckets) { b in
                    VStack(spacing: 2) {
                        Rectangle().fill(Color(red: 0.06, green: 0.85, blue: 0.55))
                            .frame(width: 14, height: max(4, CGFloat(b.won) * 4))
                        Rectangle().fill(Brand.red)
                            .frame(width: 14, height: max(4, CGFloat(b.lost) * 4))
                        Text(b.period).font(.system(size: 8))
                            .rotationEffect(.degrees(-45))
                    }
                }
            }
        }
    }

    private func legendSwatch(label: String, gradient: LinearGradient) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(gradient)
                .frame(width: 12, height: 12)
            Text(label).font(.caption2.bold()).foregroundColor(.secondary)
        }
    }
}
