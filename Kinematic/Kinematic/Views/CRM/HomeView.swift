//
//  HomeView.swift
//  Kinematic CRM
//
//  Daily mission control — mirrors the web /dashboard/crm/home and the
//  Android CrmHomeMissionTab. Reads top-to-bottom as one narrative:
//    1. Brand-gradient hero with greeting, target headline, and a
//       circular progress ring (achieved / target).
//    2. Top-3 next-best actions, each card carrying the rules-based
//       reasoning the backend produced (no LLM round-trip).
//    3. "Closest to closing" — grade A/B leads in qualified / SQL.
//    4. Today's activity stats (total + per-type counters).
//    5. Productivity playbook — data-driven nudges built off the rest
//       of the payload.
//
//  Drives off CRMService.crmHome() — one round-trip per appear / pull
//  to refresh. No section here makes its own request.
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var payload: HomePayload?
    @Published var loading: Bool = false
    @Published var refreshing: Bool = false
    @Published var error: String?

    func load(silent: Bool = false) async {
        if silent { refreshing = true } else if payload == nil { loading = true }
        error = nil
        do {
            let p = try await CRMService.shared.crmHome()
            payload = p
        } catch {
            self.error = (error as? CRMServiceError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
        refreshing = false
    }
}

// MARK: - HomeView

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var selectedLeadId: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let p = vm.payload {
                    heroCard(target: p.todayTarget)
                    section(title: "Next best actions",
                            subtitle: "Ranked by urgency × score — each suggestion explains why.") {
                        if p.nextActions.isEmpty {
                            EmptyCard(text: "You're clear. Use the time to source new leads or polish stuck deals.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(Array(p.nextActions.enumerated()), id: \.element.id) { idx, action in
                                    NextActionCard(order: idx + 1, action: action) {
                                        selectedLeadId = action.leadId
                                    }
                                }
                            }
                        }
                    }

                    section(title: "Closest to closing",
                            subtitle: "Grade A/B leads in qualified / SQL. Mornings have higher connect rates.") {
                        if p.nearToClose.isEmpty {
                            EmptyCard(text: "No high-grade qualified leads yet. Score and qualify a few from your open list to unlock this.")
                        } else {
                            VStack(spacing: 8) {
                                ForEach(p.nearToClose) { lead in
                                    NearLeadRow(lead: lead) {
                                        selectedLeadId = lead.id
                                    }
                                }
                            }
                        }
                    }

                    section(title: "Today's activity",
                            subtitle: subtitleForActivity(p.todayActivity)) {
                        ActivityStatStrip(stats: p.todayActivity)
                    }

                    section(title: "Productivity playbook",
                            subtitle: "Data-driven nudges built from your day so far.") {
                        VStack(spacing: 10) {
                            ForEach(Array(p.productivityTips.enumerated()), id: \.offset) { idx, tip in
                                TipCard(order: idx + 1, text: tip)
                            }
                        }
                    }
                } else if vm.loading {
                    ProgressView()
                        .padding(.top, 80)
                } else if let err = vm.error {
                    ErrorState(message: err) { Task { await vm.load() } }
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
        .refreshable { await vm.load(silent: true) }
        .task { await vm.load() }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedLeadId) { id in
            LeadDetailView(leadId: id)
        }
    }

    // MARK: Hero

    @ViewBuilder
    private func heroCard(target: HomeTarget?) -> some View {
        let achieved = target?.achieved ?? 0
        let total = target?.target ?? 0
        let pct = target?.progressPct ?? 0
        let headline = target?.headline ?? "Here's your day."
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(greeting()), \(firstName())".uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundColor(.white.opacity(0.88))
                    Text(headline)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if target?.hasTarget ?? false {
                        HStack(spacing: 6) {
                            HeroPill(label: "Target", value: "\(achieved)/\(total)")
                            HeroPill(label: "Pace",   value: "\(pct)%")
                        }
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
                ProgressRing(progressPct: pct, achieved: achieved, target: total)
            }
            .padding(20)

            // Refresh affordance pinned to the top-right of the hero.
            // Doubles as the spinner during pull-to-refresh fetches.
            Button {
                Task { await vm.load(silent: true) }
            } label: {
                if vm.refreshing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(14)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.88, green: 0.11, blue: 0.28), Color(red: 0.72, green: 0.11, blue: 0.24)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(red: 0.88, green: 0.11, blue: 0.28).opacity(0.25), radius: 12, x: 0, y: 6)
    }

    // MARK: Section utility

    @ViewBuilder
    private func section<Content: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .heavy))
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary) }
            }
            content()
        }
    }

    private func subtitleForActivity(_ stats: HomeActivityStats?) -> String {
        if let iso = stats?.lastActivityAt, !iso.isEmpty {
            return "Last logged \(formatAgo(iso))"
        }
        return "Nothing logged yet — your first entry sets the streak."
    }
}

// MARK: - Subcomponents

private struct HeroPill: View {
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            Text(value).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
            Text(label).font(.system(size: 10)).foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.18)))
    }
}

private struct ProgressRing: View {
    let progressPct: Int
    let achieved: Int
    let target: Int
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.22), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progressPct, 0), 100)) / 100)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(achieved)").font(.system(size: 22, weight: .heavy)).foregroundColor(.white)
                Text("of \(target > 0 ? "\(target)" : "—")")
                    .font(.system(size: 10))
                    .tracking(0.6)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(width: 96, height: 96)
    }
}

