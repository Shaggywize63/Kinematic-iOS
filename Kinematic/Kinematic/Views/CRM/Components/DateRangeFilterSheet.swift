import SwiftUI

/// Modal sheet for picking a from/to date range.
/// Caller passes `@Binding` dates and an `onApply` closure that triggers a list refresh.
struct DateRangeFilterSheet: View {
    @Binding var from: Date?
    @Binding var to: Date?
    let label: String
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localFrom: Date = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var localTo: Date = Date()
    @State private var enabled: Bool

    init(from: Binding<Date?>, to: Binding<Date?>, label: String = "Date range", onApply: @escaping () -> Void) {
        _from = from
        _to = to
        self.label = label
        self.onApply = onApply
        _enabled = State(initialValue: from.wrappedValue != nil || to.wrappedValue != nil)
        if let f = from.wrappedValue { _localFrom = State(initialValue: f) }
        if let t = to.wrappedValue { _localTo = State(initialValue: t) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Filter by \(label)", isOn: $enabled)
                }
                if enabled {
                    Section(label) {
                        DatePicker("From", selection: $localFrom, displayedComponents: .date)
                        DatePicker("To", selection: $localTo, in: localFrom..., displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        from = nil; to = nil
                        onApply(); dismiss()
                    }
                    .foregroundColor(.red)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        if enabled {
                            from = localFrom
                            to = localTo
                        } else {
                            from = nil; to = nil
                        }
                        onApply(); dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
