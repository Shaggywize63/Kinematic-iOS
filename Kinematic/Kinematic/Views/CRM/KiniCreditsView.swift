//
//  KiniCreditsView.swift
//  Kinematic — small horizontal pill displaying KINI org-wide credit usage.
//
//  Polls /api/v1/crm/ai/credits on appear. Long-press exposes a per-platform
//  breakdown popover so admins can see which clients are consuming most.
//

import SwiftUI

struct KiniCreditsView: View {
    @State private var credits: KiniCredits?
    @State private var loading = true
    @State private var showBreakdown = false

    /// Optional external trigger: pass a binding that increments whenever a
    /// chat reply lands so the pill stays in sync without polling.
    var refreshTrigger: Int = 0

    var body: some View {
        Group {
            if let c = credits {
                pill(used: c.used, limit: c.limit)
                    .onTapGesture { showBreakdown.toggle() }
                    .popover(isPresented: $showBreakdown, arrowEdge: .top) {
                        breakdownPopover(c)
                    }
            } else if loading {
                ProgressView().scaleEffect(0.6)
                    .frame(width: 60, height: 22)
            } else {
                // Failed silently — don't block the chat over a meter.
                EmptyView()
            }
        }
        .task { await load() }
        .onChange(of: refreshTrigger) { _, _ in
            Task { await load() }
        }
    }

    private func pill(used: Int, limit: Int) -> some View {
        let remaining = max(0, limit - used)
        let ratio = limit > 0 ? Double(used) / Double(limit) : 0
        let tint: Color = ratio >= 1.0 ? .red : (ratio >= 0.8 ? .orange : .secondary)
        return HStack(spacing: 4) {
            Image(systemName: "bolt.fill").font(.caption2)
            Text("\(used)/\(limit)").font(.caption.monospacedDigit())
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color(uiColor: .secondarySystemBackground))
        )
        .accessibilityLabel("KINI credits used \(used) of \(limit), \(remaining) remaining")
    }

    private func breakdownPopover(_ c: KiniCredits) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This month").font(.headline)
            HStack {
                Text("Total"); Spacer()
                Text("\(c.used) / \(c.limit)").monospacedDigit()
            }
            Divider()
            row(label: "Web",     value: c.platformBreakdown.web)
            row(label: "iOS",     value: c.platformBreakdown.ios)
            row(label: "Android", value: c.platformBreakdown.android)
            Divider()
            Text("Resets \(c.periodEnd)")
                .font(.caption).foregroundColor(.secondary)
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
        do {
            credits = try await AIChatService.shared.getCredits()
        } catch {
            credits = nil
        }
    }
}
