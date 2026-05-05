import SwiftUI

struct AISuggestionCard: View {
    let title: String
    let message: String
    let onAccept: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.indigo)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .foregroundColor(.indigo)
            }
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Color(uiColor: .label))
            if let onAccept {
                Button(action: onAccept) {
                    Text("Use this")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.indigo.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.indigo.opacity(0.25), lineWidth: 1))
        )
    }
}
