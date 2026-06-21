import SwiftUI

// Advanced leads filters — web parity (lifecycle stage, converted,
// created-date range). Status + search stay on the list itself. Binds
// straight to LeadsViewModel and refreshes on apply.
//
// Score Grade + Minimum Score were dropped at the user's request — the
// AI grade is no longer a primary filter affordance; the slider + chip
// strip cluttered every list and was rarely used.
struct LeadsFilterSheet: View {
    @ObservedObject var vm: LeadsViewModel
    @Environment(\.dismiss) private var dismiss

    private let lifecycles = ["all", "subscriber", "lead", "mql", "sql", "opportunity", "customer"]

    // Local date-range state mirrors DateRangeFilterSheet's pattern:
    // a Toggle gates rendering of the pickers AND seeds non-nil Dates
    // snapped to start-of-day. Without the explicit toggle the inline
    // pickers showed `Date()` by default — tapping "today" on a picker
    // that already showed today never triggered the setter, so
    // `vm.dateFrom` stayed nil and the filter was silently dropped.
    @State private var dateEnabled: Bool = false
    @State private var localFrom: Date = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    )
    @State private var localTo: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        NavigationStack {
            Form {
                Section("Lifecycle Stage") {
                    Picker("Lifecycle", selection: $vm.lifecycleFilter) {
                        ForEach(lifecycles, id: \.self) { Text($0 == "all" ? "All" : $0.uppercased()).tag($0) }
                    }
                }
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
                    Toggle("Filter by created date", isOn: $dateEnabled)
                    if dateEnabled {
                        DatePicker("From", selection: $localFrom, displayedComponents: .date)
                            .onChange(of: localFrom) { _, newValue in
                                let snapped = Calendar.current.startOfDay(for: newValue)
                                if snapped != localFrom { localFrom = snapped }
                                if localTo < snapped { localTo = snapped }
                            }
                        DatePicker("To", selection: $localTo, in: localFrom..., displayedComponents: .date)
                            .onChange(of: localTo) { _, newValue in
                                let snapped = Calendar.current.startOfDay(for: newValue)
                                if snapped != localTo { localTo = snapped }
                            }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.loadFilterOptions() }
            .onAppear {
                // Seed the local state from whatever the rep had applied
                // previously so reopening the sheet doesn't wipe their
                // last range.
                if let f = vm.dateFrom { localFrom = Calendar.current.startOfDay(for: f) }
                if let t = vm.dateTo { localTo = Calendar.current.startOfDay(for: t) }
                dateEnabled = vm.dateFrom != nil || vm.dateTo != nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        vm.resetFilters()
                        dateEnabled = false
                        Task { await vm.refresh() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if dateEnabled {
                            vm.dateFrom = Calendar.current.startOfDay(for: localFrom)
                            // Inclusive end-of-day so a "today → today"
                            // window picks up rows created later in the
                            // same day; the wire format is yyyy-MM-dd
                            // and the backend treats it as the full day.
                            vm.dateTo = Calendar.current.date(
                                bySettingHour: 23, minute: 59, second: 59,
                                of: Calendar.current.startOfDay(for: localTo)
                            ) ?? localTo
                        } else {
                            vm.dateFrom = nil
                            vm.dateTo = nil
                        }
                        Task { await vm.refresh() }
                        dismiss()
                    }
                }
            }
        }
    }
}
