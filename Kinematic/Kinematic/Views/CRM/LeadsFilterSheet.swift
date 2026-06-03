import SwiftUI

// Advanced leads filters — web parity (score grade, minimum score, lifecycle
// stage, converted, created-date range). Status + search stay on the list
// itself. Binds straight to LeadsViewModel and refreshes on apply.
struct LeadsFilterSheet: View {
    @ObservedObject var vm: LeadsViewModel
    @Environment(\.dismiss) private var dismiss

    private let grades = ["all", "A", "B", "C", "D"]
    private let lifecycles = ["all", "subscriber", "lead", "mql", "sql", "opportunity", "customer"]
    private let converted = ["all", "yes", "no"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Score Grade") {
                    Picker("Grade", selection: $vm.gradeFilter) {
                        ForEach(grades, id: \.self) { Text($0 == "all" ? "All" : $0).tag($0) }
                    }.pickerStyle(.segmented)
                }
                Section("Minimum Score: \(vm.minScore)") {
                    Slider(value: Binding(get: { Double(vm.minScore) }, set: { vm.minScore = Int($0) }),
                           in: 0...100, step: 5)
                }
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
                Section("Created Date") {
                    DatePicker("From", selection: Binding(
                        get: { vm.dateFrom ?? Date() },
                        set: { vm.dateFrom = $0 }), displayedComponents: .date)
                    DatePicker("To", selection: Binding(
                        get: { vm.dateTo ?? Date() },
                        set: { vm.dateTo = $0 }), displayedComponents: .date)
                    if vm.dateFrom != nil || vm.dateTo != nil {
                        Button("Clear dates", role: .destructive) { vm.dateFrom = nil; vm.dateTo = nil }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { vm.resetFilters(); Task { await vm.refresh() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { Task { await vm.refresh() }; dismiss() }
                }
            }
        }
    }
}
