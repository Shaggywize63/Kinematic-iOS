import SwiftUI
// Combine is not re-exported by SwiftUI on the Xcode 26 toolchain — the ObservableObject view model below fails to
// compile without this import.
import Combine

// MARK: - View model

/// State behind the Timeline screen (module `timeline`).
///
/// A field executive only ever sees their own day. A manager can also switch to the team list for the chosen date and
/// open one person's day (`viewing`). Every change of date / person / view re-fetches, and a reply that arrives after a
/// newer request was made is dropped so a slow answer for yesterday cannot overwrite today.
@MainActor
final class DayTimelineViewModel: ObservableObject {
    /// `YYYY-MM-DD`, India day.
    @Published var date: String = DayTimelineLogic.today()
    /// A manager looking at the team list instead of their own day.
    @Published var teamMode = false
    /// The teammate whose day is open; nil = the signed-in user's own.
    @Published var viewing: TeamDayRow? = nil
    @Published var loading = true
    @Published var errorMsg: String? = nil
    @Published var report: DayReportData? = nil
    @Published var team: [TeamDayRow]? = nil

    private let api = DayTimelineAPI.shared
    private var task: Task<Void, Never>? = nil

    /// True while the team list (not a person's day) is what the screen shows.
    var showingTeamList: Bool { teamMode && viewing == nil }

    func load() async {
        let day = date
        let listing = showingTeamList
        let person = viewing?.userId
        loading = true
        errorMsg = nil
        do {
            if listing {
                let rows = try await api.team(date: day)
                guard isCurrent(day: day, listing: listing, person: person) else { return }
                team = rows
            } else {
                let r = try await api.dailyReport(date: day, userId: person)
                guard isCurrent(day: day, listing: listing, person: person) else { return }
                report = r
            }
            loading = false
        } catch {
            guard isCurrent(day: day, listing: listing, person: person) else { return }
            errorMsg = error.localizedDescription
            loading = false
        }
    }

    /// Is the request that was started for these inputs still the one on screen?
    private func isCurrent(day: String, listing: Bool, person: String?) -> Bool {
        !Task.isCancelled && date == day && showingTeamList == listing && viewing?.userId == person
    }

    /// Start a fresh load, cancelling any still running.
    func refresh() {
        task?.cancel()
        task = Task { [weak self] in
            await self?.load()
        }
    }

    func setDate(_ newDate: String) {
        guard newDate != date else { return }
        date = newDate
        report = nil
        team = nil
        refresh()
    }

    func previousDay() { setDate(DayTimelineLogic.shiftDay(date, by: -1)) }

    /// The next day, never past today (India).
    func nextDay() {
        let next = DayTimelineLogic.shiftDay(date, by: 1)
        if next <= DayTimelineLogic.today() { setDate(next) }
    }

    func goToday() { setDate(DayTimelineLogic.today()) }

    var isToday: Bool { date >= DayTimelineLogic.today() }

    /// Switch between a manager's own day and the team list.
    func showTeam(_ on: Bool) {
        if teamMode == on && viewing == nil { return }
        teamMode = on
        viewing = nil
        report = nil
        team = nil
        refresh()
    }

    /// Open one teammate's day from the team list.
    func open(_ person: TeamDayRow) {
        viewing = person
        report = nil
        refresh()
    }

    /// Back from a teammate's day to the team list.
    func closePerson() {
        guard viewing != nil else { return }
        viewing = nil
        report = nil
        team = nil
        refresh()
    }
}

// MARK: - Screen

/// Timeline (module `timeline`, off unless granted to the client): a day laid out in time order — check-in, travel,
/// customer visits, halts, check-out — the same report the web dashboard's Daily Travel Report shows.
///
/// A field executive sees their own day. A manager (supervisor and above) can switch to Team, pick the date, and open
/// anyone with a shift that day. Dates step back and forward but never past today.
struct DayTimelineView: View {
    @StateObject private var vm = DayTimelineViewModel()
    @Environment(\.openURL) private var openURL

    private var canTeam: Bool { DayTimelineLogic.canViewTeam(role: Session.currentUser?.role) }

