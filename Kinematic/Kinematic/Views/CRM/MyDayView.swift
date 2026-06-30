import SwiftUI

/// "My Day" — the rep's agenda for today. Surfaces activities due today,
/// overdue (tinted as attention) and upcoming work, plus open leads near
/// the device. Data comes from `GET /crm/my-day` via
/// `KinematicRepository.fetchMyDay(lat:lng:)`.
///
/// Note: this screen intentionally never renders the lead `city` field —
/// `city` is a built-in lead field gated by the field-override contract
/// (see CLAUDE.md). Lead rows show title + status + distance only.
struct MyDayView: View {
    @State private var payload: MyDayResponse?
    @State private var isLoading = true
    @State private var didLoad = false

    // KINI daily briefing — loaded alongside the agenda. While the request is
    // in flight we show a shimmer placeholder; if it resolves to nil/empty the
    // card hides entirely (no error surface).
    @State private var briefing: String?
    @State private var briefingLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                briefingCard

                if let counts = payload?.counts {
                    summaryPills(counts)
                }

                if isLoading && !didLoad {
                    loadingState
                } else if isEverythingEmpty {
                    emptyState
                } else {
                    if let today = payload?.activitiesToday, !today.isEmpty {
                        section(
                            title: "Today",
                            icon: "sun.max.fill",
                            tint: Brand.info
                        ) {
                            ForEach(today) { ActivityRow(activity: $0, tint: Brand.info) }
                        }
                    }

                    if let overdue = payload?.overdue, !overdue.isEmpty {
                        section(
                            title: "Overdue",
                            icon: "exclamationmark.triangle.fill",
                            tint: Brand.red
                        ) {
                            ForEach(overdue) { ActivityRow(activity: $0, tint: Brand.red) }
                        }
                    }

                    if let upcoming = payload?.upcoming, !upcoming.isEmpty {
                        UpcomingSection(activities: upcoming)
                    }

                    if let leads = payload?.leads, !leads.isEmpty {
                        section(
                            title: "Open leads near you",
                            icon: "mappin.and.ellipse",
                            tint: Brand.success
                        ) {
                            ForEach(leads) { LeadRow(lead: $0) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .navigationTitle("My Day")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .refreshable { await load() }
        .task {
            guard !didLoad else { return }
            await load()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("My Day")
                .font(.largeTitle.bold())
            Text(prettyDate)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }

    private var prettyDate: String {
        // Prefer the server-stamped date; fall back to the device's today.
        let date = parseISO(payload?.date) ?? Date()
        let df = DateFormatter()
        df.dateFormat = "EEEE, d MMMM"
        return df.string(from: date)
    }

    // MARK: - Summary pills

    private func summaryPills(_ counts: MyDayCounts) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                SummaryPill(label: "Today",    value: counts.today,     tint: Brand.info)
                SummaryPill(label: "Overdue",  value: counts.overdue,   tint: Brand.red)
                SummaryPill(label: "Upcoming", value: counts.upcoming,  tint: Brand.caution)
                SummaryPill(label: "Open leads", value: counts.openLeads, tint: Brand.success)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Daily AI briefing card

    @ViewBuilder
    private var briefingCard: some View {
        if briefingLoading && briefing == nil {
            briefingShell {
                Text("KINI is reading your day…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .shimmer()
            }
        } else if let text = briefing, !text.isEmpty {
            briefingShell {
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // nil / empty after load → render nothing.
    }

    @ViewBuilder
    private func briefingShell<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Brand.info)
            content()
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Brand.info.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Brand.info.opacity(0.16), lineWidth: 1)
        )
    }

    // MARK: - Section scaffold

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(tint)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.headline)
                Spacer()
            }
            VStack(spacing: 8) {
                content()
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your day…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(Brand.success)
            Text("You're all caught up")
                .font(.headline)
            Text("No activities due and no nearby leads right now.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var isEverythingEmpty: Bool {
        let a = payload?.activitiesToday?.isEmpty ?? true
        let o = payload?.overdue?.isEmpty ?? true
        let u = payload?.upcoming?.isEmpty ?? true
        let l = payload?.leads?.isEmpty ?? true
        return a && o && u && l
    }

    // MARK: - Networking

    private func load() async {
        isLoading = true
        briefingLoading = true
        // Pass device coordinates when available so the backend can stamp
        // per-lead distance; the endpoint treats them as optional.
        let loc = LocationTrackingService.shared.lastLocation

        // The briefing can take ~1-2s; fetch it concurrently so the agenda
        // renders as soon as my-day returns and the card fills in after.
        async let myDay = KinematicRepository.shared.fetchMyDay(
            lat: loc?.coordinate.latitude,
            lng: loc?.coordinate.longitude
        )
        async let dailyBriefing = KinematicRepository.shared.fetchDailyBriefing()

        let result = await myDay
        await MainActor.run {
            self.payload = result
            self.isLoading = false
            self.didLoad = true
        }

        let briefingText = await dailyBriefing
        await MainActor.run {
            self.briefing = briefingText
            self.briefingLoading = false
        }
    }
}

// MARK: - Upcoming (collapsed / secondary)

private struct UpcomingSection: View {
    let activities: [MyDayActivity]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundColor(Brand.caution)
                        .font(.system(size: 15, weight: .semibold))
                    Text("Upcoming")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(activities.count)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 8) {
                    ForEach(activities) { ActivityRow(activity: $0, tint: Brand.caution) }
                }
            }
        }
    }
}

