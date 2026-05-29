import SwiftUI

/**
 * Redesigned lead row — punchier than the v1 plain-row layout. Mirrors
 * the Android LeadCard so the two platforms feel like one product.
 *
 *   ┌───────────────────────────────────────────────────────┐
 *   │ ╱╲                                                    │
 *   │╱RA╲  Rohan Agarwal               ┌──┐  A   87         │
 *   │╲  ╱  Acme Corp · CTO              └──┘                │
 *   │ ╲╱   ● Qualified · Inbound                            │
 *   └───────────────────────────────────────────────────────┘
 *
 * - Gradient avatar (palette derived from the lead id so the same
 *   person always gets the same colour in long lists).
 * - Score chip with grade letter beside the number for at-a-glance
 *   "this is an A-grade hot lead" reading.
 * - Status dot + label + optional source on a single inline meta row.
 * - 1pt outline + subtle shadow so the card lifts off the background
 *   without leaning entirely on red.
 */
struct LeadRow: View {
    let lead: Lead

    var body: some View {
        HStack(spacing: 14) {
            // Gradient avatar — deterministic palette per lead.
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: avatarPalette,
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                Text(initials)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(lead.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(uiColor: .label))
                    .lineLimit(1)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                // Inline meta row — keeps the card height compact while
                // still surfacing status + source.
                if !metaRow.isEmpty {
                    HStack(spacing: 6) {
                        if let s = lead.status, !s.isEmpty {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 7, height: 7)
                            Text(s.capitalized)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(statusColor)
                        }
                        if let src = sourceLabel {
                            if lead.status != nil && lead.status?.isEmpty == false {
                                Text("·").font(.system(size: 11)).foregroundColor(.secondary)
                            }
                            Text(src.capitalized)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            LeadScoreChip(score: Int(lead.score ?? 0))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    // MARK: - Derived

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
        if !s.isEmpty { return s }
        if let c = lead.company?.first { return String(c).uppercased() }
        if let e = lead.email?.first { return String(e).uppercased() }
        return "L"
    }

    private var sourceLabel: String? {
        let s = lead.source?.trimmingCharacters(in: .whitespacesAndNewlines)
        return s?.isEmpty == false ? s : nil
    }

    private var metaRow: String {
        var parts: [String] = []
        if let s = lead.status, !s.isEmpty { parts.append(s) }
        if let src = sourceLabel { parts.append(src) }
        return parts.joined(separator: " · ")
    }

    /// Curated palette — same set as Android so a given lead gets the
    /// same colour identity across both apps.
    private var avatarPalette: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.878, green: 0.118, blue: 0.173), Color(red: 1.0,   green: 0.42,  blue: 0.36)],   // brand red → coral
            [Color(red: 0.388, green: 0.4,   blue: 0.945), Color(red: 0.545, green: 0.361, blue: 0.965)],  // indigo → violet
            [Color(red: 0.063, green: 0.725, blue: 0.506), Color(red: 0.204, green: 0.827, blue: 0.6)],   // emerald → mint
            [Color(red: 0.961, green: 0.62,  blue: 0.043), Color(red: 0.984, green: 0.749, blue: 0.141)], // amber → gold
            [Color(red: 0.055, green: 0.647, blue: 0.914), Color(red: 0.22,  green: 0.741, blue: 0.973)], // sky → blue
            [Color(red: 0.925, green: 0.282, blue: 0.6),  Color(red: 0.957, green: 0.447, blue: 0.714)],  // pink → magenta
            [Color(red: 0.078, green: 0.722, blue: 0.651), Color(red: 0.176, green: 0.831, blue: 0.749)], // teal → cyan
        ]
        // `lead.id` is non-optional on iOS; fall through to email / phone
        // only when the id happens to be empty (shouldn't happen, but the
        // chain keeps the avatar gradient stable across re-renders).
        let seed = !lead.id.isEmpty ? lead.id : (lead.email ?? lead.phone ?? "lead")
        let h = abs(seed.hashValue)
        return palettes[h % palettes.count]
    }

    private var statusColor: Color {
        switch (lead.status ?? "").lowercased() {
        case "new":          return Color(red: 0.055, green: 0.647, blue: 0.914)
        case "contacted":    return Color(red: 0.388, green: 0.4,   blue: 0.945)
        case "qualified":    return Color(red: 0.063, green: 0.725, blue: 0.506)
        case "unqualified":  return .secondary
        case "converted":    return Color(red: 0.078, green: 0.722, blue: 0.651)
        case "lost":         return Color(red: 0.937, green: 0.267, blue: 0.267)
        default:             return Brand.red
        }
    }
}

/**
 * Score chip — grade letter (A/B/C/D) badge + numeric score, same
 * visual language as the Android LeadScoreChip so the rep sees the
 * same metric component on both platforms.
 */
struct LeadScoreChip: View {
    let score: Int
    var band: String? = nil

    var body: some View {
        let tier = (band?.uppercased().first.map(String.init))
            ?? defaultTier(for: score)
        let tint = color(for: tier)
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(tint).frame(width: 22, height: 22)
                Text(tier)
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.white)
            }
            Text("\(score)")
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(tint)
        }
    }

    private func defaultTier(for s: Int) -> String {
        if s >= 75 { return "A" }
        if s >= 55 { return "B" }
        if s >= 35 { return "C" }
        return "D"
    }

    private func color(for tier: String) -> Color {
        switch tier {
        case "A": return Color(red: 0.063, green: 0.725, blue: 0.506)
        case "B": return Color(red: 0.984, green: 0.749, blue: 0.141)
        case "C": return Color(red: 0.984, green: 0.573, blue: 0.235)
        default:  return Color(red: 0.937, green: 0.267, blue: 0.267)
        }
    }
}