    var body: some View {
        VStack(spacing: 0) {
            if canTeam && vm.viewing == nil {
                Picker("View", selection: Binding(get: { vm.teamMode }, set: { vm.showTeam($0) })) {
                    Text("My day").tag(false)
                    Text("Team").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            if let person = vm.viewing {
                HStack {
                    Button {
                        vm.closePerson()
                    } label: {
                        Label("Team", systemImage: "chevron.left")
                    }
                    Spacer()
                    Text(person.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            dateBar
            content
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    vm.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await vm.load() }
    }

    // MARK: date bar

    private var dateBar: some View {
        HStack {
            Button {
                vm.previousDay()
            } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(DayTimelineLogic.dayLabel(vm.date))
                    .font(.subheadline.weight(.bold))
                if vm.isToday {
                    Text("Today").font(.caption2).foregroundColor(.secondary)
                } else {
                    Button("Today") { vm.goToday() }
                        .font(.caption.weight(.semibold))
                }
            }
            Spacer()
            Button {
                vm.nextDay()
            } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .disabled(vm.isToday)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        if vm.loading && (vm.showingTeamList ? vm.team == nil : vm.report == nil) {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMsg {
            VStack(spacing: 12) {
                Text(err)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { vm.refresh() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.showingTeamList {
            teamList(vm.team ?? [])
        } else if let report = vm.report {
            dayContent(report)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func emptyState(icon: String, title: String, sub: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(title).font(.headline).foregroundColor(.secondary)
            Text(sub)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: team list

    @ViewBuilder
    private func teamList(_ rows: [TeamDayRow]) -> some View {
        if rows.isEmpty {
            emptyState(icon: "person.3", title: "No one clocked in", sub: "People with a shift on this day appear here")
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(rows) { r in
                        Button {
                            vm.open(r)
                        } label: {
                            teamRow(r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .refreshable { await vm.load() }
        }
    }

    private func teamRow(_ r: TeamDayRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    let sub = [r.employeeId, r.modeLabel].compactMap { $0 }.joined(separator: " · ")
                    if !sub.isEmpty {
                        Text(sub).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
            let out = r.checkout != nil ? DayTimelineLogic.clockText(r.checkout) : "on shift"
            Text("\(DayTimelineLogic.clockText(r.checkin)) – \(out)")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                statPill("Distance", DayTimelineLogic.kmText(r.totalKm))
                statPill("Visits", "\(r.visits)")
                statPill("Halts", DayTimelineLogic.durationText(r.haltMinutes) ?? "0 min")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.footnote.weight(.bold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: one person's day

    @ViewBuilder
    private func dayContent(_ report: DayReportData) -> some View {
        let events = DayTimelineLogic.buildTimeline(report)
        if report.attendanceId == nil || events.isEmpty {
            emptyState(icon: "clock.arrow.circlepath",
                       title: "No shift on \(DayTimelineLogic.dayLabel(report.date.isEmpty ? vm.date : report.date))",
                       sub: "Check-in, travel, visits and halts show up once a shift starts")
        } else {
            let visitMinutes = report.visits.reduce(0) { $0 + $1.minutes }
            let haltMinutes = report.halts.reduce(0) { $0 + $1.minutes }
            let hours = (report.inProgress && report.totalHours == nil) ? "On shift" : DayTimelineLogic.hoursText(report.totalHours)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        statPill("Distance", DayTimelineLogic.kmText(report.totalKm))
                        statPill("Hours", hours)
                    }
                    HStack(spacing: 8) {
                        statPill("Visits", "\(report.visits.count) · \(DayTimelineLogic.durationText(visitMinutes) ?? "0 min")")
                        statPill("Halts", "\(report.halts.count) · \(DayTimelineLogic.durationText(haltMinutes) ?? "0 min")")
                    }
                    if let mode = report.modeLabel {
                        Text("Travelling by \(mode)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(events) { e in
                            eventRow(e, isLast: e.seq == events.count)
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(16)
            }
            .refreshable { await vm.load() }
        }
    }

    private func color(for kind: DayTimelineKind) -> Color {
        switch kind {
        case .checkin: return .green
        case .travel: return .blue
        case .visit: return Brand.red
        case .halt: return .orange
        case .checkout: return .purple
        }
    }

    private func icon(for kind: DayTimelineKind) -> String {
        switch kind {
        case .checkin: return "arrow.right.circle.fill"
        case .travel: return "car.fill"
        case .visit: return "mappin.circle.fill"
        case .halt: return "pause.circle.fill"
        case .checkout: return "arrow.left.circle.fill"
        }
    }

    private func eventRow(_ e: DayTimelineEvent, isLast: Bool) -> some View {
        let tint = color(for: e.kind)
        let badge: String? = e.km != nil ? DayTimelineLogic.kmText(e.km) : DayTimelineLogic.durationText(e.minutes)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: icon(for: e.kind))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text((e.marker.map { "#\($0) · " } ?? "") + e.title)
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    if let badge = badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(tint)
                    }
                }
                Text(DayTimelineLogic.rangeText(e))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !e.detail.isEmpty {
                    Text(e.detail).font(.subheadline).lineLimit(3)
                }
                if mapURL(e) != nil {
                    Text("Tap to open in Maps").font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            if !isLast {
                // The rail: a line from under this event's icon down to the next one.
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(width: 2)
                    .padding(.leading, 15)
                    .padding(.top, 32)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = mapURL(e) { openURL(url) }
        }
    }

    /// An Apple Maps link for a visit / halt location; nil for an event with no place.
    private func mapURL(_ e: DayTimelineEvent) -> URL? {
        guard let lat = e.lat, let lng = e.lng else { return nil }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "maps.apple.com"
        comps.path = "/"
        comps.queryItems = [
            URLQueryItem(name: "ll", value: "\(lat),\(lng)"),
            URLQueryItem(name: "q", value: e.detail.isEmpty ? e.title : e.detail),
        ]
        return comps.url
    }
}
