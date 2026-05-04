import SwiftUI

struct NextBestActionCard: View {
    let action: NextBestAction
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("NEXT BEST ACTION")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .foregroundColor(.purple)
            }
            Text(action.action)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(uiColor: .label))
            if let r = action.rationale {
                Text(r).font(.caption).foregroundColor(.secondary)
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
                .background(Color.purple)
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.25), lineWidth: 1))
        )
    }
}