private struct NextActionCard: View {
    let order: Int
    let action: HomeNextAction
    let onTap: () -> Void
    private var urgencyColor: Color {
        switch action.urgency?.lowercased() {
        case "high":   return Color(red: 0.88, green: 0.11, blue: 0.28)
        case "medium": return Color(red: 0.96, green: 0.62, blue: 0.16)
        default:       return Color(red: 0.06, green: 0.73, blue: 0.51)
        }
    }
    private var urgencyLabel: String {
        switch action.urgency?.lowercased() {
        case "high":   return "High urgency"
        case "medium": return "This week"
        default:       return "When you can"
        }
    }
    private var iconName: String {
        switch action.action?.lowercased() {
        case "call": return "phone.fill"
        case "whatsapp": return "bubble.left.fill"
        case "meeting": return "calendar.badge.clock"
        case "create_deal": return "indianrupeesign.circle.fill"
        case "qualify": return "sparkles"
        case "follow_up": return "arrow.up.right.circle.fill"
        default: return "person.crop.circle.badge.plus"
        }
    }
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                Text("#\(order) · \(urgencyLabel)".uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(urgencyColor)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(urgencyColor.opacity(0.14)))
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(urgencyColor.opacity(0.14))
                        Image(systemName: iconName).foregroundColor(urgencyColor).font(.system(size: 18, weight: .semibold))
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.label ?? "Next action")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.primary)
                        if let score = action.score {
                            let gradeBit = action.scoreGrade.map { " · grade \($0)" } ?? ""
                            Text("Score \(score)\(gradeBit)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let reason = action.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.88))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 4) {
                    Text("Open \(action.leadName ?? "lead")")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(urgencyColor)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(urgencyColor)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

private struct NearLeadRow: View {
    let lead: HomeNearLead
    let onTap: () -> Void
    private var gradeColor: Color {
        switch lead.scoreGrade?.uppercased() {
        case "A": return Color(red: 0.09, green: 0.64, blue: 0.29)
        case "B": return Color(red: 0.23, green: 0.51, blue: 0.96)
        case "C": return Color(red: 0.96, green: 0.62, blue: 0.16)
        case "D": return Color(red: 0.94, green: 0.27, blue: 0.27)
        default:  return Color(red: 0.42, green: 0.45, blue: 0.50)
        }
    }
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(lead.scoreGrade ?? "–").font(.system(size: 14, weight: .black)).foregroundColor(gradeColor)
                    if let score = lead.score {
                        Text("\(score)").font(.system(size: 9, weight: .bold)).foregroundColor(gradeColor.opacity(0.8))
                    }
                }
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(gradeColor.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(lead.name ?? "Lead").font(.system(size: 14, weight: .bold)).foregroundColor(.primary).lineLimit(1)
                    if let reason = lead.reason, !reason.isEmpty {
                        Text(reason).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityStatStrip: View {
    let stats: HomeActivityStats?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StatCard(label: "Total",    value: stats?.total ?? 0,                accent: Color(red: 0.06, green: 0.73, blue: 0.51), system: "checkmark.circle.fill")
                StatCard(label: "Calls",    value: stats?.byType["call"] ?? 0,      accent: Color(red: 0.23, green: 0.51, blue: 0.96), system: "phone.fill")
                StatCard(label: "WhatsApp", value: stats?.byType["whatsapp"] ?? 0,  accent: Color(red: 0.09, green: 0.64, blue: 0.29), system: "bubble.left.fill")
                StatCard(label: "Meetings", value: stats?.byType["meeting"] ?? 0,   accent: Color(red: 0.96, green: 0.62, blue: 0.16), system: "calendar.badge.clock")
                StatCard(label: "Notes",    value: stats?.byType["note"] ?? 0,      accent: Color(red: 0.55, green: 0.36, blue: 0.96), system: "sparkles")
            }
        }
    }
}

private struct StatCard: View {
    let label: String
    let value: Int
    let accent: Color
    let system: String
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.16))
                Image(systemName: system).foregroundColor(accent).font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.5).foregroundColor(.secondary)
                Text("\(value)").font(.system(size: 18, weight: .heavy)).foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(minWidth: 132, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5))
    }
}

private struct TipCard: View {
    let order: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(order)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(Color(red: 0.88, green: 0.11, blue: 0.28))
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.88, green: 0.11, blue: 0.28).opacity(0.22),
                            Color(red: 0.88, green: 0.11, blue: 0.28).opacity(0.06),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5))
    }
}

private struct EmptyCard: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundColor(Color(uiColor: .separator).opacity(0.6)))
    }
}

private struct ErrorState: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash").foregroundColor(.red).font(.system(size: 30))
            Text(message).font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("Retry", action: onRetry).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Helpers

private func greeting() -> String {
    let h = Calendar.current.component(.hour, from: Date())
    switch h {
    case ..<5:  return "Up early"
    case ..<12: return "Good morning"
    case ..<17: return "Good afternoon"
    default:    return "Good evening"
    }
}

private func firstName() -> String {
    let raw = Session.currentUser?.name ?? ""
    let first = raw.split(separator: " ").first.map(String.init) ?? ""
    return first.isEmpty ? "there" : first
}

private func formatAgo(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return "" }
    let mins = max(0, Int(Date().timeIntervalSince(date) / 60))
    switch mins {
    case ..<1:   return "just now"
    case ..<60:  return "\(mins)m ago"
    case ..<(60 * 24): return "\(mins / 60)h ago"
    default:     return "\(mins / (60 * 24))d ago"
    }
}