// MARK: - Activity row

private struct ActivityRow: View {
    let activity: MyDayActivity
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: typeIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(activity.subject?.isEmpty == false ? activity.subject! : "(No subject)")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let type = activity.type, !type.isEmpty {
                        Chip(text: type.capitalized, tint: tint)
                    }
                    if let priority = activity.priority, !priority.isEmpty {
                        Chip(text: priority.capitalized, tint: priorityTint)
                    }
                    Spacer(minLength: 0)
                    if let due = dueLabel {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 11, weight: .semibold))
                            Text(due)
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var typeIcon: String {
        switch (activity.type ?? "").lowercased() {
        case "call":    return "phone.fill"
        case "email":   return "envelope.fill"
        case "meeting": return "person.2.fill"
        case "task":    return "checkmark.square.fill"
        case "note":    return "note.text"
        default:        return "circle.fill"
        }
    }

    private var priorityTint: Color {
        switch (activity.priority ?? "").lowercased() {
        case "high", "urgent": return Brand.red
        case "medium":         return Brand.caution
        default:               return Brand.info
        }
    }

    private var dueLabel: String? {
        guard let date = parseISO(activity.dueAt) else { return nil }
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: date)
    }
}

// MARK: - Lead row (title + status + distance only — never city)

private struct LeadRow: View {
    let lead: MyDayLead

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Brand.success.opacity(0.16))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Brand.success)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(lead.title?.isEmpty == false ? lead.title! : "(Untitled lead)")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let status = lead.status, !status.isEmpty {
                        Chip(text: status.capitalized, tint: Brand.info)
                    }
                }
            }

            Spacer(minLength: 0)

            if let distance = distanceLabel {
                HStack(spacing: 3) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(distance)
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var distanceLabel: String? {
        guard let km = lead.distanceKm else { return nil }
        return String(format: "%.1f km", km)
    }
}

// MARK: - Small components

private struct Chip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
            .foregroundColor(tint)
    }
}

// MARK: - Shimmer (briefing placeholder)

/// Subtle left-to-right highlight sweep used on the KINI briefing placeholder
/// while the request is in flight. Self-contained — no external dependency.
private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Color.white.opacity(0.55),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 1.4)
                    .offset(x: phase * geo.size.width * 1.4)
                    .blendMode(.plusLighter)
                }
                .mask(content)
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

private extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

private struct SummaryPill: View {
    let label: String
    let value: Int?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value ?? 0)")
                .font(.title3.bold())
                .foregroundColor(tint)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tint.opacity(0.10))
        )
    }
}
