//
//  KiniCreditsView.swift
//  Kinematic — small horizontal pill displaying KINI usage in the chat
//  navigation bar.
//
//  Mirrors the dashboard's KinematicAI pill: shows the caller's per-user
//  monthly count (used/cap). The cap respects per-client overrides
//  (e.g. Tata Tiscon users → 20). Tap to reveal a popover with the
//  org-wide breakdown and platform split — useful for admins.
//
//  - GET /api/v1/crm/ai/usage   → per-user used / cap (pill foreground)
//  - GET /api/v1/crm/ai/credits → org-wide breakdown (popover only)
//

import SwiftUI

struct KiniCreditsView: View {
    @State private var usage: KiniUsage?
    @State private var credits: KiniCredits?
    @State private var loading = true
    @State private var showBreakdown = false

    /// Bump from the chat VM after each reply so the pill refreshes
    /// without polling.
    var refreshTrigger: Int = 0

    var body: some View {
        Group {
            if let u = usage, !u.exempt {
                pill(used: u.used, cap: u.cap)
                    .onTapGesture { showBreakdown.toggle() }
                    .popover(isPresented: $showBreakdown, arrowEdge: .top) {
                        breakdownPopover(user: u, org: credits)
                    }
            } else if loading {
                ProgressView().scaleEffect(0.6)
                    .frame(width: 60, height: 22)
            } else {
                // exempt user (super_admin/demo) or failed silently —
                // don't block the chat over a meter.
                EmptyView()
            }
        }
        .task { await load() }
        .onChange(of: refreshTrigger) { _, _ in
            Task { await load() }
        }
    }

    private func pill(used: Int, cap: Int) -> some View {
        let remaining = max(0, cap - used)
        let ratio = cap > 0 ? Double(used) / Double(cap) : 0
        let tint: Color = ratio >= 1.0 ? .red : (ratio >= 0.8 ? .orange : .secondary)
        return HStack(spacing: 4) {
            Image(systemName: "bolt.fill").font(.caption2)
            Text("\(used)/\(cap)").font(.caption.monospacedDigit())
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color(uiColor: .secondarySystemBackground))
        )
        .accessibilityLabel("KINI queries used \(used) of \(cap), \(remaining) remaining")
    }

    private func breakdownPopover(user: KiniUsage, org: KiniCredits?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This month").font(.headline)
            HStack {
                Text("You"); Spacer()
                Text("\(user.used) / \(user.cap)").monospacedDigit()
            }
            if let org {
                Divider()
                HStack {
                    Text("Org total"); Spacer()
                    Text("\(org.used) / \(org.limit)").monospacedDigit()
                }
                row(label: "Web",     value: org.platformBreakdown.web)
                row(label: "iOS",     value: org.platformBreakdown.ios)
                row(label: "Android", value: org.platformBreakdown.android)
                Divider()
                Text("Resets \(org.periodEnd)")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(minWidth: 180)
        .presentationCompactAdaptation(.popover)
    }

    private func row(label: String, value: Int) -> some View {
        HStack { Text(label); Spacer(); Text("\(value)").monospacedDigit() }
            .font(.subheadline)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        // Per-user counter is the primary display — fetch first so the
        // pill renders even if the org-wide call fails.
        usage = (try? await AIChatService.shared.getUsage())
        credits = (try? await AIChatService.shared.getCredits())
    }
}
