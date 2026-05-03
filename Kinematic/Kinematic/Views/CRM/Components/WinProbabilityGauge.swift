import SwiftUI

struct WinProbabilityGauge: View {
    let probability: Double          // 0..1
    let label: String?

    var body: some View {
        VStack(spacing: 12) {
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
    }

    private var color: Color {
        if probability >= 0.7 { return .green }
        if probability >= 0.4 { return .orange }
        return .red
    }
}
