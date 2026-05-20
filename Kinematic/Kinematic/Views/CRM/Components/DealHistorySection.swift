import SwiftUI

/// History section for a deal — stage transitions, amount edits and
/// create/update audit rows pulled from `/deals/:id/history`.
struct DealHistorySection: View {
    let dealId: String

    @State private var events: [DealHistoryEvent] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(Brand.red)
                Text("HISTORY")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .foregroundColor(Brand.red)
                Spacer()
                if loaded && !events.isEmpty {
                    Text("\(events.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }

            if !loaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if events.isEmpty {
                Text("No history yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(events.prefix(50)) { ev in
                        DealHistoryRow(event: ev)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .task(id: dealId) {
            let list = (try? await CRMService.shared.dealHistory(dealId: dealId)) ?? []
            events = list
            loaded = true
        }
    }
}

private struct DealHistoryRow: View {
    let event: DealHistoryEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(iconTint.opacity(0.15)).frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(iconTint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(uiColor: .label))
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(relativeTime)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Presentation

    private var iconName: String {
        switch event.eventType {
        case "stage_changed":  return "arrow.right.circle.fill"
        case "amount_changed": return "indianrupeesign.circle.fill"
        case "created":        return "sparkles"
        case "updated":        return "pencil.circle.fill"
        default:               return "circle.fill"
        }
    }

    private var iconTint: Color {
        switch event.eventType {
        case "stage_changed":  return Brand.red
        case "amount_changed": return .green
        case "created":        return .blue
        case "updated":        return .orange
        default:               return .secondary
        }
    }

    private var headline: String {
        switch event.eventType {
        case "stage_changed":
            let from = event.fromStage ?? "—"
            let to   = event.toStage ?? "—"
            return "Stage: \(from) → \(to)"
        case "amount_changed":
            let from = formatAmount(event.fromAmount)
            let to   = formatAmount(event.toAmount)
            return "Amount: \(from) → \(to)"
        case "created":
            return "Deal created"
        case "updated":
            return "Deal updated"
        default:
            return event.eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var subtitle: String? {
        // Reserved for future per-event detail (e.g. who changed it).
        nil
    }

    private var relativeTime: String {
        guard let raw = event.createdAt,
              let date = ISO8601DateFormatter.parse(raw) else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func formatAmount(_ value: Double?) -> String {
        CurrencyFormatter.formatINR(value)
    }
}

private extension ISO8601DateFormatter {
    /// Parse with and without fractional seconds — the backend mixes both
    /// shapes depending on the audit table the row was written from.
    static func parse(_ s: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: s) { return d }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: s)
    }
}
