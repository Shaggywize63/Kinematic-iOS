import SwiftUI

/// CRM activity row — redesigned to read like a polished feed entry rather
/// than a sparse two-liner. Mirrors the web dashboard's status pills + type
/// badges so a rep flipping between mobile and web sees the same metadata
/// shape (status, type, when, owner) on every row.
struct ActivityTimelineItem: View {
    let activity: Activity
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Header row: type badge → subject → status pill ──────────
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(typeAccent.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: typeIcon)
                        .foregroundColor(typeAccent)
                        .font(.system(size: 15, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.subject ?? activity.type?.capitalized ?? "Activity")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(uiColor: .label))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        TypeChip(label: (activity.type ?? "activity").replacingOccurrences(of: "_", with: " ").capitalized, tint: typeAccent)
                        StatusPill(status: activity.effectiveStatus)
                    }
                }
                Spacer(minLength: 0)
                if let when = displayDate {
                    Text(when)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            // ── Body: description + optional photo ──────────────────────
            if let d = activity.description, !d.isEmpty {
                Text(d)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .padding(.leading, 50) // indent under the type badge
            }

            if let urlString = activity.imageUrl,
               !urlString.isEmpty {
                // Private-bucket photo: sign the URL for BOTH the thumbnail and
                // the tap-to-open action (PR-1). Resolve on tap so the opened
                // link is a fresh signed URL, not the now-403 raw object URL.
                Button {
                    Task {
                        if let signed = await MediaSigning.shared.resolvedURL(for: urlString) {
                            openURL(signed)
                        }
                    }
                } label: {
                    SignedAsyncImage(urlString: urlString) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                                ProgressView()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        case .failure:
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 50)
            }

            // ── Footer: meta row (owner, duration, direction) ──────────
            if hasFooterMeta {
                HStack(spacing: 10) {
                    if let owner = activity.ownerName?.trimmingCharacters(in: .whitespaces), !owner.isEmpty {
                        MetaChip(icon: "person.crop.circle.fill", text: owner)
                    }
                    if let mins = activity.durationMinutes, mins > 0 {
                        MetaChip(icon: "clock.fill", text: "\(mins) min")
                    }
                    if let dir = activity.direction?.trimmingCharacters(in: .whitespaces), !dir.isEmpty {
                        MetaChip(
                            icon: dir.lowercased() == "outbound" ? "arrow.up.right" : "arrow.down.left",
                            text: dir.capitalized
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 50)
            }

            // ── Linked record: lead / contact / deal name ───────────────
            // Backend stamps lead_name, contact_name, deal_name on every
            // activity response so we can surface context inline without a
            // secondary fetch. Priority: lead → contact → deal.
            if let linkedName = linkedRecordName {
                HStack(spacing: 5) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Brand.red)
                    Text(linkedName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Brand.red)
                        .lineLimit(1)
                }
                .padding(.leading, 50)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: Derived

    /// The best available linked-record name to display on the card.
    /// Falls back through lead → contact → deal so the card always shows
    /// some context if the backend stamped any of the three fields.
    private var linkedRecordName: String? {
        if let n = activity.leadName?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        if let n = activity.contactName?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        if let n = activity.dealName?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return nil
    }

    private var hasFooterMeta: Bool {
        (activity.ownerName?.isEmpty == false) ||
        (activity.durationMinutes ?? 0) > 0 ||
        (activity.direction?.isEmpty == false)
    }

    /// The "when" suffix that reads as "today / yesterday / 25 Jun" etc.
    /// Falls back to the raw YYYY-MM-DD prefix if the backend ships an
    /// unparseable shape.
    private var displayDate: String? {
        let raw = activity.completedAt ?? activity.dueAt ?? activity.createdAt
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date = parsed else { return String(raw.prefix(10)) }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    private var typeIcon: String {
        switch (activity.type ?? "").lowercased() {
        case "call":         return "phone.fill"
        case "email":        return "envelope.fill"
        case "meeting":      return "person.2.fill"
        case "note":         return "note.text"
        case "task":         return "checkmark.square.fill"
        case "whatsapp":     return "bubble.left.and.bubble.right.fill"
        case "site_visit", "visit": return "mappin.and.ellipse"
        default:             return "circle.fill"
        }
    }

    /// Per-type accent so the badge / type chip read at a glance.
    private var typeAccent: Color {
        switch (activity.type ?? "").lowercased() {
        case "call":     return Color(red: 0.20, green: 0.55, blue: 0.95)
        case "email":    return Color(red: 0.55, green: 0.30, blue: 0.95)
        case "meeting":  return Color(red: 0.96, green: 0.62, blue: 0.16)
        case "note":     return Color(red: 0.55, green: 0.55, blue: 0.55)
        case "task":     return Brand.red
        case "whatsapp": return Color(red: 0.145, green: 0.827, blue: 0.4)
        case "site_visit", "visit": return Color(red: 0.16, green: 0.74, blue: 0.50)
        default:         return Color(red: 0.55, green: 0.55, blue: 0.55)
        }
    }
}

// MARK: - Pills

private struct StatusPill: View {
    let status: String
    var body: some View {
        let (fg, bg) = StatusPill.palette(for: status)
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundColor(fg)
            .background(Capsule().fill(bg))
            .overlay(Capsule().stroke(fg.opacity(0.25), lineWidth: 0.5))
    }
    /// Match the web dashboard's status palette so reps see identical chips
    /// on every surface they switch between.
    static func palette(for status: String) -> (Color, Color) {
        switch status.lowercased() {
        case "completed":
            return (Color(red: 0.05, green: 0.55, blue: 0.30), Color(red: 0.05, green: 0.55, blue: 0.30).opacity(0.14))
        case "in_progress", "in progress":
            return (Color(red: 0.75, green: 0.45, blue: 0.05), Color(red: 0.96, green: 0.62, blue: 0.16).opacity(0.16))
        case "cancelled", "canceled":
            return (Color(uiColor: .secondaryLabel), Color(uiColor: .secondaryLabel).opacity(0.14))
        case "open":
            return (Brand.red, Brand.red.opacity(0.14))
        default:
            return (Color(uiColor: .secondaryLabel), Color(uiColor: .secondaryLabel).opacity(0.14))
        }
    }
}

private struct TypeChip: View {
    let label: String
    let tint: Color
    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundColor(tint)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

private struct MetaChip: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.secondary)
    }
}
