import SwiftUI

// MARK: - Screen Overview
//
// A static "map" of the Leads screen that names every major button and what
// it does. Companion to the step-by-step GuidedTourView / spotlight tour —
// this is the at-a-glance legend rather than a walkthrough. Mirrors the
// Android ScreenOverviewScreen one-to-one.
//
// Deliberately self-contained (a lightweight mock, not the live screen) so
// it's easy to maintain. No built-in field is rendered — pure onboarding UI.

private struct OverviewItem: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
    let desc: String
}

private struct OverviewSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [OverviewItem]
}

private let leadsOverview: [OverviewSection] = [
    .init(title: "Top bar", items: [
        .init(icon: "magnifyingglass", name: "Search", desc: "Find a lead by name or phone number."),
        .init(icon: "plus", name: "Add lead", desc: "Create a new lead in seconds — just a name and mobile."),
    ]),
    .init(title: "On a lead", items: [
        .init(icon: "hand.tap.fill", name: "Open a lead", desc: "Tap a lead row to see its full profile and history."),
        .init(icon: "phone.fill", name: "Call", desc: "Call the lead in one tap — the call is logged for you."),
        .init(icon: "message.fill", name: "WhatsApp", desc: "Message on WhatsApp without copying the number."),
    ]),
    .init(title: "Assistant", items: [
        .init(icon: "sparkles", name: "KINI", desc: "Ask KINI to draft messages, add leads and more."),
    ]),
    .init(title: "Bottom navigation", items: [
        .init(icon: "chart.bar.fill", name: "Dashboard", desc: "KPIs, charts and your targets."),
        .init(icon: "person.crop.circle.badge.plus", name: "Leads", desc: "Your lead list — capture and track."),
        .init(icon: "indianrupeesign.circle.fill", name: "Deals", desc: "Opportunities and the pipeline."),
        .init(icon: "checkmark.square.fill", name: "Activities", desc: "Calls, visits, meetings and tasks."),
        .init(icon: "ellipsis.circle", name: "More", desc: "Reports, settings, guided tour and more."),
    ]),
]

struct ScreenOverviewView: View {
    var body: some View {
        List {
            Section {
                LeadsScreenMock()
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            } footer: {
                Text("A map of the Leads screen — here's what every button does.")
            }
            ForEach(leadsOverview) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Brand.red.opacity(0.16))
                                    .frame(width: 38, height: 38)
                                Image(systemName: item.icon).foregroundStyle(Brand.red)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.body.weight(.semibold))
                                Text(item.desc).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Screen overview")
    }
}

// MARK: - Lightweight Leads-screen mock (for spatial context)

private struct LeadsScreenMock: View {
    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("Leads").font(.headline)
                Spacer()
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.red)
                Image(systemName: "plus").foregroundStyle(Brand.red)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider()
            leadRow("RS", "Rahul Sharma", "+91 98765 43210", emphasised: true)
            Divider().padding(.leading, 66)
            leadRow("AP", "Anita Patel", "+91 91234 56780", emphasised: false)
            Spacer(minLength: 14)
            Divider()
            // Bottom navigation
            HStack {
                navItem("chart.bar.fill", "Dashboard", selected: false)
                navItem("person.crop.circle.badge.plus", "Leads", selected: true)
                navItem("indianrupeesign.circle.fill", "Deals", selected: false)
                navItem("checkmark.square.fill", "Activities", selected: false)
                navItem("ellipsis.circle", "More", selected: false)
            }
            .padding(.vertical, 8)
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            // Floating KINI assistant button
            Image(systemName: "sparkles")
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Brand.red))
                .padding(.trailing, 14).padding(.bottom, 60)
        }
    }

    private func leadRow(_ initials: String, _ name: String, _ phone: String, emphasised: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Brand.red.opacity(emphasised ? 0.16 : 0.08)).frame(width: 38, height: 38)
                Text(initials).font(.caption.weight(.semibold)).foregroundStyle(emphasised ? Brand.red : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(phone).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "phone.fill").foregroundStyle(Brand.red)
            Image(systemName: "message.fill").foregroundStyle(Brand.red)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func navItem(_ icon: String, _ label: String, selected: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
            Text(label).font(.system(size: 9))
        }
        .foregroundStyle(selected ? Brand.red : Color.secondary.opacity(0.7))
        .frame(maxWidth: .infinity)
    }
}
