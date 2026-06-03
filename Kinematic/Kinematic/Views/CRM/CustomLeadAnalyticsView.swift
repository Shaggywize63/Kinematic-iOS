import SwiftUI

// Layout-driven Lead Analytics — reads the per-user widget layout from
// /crm/dashboard-layouts/analytics (the SAME config the web customisable Lead
// Analytics page writes), renders each chosen widget natively, and lets the
// user add/remove widgets. Saving PUTs the layout back so web ↔ app stay in
// sync. Each widget renders generically (top rows of its analytics endpoint as
// a labelled bar list), so all 15 catalogue widgets work.

struct AnalyticsWidgetMeta: Identifiable {
    let type: String
    let title: String
    let endpoint: String        // under /api/v1/crm
    var id: String { type }
}

enum LeadAnalyticsCatalog {
    static let widgets: [AnalyticsWidgetMeta] = [
        .init(type: "lead_velocity", title: "Lead Velocity Rate", endpoint: "/api/v1/crm/analytics/lead-velocity"),
        .init(type: "time_to_first_touch", title: "Time to First Touch", endpoint: "/api/v1/crm/analytics/time-to-first-touch"),
        .init(type: "stuck_leads", title: "Stuck Leads", endpoint: "/api/v1/crm/analytics/stuck-leads"),
        .init(type: "lost_reasons", title: "Top Lost Reasons", endpoint: "/api/v1/crm/analytics/lost-reasons"),
        .init(type: "won_reasons", title: "Top Won Reasons", endpoint: "/api/v1/crm/analytics/won-reasons"),
        .init(type: "disqualification_reasons", title: "Disqualification Reasons", endpoint: "/api/v1/crm/analytics/disqualification-reasons"),
        .init(type: "stage_conversion", title: "Stage Conversion %", endpoint: "/api/v1/crm/analytics/stage-conversion"),
        .init(type: "lead_aging", title: "Lead Aging", endpoint: "/api/v1/crm/analytics/lead-aging"),
        .init(type: "cohort_conversion", title: "Cohort Conversion", endpoint: "/api/v1/crm/analytics/cohort-conversion"),
        .init(type: "engagement_comparison", title: "Touches: Won vs Lost", endpoint: "/api/v1/crm/analytics/engagement-comparison"),
        .init(type: "days_since_touch", title: "Days Since Last Touch", endpoint: "/api/v1/crm/analytics/days-since-touch"),
        .init(type: "score_band_conversion", title: "Score-Band Conversion", endpoint: "/api/v1/crm/analytics/score-band-conversion"),
        .init(type: "territory_conversion", title: "Territory Conversion", endpoint: "/api/v1/crm/analytics/territory-conversion"),
        .init(type: "touchpoints_to_response", title: "Touchpoints to Response", endpoint: "/api/v1/crm/analytics/touchpoints-to-response"),
        .init(type: "leads_at_risk", title: "Leads at Risk", endpoint: "/api/v1/crm/analytics/leads-at-risk"),
    ]
    static func meta(_ type: String) -> AnalyticsWidgetMeta? { widgets.first { $0.type == type } }
    /// Sensible default selection before the user customises anything.
    static let defaults = ["lead_velocity", "lead_aging", "stuck_leads", "lost_reasons", "score_band_conversion", "leads_at_risk"]
}

struct CustomLeadAnalyticsView: View {
    @State private var enabledTypes: [String] = []
    @State private var loading = true
    @State private var showCustomize = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if loading {
                    ProgressView().padding(.top, 40)
                } else if enabledTypes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.pie").font(.largeTitle).foregroundColor(.secondary)
                        Text("No analytics widgets yet.").foregroundColor(.secondary)
                        Button("Add widgets") { showCustomize = true }.buttonStyle(.borderedProminent).tint(Brand.red)
                    }.padding(.top, 60)
                } else {
                    ForEach(enabledTypes, id: \.self) { type in
                        if let meta = LeadAnalyticsCatalog.meta(type) {
                            AnalyticsWidgetCard(meta: meta)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Lead Analytics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCustomize = true } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $showCustomize) {
            CustomizeAnalyticsSheet(enabledTypes: enabledTypes) { newTypes in
                enabledTypes = newTypes
                Task { await CRMService.shared.saveAnalyticsLayout(types: newTypes) }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        let widgets = (try? await CRMService.shared.getAnalyticsLayout()) ?? []
        let types = widgets.map { $0.widget_type }.filter { LeadAnalyticsCatalog.meta($0) != nil }
        await MainActor.run {
            enabledTypes = types.isEmpty ? LeadAnalyticsCatalog.defaults : types
            loading = false
        }
    }
}

// Renders one widget: top rows of its endpoint as a labelled bar list.
private struct AnalyticsWidgetCard: View {
    let meta: AnalyticsWidgetMeta
    @State private var rows: [(label: String, value: Double)] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(meta.title).font(.headline)
            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else if rows.isEmpty {
                Text("No data.").font(.caption).foregroundColor(.secondary)
            } else {
                let maxV = max(rows.map { $0.value }.max() ?? 1, 1)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(r.label).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Text(format(r.value)).font(.system(size: 12, weight: .bold))
                        }
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Brand.red.opacity(0.85))
                                .frame(width: max(geo.size.width * CGFloat(r.value / maxV), 2), height: 6)
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
        .task { await load() }
    }

    private func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func load() async {
        loading = true
        let data = (try? await CRMService.shared.analyticsReport(meta.endpoint)) ?? []
        // Pick the first string-ish column as the label and the first numeric
        // column as the value — works generically across widget shapes.
        let built: [(String, Double)] = data.prefix(8).compactMap { row in
            var label: String? = nil
            var value: Double? = nil
            for (_, v) in row {
                switch v.value {
                case let s as String where label == nil: label = s
                case let d as Double where value == nil: value = d
                default: break
                }
            }
            guard let l = label, let val = value else { return nil }
            return (l, val)
        }
        await MainActor.run { rows = built.map { (label: $0.0, value: $0.1) }; loading = false }
    }
}

private struct CustomizeAnalyticsSheet: View {
    @State var enabledTypes: [String]
    let onSave: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text("Your selection syncs with the web Lead Analytics page.")) {
                    ForEach(LeadAnalyticsCatalog.widgets) { w in
                        Button {
                            if enabledTypes.contains(w.type) { enabledTypes.removeAll { $0 == w.type } }
                            else { enabledTypes.append(w.type) }
                        } label: {
                            HStack {
                                Text(w.title).foregroundColor(.primary)
                                Spacer()
                                if enabledTypes.contains(w.type) {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(Brand.red)
                                } else {
                                    Image(systemName: "circle").foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Customise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(enabledTypes); dismiss() } }
            }
        }
    }
}
