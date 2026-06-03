import SwiftUI

// "Boost this score" — mirrors the web ScoreBoostSuggestions card. Surfaces the
// scoring signals this lead is missing, each with the points it would add and
// an action. Vertical-specific items (GPS on a visit, monthly volume) only show
// for clients that use them (Tata Tiscon); generic CRM gaps show for everyone.
struct LeadScoreBoostCard: View {
    let lead: Lead
    let isTata: Bool
    let busy: Bool
    let onEdit: () -> Void
    let onQualify: () -> Void

    struct Suggestion: Identifiable {
        let id: String
        let label: String
        let points: Int
        let qualify: Bool
    }

    private var suggestions: [Suggestion] {
        var out: [Suggestion] = []
        let status = (lead.status ?? "new").lowercased()
        if !["qualified", "converted", "lost", "unqualified"].contains(status) {
            out.append(.init(id: "qualify", label: "Mark as Qualified once vetted", points: 18, qualify: true))
        }
        // Vertical (field-sales) signals — only for clients that use them.
        if isTata {
            let hasGps = (lead.latitude ?? 0) != 0 && (lead.longitude ?? 0) != 0
            if !hasGps { out.append(.init(id: "gps", label: "Capture GPS location on a visit", points: 8, qualify: false)) }
            let volStr = lead.customFields?["monthly_volume"]?.value ?? lead.customFields?["volume_mt"]?.value ?? ""
            if (Double(volStr) ?? 0) <= 0 {
                out.append(.init(id: "volume", label: "Record monthly volume (MT)", points: 8, qualify: false))
            }
        }
        if (lead.email ?? "").isEmpty { out.append(.init(id: "email", label: "Add an email address", points: 5, qualify: false)) }
        if (lead.city ?? "").isEmpty { out.append(.init(id: "city", label: "Set the city / location", points: 5, qualify: false)) }
        if (lead.firstName ?? "").isEmpty || (lead.lastName ?? "").isEmpty {
            out.append(.init(id: "name", label: "Add the full name", points: 4, qualify: false))
        }
        return Array(out.sorted { $0.points > $1.points }.prefix(6))
    }

    var body: some View {
        if suggestions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Boost this score").font(.headline)
                Text("Add the missing signals below to raise the lead score. Re-score after updating to see the new number.")
                    .font(.caption).foregroundColor(.secondary)
                ForEach(suggestions) { s in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.label).font(.system(size: 13, weight: .semibold)).foregroundColor(.primary)
                            Text("up to +\(s.points) pts").font(.system(size: 11, weight: .bold)).foregroundColor(.green)
                        }
                        Spacer()
                        Button(s.qualify ? "Mark Qualified" : "Add detail") {
                            if s.qualify { onQualify() } else { onEdit() }
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(s.qualify ? Brand.red : Color(uiColor: .secondarySystemBackground))
                        .foregroundColor(s.qualify ? .white : .primary)
                        .clipShape(Capsule())
                        .disabled(busy)
                        .opacity(busy ? 0.6 : 1)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .tertiarySystemBackground)))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
        }
    }
}
