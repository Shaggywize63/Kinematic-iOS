import SwiftUI

struct LeadRow: View {
    let lead: Lead

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Brand.red, Brand.red.opacity(0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(lead.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(uiColor: .label))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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

    /// Subtitle falls back through the most-useful identifier the lead has.
    /// Returns nil when nothing's set so the row hides the line entirely
    /// instead of showing a useless "—" placeholder.
    private var subtitle: String? {
        let candidates: [String?] = [lead.company, lead.email, lead.phone, lead.city]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private var initials: String {
        let f = (lead.firstName ?? "").prefix(1)
        let l = (lead.lastName ?? "").prefix(1)
        let s = "\(f)\(l)".uppercased()
        return s.isEmpty ? "L" : s
    }

    // Single-accent status palette: every "live" status reads as red; only
    // unqualified / muted states drop to neutral grey so the row still
    // signals that the lead's pipeline activity has stalled.
    private var statusColor: Color {
        switch (lead.status ?? "").lowercased() {
        case "unqualified", "lost": return .secondary
        default: return Brand.red
        }
    }
}
