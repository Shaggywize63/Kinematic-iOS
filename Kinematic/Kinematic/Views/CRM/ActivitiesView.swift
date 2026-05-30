import SwiftUI

struct ActivitiesView: View {
    @StateObject var vm: ActivitiesViewModel
    @State private var showCompose = false
    @State private var layout: Layout = .list
    @State private var calendarMonth: Date = {
        let d = Date()
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }()
    let typeOptions = ["all", "call", "email", "meeting", "note", "task"]

    enum Layout: String, CaseIterable, Identifiable { case list, calendar; var id: String { rawValue } }

    init(initialFilter: String = "all") {
        _vm = StateObject(wrappedValue: ActivitiesViewModel(initialFilter: initialFilter))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Layout picker — list (existing) ↔ calendar (mirrors the web
            // dashboard month grid I shipped earlier). Stays above the
            // type-filter chips so the layout choice persists across
            // filter switches.
            Picker("Layout", selection: $layout) {
                ForEach(Layout.allCases) { l in
                    Text(l.rawValue.capitalized).tag(l)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(typeOptions, id: \.self) { t in
                        Button { vm.typeFilter = t } label: {
                            Text(t.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(vm.typeFilter == t ? Brand.red : Color(uiColor: .secondarySystemBackground))
                                .foregroundColor(vm.typeFilter == t ? .white : .gray)
                                .cornerRadius(8)
                        }
                    }
                }.padding()
            }

            if layout == .list {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if vm.filtered.isEmpty {
                            Text("No activity yet.").foregroundColor(.gray).padding(.top, 60)
                        } else {
                            ForEach(vm.filtered) { a in
                                ActivityTimelineItem(activity: a)
                            }
                        }
                    }.padding()
                }
                .refreshable { await vm.refresh() }
            } else {
                ActivityCalendar(
                    month: $calendarMonth,
                    activities: vm.filtered,
                )
                .padding(.horizontal)
                .padding(.top, 6)
            }
        }
        .navigationTitle("Activities")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: ChatListView()) {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCompose = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCompose) {
            ActivityComposeView { type, subject, desc, imageUrl, when in
                await vm.log(
                    type: type, subject: subject, description: desc,
                    dealId: nil, leadId: nil, imageUrl: imageUrl, completedAt: when
                )
            }
        }
        .task { await vm.refresh() }
    }
}

/**
 * Month-pivoted agenda view of activities. Mirrors the web dashboard's
 * calendar layout at narrow widths — every day in the visible month with
 * at least one activity becomes a stacked card listing its rows. Today's
 * card carries a primary-coloured left rail so it's findable without
 * scrolling. A 7-column grid would scrunch beyond use on a phone, so we
 * skip it on mobile entirely.
 *
 * Activities are bucketed by completed_at (else due_at); activities with
 * neither date drop off the calendar but stay visible in the list view.
 */
struct ActivityCalendar: View {
    @Binding var month: Date
    let activities: [Activity]

    private var cal: Calendar { Calendar(identifier: .gregorian) }

    /// Map of YYYY-MM-DD → activities for fast cell lookups.
    private var byDay: [Date: [Activity]] {
        var out: [Date: [Activity]] = [:]
        let f = ISO8601DateFormatter()
        for a in activities {
            let iso = a.completedAt ?? a.dueAt
            guard let iso, let d = f.date(from: iso) ?? parseLooseISO(iso) else { continue }
            let key = cal.startOfDay(for: d)
            out[key, default: []].append(a)
        }
        return out
    }

    private var monthDays: [Date] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        var d = interval.start
        var out: [Date] = []
        while d < interval.end {
            out.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? interval.end
        }
        return out
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: month)
    }

    private func goPrev() {
        if let d = cal.date(byAdding: .month, value: -1, to: month) { month = d }
    }
    private func goNext() {
        if let d = cal.date(byAdding: .month, value: 1, to: month) { month = d }
    }
    private func goToday() {
        let now = Date()
        month = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
    }

    var body: some View {
        VStack(spacing: 10) {
            // Header: prev / month label / next / today.
            HStack(spacing: 6) {
                Button(action: goPrev) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(6)
                }
                Text(monthLabel)
                    .font(.system(size: 14, weight: .bold))
                    .frame(minWidth: 160)
                Button(action: goNext) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(6)
                }
                Button("Today", action: goToday)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(6)
                Spacer()
            }

            // Body: agenda stack of days that have activities.
            let populated = monthDays
                .map { d -> (Date, [Activity]) in (d, byDay[cal.startOfDay(for: d)] ?? []) }
                .filter { !$0.1.isEmpty }
            if populated.isEmpty {
                Text("No activities in this month.")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .padding(.top, 24)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(populated, id: \.0) { day, list in
                            DayCard(day: day, activities: list)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    /// Some backend rows return ISO with fractional seconds the standard
    /// formatter rejects; fall back to a loose parser so cells don't
    /// silently drop activities.
    private func parseLooseISO(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }
}

private struct DayCard: View {
    let day: Date
    let activities: [Activity]

    private var cal: Calendar { Calendar(identifier: .gregorian) }
    private var isToday: Bool { cal.isDateInToday(day) }
    private var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.dateFormat = "EEE, d MMM"
        return f.string(from: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayLabel)
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(isToday ? Brand.red : .primary)
                if isToday {
                    Text("· TODAY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Brand.red)
                }
                Spacer()
                Text("\(activities.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }

            ForEach(activities) { a in
                ActivityTimelineItem(activity: a)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(alignment: .leading) {
            if isToday {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Brand.red)
                    .frame(width: 4)
            }
        }
    }
}
