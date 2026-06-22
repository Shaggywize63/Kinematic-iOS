import SwiftUI

// Advanced leads filters — web parity (lifecycle stage, converted,
// created-date range). Status + search stay on the list itself. Binds
// straight to LeadsViewModel and refreshes on apply.
//
// Score Grade + Minimum Score were dropped at the user's request — the
// AI grade is no longer a primary filter affordance.
//
// Created Date uses the same Today / Yesterday / Last 7 / This month /
// Custom preset bar as the Dashboard + Reports hub so reps don't have
// to manually pick start-of-day timestamps every time they want
// "today's leads". Custom mode reveals two pickers that snap to
// start-of-day and stamp end-of-day on Apply so the wire timestamps
// span the full picked day(s).
struct LeadsFilterSheet: View {
    @ObservedObject var vm: LeadsViewModel
    @Environment(\.dismiss) private var dismiss


    enum DateRangePreset: String, CaseIterable, Identifiable {
        case any, today, yesterday, last7, thisMonth, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: return "Any"
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .last7: return "Last 7 days"
            case .thisMonth: return "This month"
            case .custom: return "Custom"
            }
        }
    }

    @State private var range: DateRangePreset = .any
    @State private var customFrom: Date = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    )
    @State private var customTo: Date = Calendar.current.startOfDay(for: Date())

    /// Resolve the current preset → concrete start-of-day (from) +
    /// end-of-day (to) Dates the VM forwards to the backend. Both ends
    /// are user-timezone aware so "today" matches the rep's day, not
    /// midnight UTC.
    private var resolvedRange: (from: Date?, to: Date?) {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let endOfDay = { (d: Date) -> Date in
            cal.date(bySettingHour: 23, minute: 59, second: 59,
                     of: cal.startOfDay(for: d)) ?? d
        }
        switch range {
        case .any:
            return (nil, nil)
        case .today:
            return (startOfToday, endOfDay(startOfToday))
        case .yesterday:
            let y = cal.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return (y, endOfDay(y))
        case .last7:
            let from = cal.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
            return (from, endOfDay(startOfToday))
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: Date())
            let monthStart = cal.date(from: comps) ?? startOfToday
            return (monthStart, endOfDay(startOfToday))
        case .custom:
            return (cal.startOfDay(for: customFrom), endOfDay(customTo))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Lifecycle stage (MQL / SQL / Subscriber / …) was
                // dropped at the user's request — too marketing-y for
                // the field-rep flow. Reps filter by Converted / Owner /
                // Source / Date which already covers every real-world
                // question they ask the list.
                Section("Converted") {
                    Picker("Converted", selection: $vm.convertedFilter) {
                        Text("All").tag("all"); Text("Converted").tag("yes"); Text("Not converted").tag("no")
                    }.pickerStyle(.segmented)
                }
                Section("Owner") {
                    Picker("Owner", selection: $vm.ownerFilter) {
                        Text("All owners").tag("all")
                        ForEach(vm.owners) { u in Text(u.displayName).tag(u.id) }
                    }
                }
                Section("Source") {
                    Picker("Source", selection: $vm.sourceFilter) {
                        Text("All sources").tag("all")
                        ForEach(vm.sources) { s in Text(s.name).tag(s.id) }
                    }
                }
                Section("Created Date") {
                    Picker("Range", selection: $range) {
                        ForEach(DateRangePreset.allCases) { Text($0.label).tag($0) }
                    }
                    // Wheel — the segmented control wraps to 2 lines on
                    // the standard sheet width with 6 options and is
                    // hard to read; menu picker keeps the form compact.
                    .pickerStyle(.menu)
                    if range == .custom {
                        DatePicker("From", selection: $customFrom, displayedComponents: .date)
                            .onChange(of: customFrom) { _, newValue in
                                let snapped = Calendar.current.startOfDay(for: newValue)
                                if snapped != customFrom { customFrom = snapped }
                                if customTo < snapped { customTo = snapped }
                            }
                        DatePicker("To", selection: $customTo, in: customFrom..., displayedComponents: .date)
                            .onChange(of: customTo) { _, newValue in
                                let snapped = Calendar.current.startOfDay(for: newValue)
                                if snapped != customTo { customTo = snapped }
                            }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.loadFilterOptions() }
            .onAppear {
                // Seed the local picker from whatever the rep had applied
                // last; default to .any when no range is active.
                if let f = vm.dateFrom { customFrom = Calendar.current.startOfDay(for: f) }
                if let t = vm.dateTo { customTo = Calendar.current.startOfDay(for: t) }
                if vm.dateFrom == nil && vm.dateTo == nil { range = .any }
                else if range == .any { range = .custom }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        vm.resetFilters()
                        range = .any
                        Task { await vm.refresh() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let r = resolvedRange
                        vm.dateFrom = r.from
                        vm.dateTo = r.to
                        Task { await vm.refresh() }
                        dismiss()
                    }
                }
            }
        }
    }
}
