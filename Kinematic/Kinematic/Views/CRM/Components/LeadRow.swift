import SwiftUI

struct LeadRow: View {
    let lead: Lead
    /// When non-nil the row is rendered in multi-select mode: a checkbox
    /// is shown on the leading edge instead of the avatar tap-acting as
    /// a navigation link, and the background tints when `selected` is true.
    var selected: Bool? = nil

    var body: some View {
        HStack(spacing: 14) {
            if let selected {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(selected ? Brand.red : .secondary)
                    .frame(width: 28)
            }

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
                // Latest update preview — denormalised onto the lead row
                // server-side every time someone POSTs to /updates. Shows
                // a one-liner truncation plus the relative timestamp so the
                // rep can scan "who's been worked recently" at a glance.
                if let body = lead.latestUpdate, !body.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Brand.red.opacity(0.7))
                        Text(body)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(uiColor: .label).opacity(0.85))
                            .lineLimit(1)
                        if let rel = relativeUpdateTime {
                            Text("· \(rel)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
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
                .fill(rowBackground)
        )
    }

    private var rowBackground: Color {
        if selected == true { return Brand.red.opacity(0.12) }
        return Color(uiColor: .secondarySystemBackground)
    }

    /// "5m ago", "2h ago", "3d ago". Returns nil if the timestamp is
    /// missing or unparseable — the row just hides the suffix in that
    /// case rather than rendering "ago" with no number.
    private var relativeUpdateTime: String? {
        guard let at = lead.latestUpdateAt,
              let date = LeadRow.iso.date(from: at) ?? LeadRow.isoFallback.date(from: at)
        else { return nil }
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3600))h ago" }
        if elapsed < 604_800 { return "\(Int(elapsed / 86_400))d ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

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
