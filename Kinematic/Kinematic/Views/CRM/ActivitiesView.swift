import SwiftUI

struct ActivitiesView: View {
    @StateObject var vm: ActivitiesViewModel
    @State private var showCompose = false
    @State private var showDateSheet = false
    /// Activity the rep tapped to edit. Drives the edit sheet; nil hides it.
    /// Reps wanted to open an existing activity to enrich notes or change
    /// status — the row was a static badge before, now it's tappable.
    @State private var editingActivity: Activity? = nil
    /// Activity pending deletion confirmation; nil hides the alert.
    @State private var deletingActivity: Activity? = nil
    @State private var layout: Layout = .list
    @State private var calendarMonth: Date = {
        let d = Date()
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }()
    // Meeting first — matches the field-force usage pattern and the
    // web dashboard's reordered activity type picker.
    let typeOptions = ["all", "meeting", "call", "email", "note", "task"]
    @State private var showLeadPicker = false

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

            // Owner + date-range filters (city/state come from the global scope).
            HStack(spacing: 8) {
                if !vm.owners.isEmpty {
                    Menu {
                        Button("All owners") { vm.ownerFilter = "all"; Task { await vm.refresh() } }
                        ForEach(vm.owners) { u in
                            Button(u.displayName) { vm.ownerFilter = u.id; Task { await vm.refresh() } }
                        }
                    } label: {
                        Label(vm.ownerFilter == "all" ? "Owner" : (vm.owners.first { $0.id == vm.ownerFilter }?.displayName ?? "Owner"),
                              systemImage: "person.crop.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .foregroundColor(vm.ownerFilter == "all" ? .gray : Brand.red)
                            .cornerRadius(8)
                    }
                }
                Button { showDateSheet = true } label: {
                    Label("Dates", systemImage: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .foregroundColor(vm.dateFrom != nil || vm.dateTo != nil ? Brand.red : .gray)
                        .cornerRadius(8)
                }
                if vm.dateFrom != nil || vm.dateTo != nil {
                    Button { vm.dateFrom = nil; vm.dateTo = nil; Task { await vm.refresh() } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
                // Search-by-lead chip. Tapping it opens a searchable lead
                // sheet; picking a lead filters the list via .eq(lead_id).
                Button { showLeadPicker = true } label: {
                    Label(vm.leadFilterLabel ?? "Lead", systemImage: "person.crop.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .foregroundColor(vm.leadFilterId == nil ? .gray : Brand.red)
                        .cornerRadius(8)
                        .lineLimit(1)
                }
                if vm.leadFilterId != nil {
                    Button {
                        vm.leadFilterId = nil
                        vm.leadFilterLabel = nil
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal).padding(.bottom, 4)

            if layout == .list {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if vm.filtered.isEmpty {
                            Text("No activity yet.").foregroundColor(.gray).padding(.top, 60)
                        } else {
                            // ── Today section ────────────────────────────
                            // On-device split — the activities endpoint
                            // doesn't have a `view=today` shortcut, so we
                            // partition the existing payload by whether
                            // due_at / completed_at falls within today's
                            // local calendar day. Keeps the network
                            // round-trip identical to before.
                            let buckets = Self.partitionToday(vm.filtered)
                            if !buckets.today.isEmpty {
                                ActivitySectionHeader(
                                    title: "Today",
                                    count: buckets.today.count,
                                    accent: Brand.red,
                                )
                                ForEach(buckets.today) { a in
                                    activityRow(a)
                                }
                            }
                            if !buckets.rest.isEmpty {
                                ActivitySectionHeader(
                                    title: buckets.today.isEmpty ? "All activity" : "Earlier",
                                    count: buckets.rest.count,
                                    accent: .secondary,
                                )
                                ForEach(buckets.rest) { a in
                                    activityRow(a)
                                }
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
            ActivityComposeView(allowLeadPicker: true) { type, subject, desc, imageUrl, when, leadId, customFields in
                await vm.log(
                    type: type, subject: subject, description: desc,
                    dealId: nil, leadId: leadId, imageUrl: imageUrl, completedAt: when,
                    customFields: customFields
                )
            }
        }
        // Edit sheet — tap a row to open the same compose view with
        // the activity's existing subject/type pre-filled, then save
        // patches the row instead of creating a new one.
        .sheet(item: $editingActivity) { act in
            ActivityComposeView(
                initialType: act.type ?? "meeting",
                initialSubject: act.subject ?? "",
                allowLeadPicker: false,
            ) { type, subject, desc, imageUrl, when, _, customFields in
                // Activity.id is non-optional in the model — pass it
                // straight through without a guard. (Earlier draft
                // used `if let` which the iOS 26 toolchain refused.)
                await vm.update(id: act.id, type: type, subject: subject, description: desc, imageUrl: imageUrl, completedAt: when, customFields: customFields)
            }
        }
        // Delete confirmation — guards against an accidental long-press.
        .alert("Delete this activity?", isPresented: .init(
            get: { deletingActivity != nil },
            set: { if !$0 { deletingActivity = nil } },
        )) {
            Button("Cancel", role: .cancel) { deletingActivity = nil }
            Button("Delete", role: .destructive) {
                if let id = deletingActivity?.id { Task { await vm.delete(id: id) } } // id is non-optional on Activity but the chain through optional `deletingActivity` keeps it Optional<String> — guard remains required.
                deletingActivity = nil
            }
        } message: {
            Text(deletingActivity?.subject ?? "This activity will be removed from the timeline.")
        }
        .sheet(isPresented: $showDateSheet) {
            DateRangeFilterSheet(from: $vm.dateFrom, to: $vm.dateTo, label: "Activity date") {
                Task { await vm.refresh() }
            }
        }
        .sheet(isPresented: $showLeadPicker) {
            LeadSearchPickerSheet { lead in
                vm.leadFilterId = lead.id
                vm.leadFilterLabel = lead.displayName
                Task { await vm.refresh() }
            }
        }
        .task { await vm.refresh(); await vm.loadOwners() }
    }

    /// Activity row with tap-to-edit and long-press context menu.
    /// The row itself stays read-only at-a-glance; tap opens the
    /// compose view pre-filled for editing, long-press surfaces a
    /// Delete action behind a confirmation alert so a misfire on a
    /// crowded screen can't silently remove a logged call.
    @ViewBuilder
    private func activityRow(_ a: Activity) -> some View {
        ActivityTimelineItem(activity: a)
            .contentShape(Rectangle())
            .onTapGesture { editingActivity = a }
            .contextMenu {
                Button { editingActivity = a } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) { deletingActivity = a } label: { Label("Delete", systemImage: "trash") }
            }
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

// MARK: - Today partition + section header

extension ActivitiesView {
    /// Splits the activity list into "today" vs "everything else" using the
    /// device's local calendar. Today buckets by `completedAt` if present,
    /// else `dueAt`, else `createdAt` — the same fallback the timeline item
    /// uses for its date suffix, so the split feels consistent with what
    /// the row labels say.
    static func partitionToday(_ activities: [Activity]) -> (today: [Activity], rest: [Activity]) {
        let cal = Calendar.current
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()

        func date(for a: Activity) -> Date? {
            let raw = a.completedAt ?? a.dueAt ?? a.createdAt
            guard let raw, !raw.isEmpty else { return nil }
            return iso.date(from: raw) ?? isoFallback.date(from: raw)
        }

        var today: [Activity] = []
        var rest: [Activity] = []
        for a in activities {
            if let d = date(for: a), cal.isDateInToday(d) {
                today.append(a)
            } else {
                rest.append(a)
            }
        }
        return (today, rest)
    }
}

private struct ActivitySectionHeader: View {
    let title: String
    let count: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 1)
                .foregroundColor(accent == .secondary ? .secondary : .white)
                .background(
                    Capsule().fill(accent == .secondary ? Color(uiColor: .tertiarySystemFill) : accent)
                )
            Spacer()
        }
        .padding(.top, 4)
    }
}
