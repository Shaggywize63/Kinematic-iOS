import SwiftUI

struct LeadRow: View {
    let lead: Lead

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(lead.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(uiColor: .label))
                Text(lead.company ?? lead.email ?? "—")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                ScoreBadge(score: lead.score ?? 0)
                Text((lead.status ?? "new").uppercased())
                    .font(.system(size: 9, weight: .black))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .foregroundColor(statusColor)
                    .cornerRadius(4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var initials: String {
        let f = (lead.firstName ?? "").prefix(1)
        let l = (lead.lastName ?? "").prefix(1)
        let s = "\(f)\(l)".uppercased()
        return s.isEmpty ? "L" : s
    }

    private var statusColor: Color {
        switch (lead.status ?? "").lowercased() {
        case "new": return .blue
        case "qualified": return .green
        case "contacted": return .orange
        case "unqualified": return .red
        case "converted": return .purple
        default: return .gray
        }
    }
}
