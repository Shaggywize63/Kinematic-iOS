import SwiftUI

/// Modal sheet for picking a from/to date range.
/// Caller passes `@Binding` dates and an `onApply` closure that triggers a list refresh.
struct DateRangeFilterSheet: View {
    @Binding var from: Date?
    @Binding var to: Date?
    let label: String
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    // Normalise to start-of-day so the `.date`-only pickers don't carry a
    // stale time-of-day. If we let the time component ride, the `in:
    // localFrom...` constraint on the To picker compares *full* timestamps
    // and silently rejects "today" when From's seeded time-of-day is later
    // than the current clock (e.g. From = today 14:00, user taps To =
    // today, To resolves to today 10:00 → out of range → ignored). Same
    // bug bit the end-of-day boundary, where To = today 09:00 < From =
    // today 14:00 even though the rep picked the same calendar date.
    @State private var localFrom: Date = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    )
    @State private var localTo: Date = Calendar.current.startOfDay(for: Date())
    @State private var enabled: Bool

    init(from: Binding<Date?>, to: Binding<Date?>, label: String = "Date range", onApply: @escaping () -> Void) {
        _from = from
        _to = to
        self.label = label
        self.onApply = onApply
        _enabled = State(initialValue: from.wrappedValue != nil || to.wrappedValue != nil)
        if let f = from.wrappedValue {
            _localFrom = State(initialValue: Calendar.current.startOfDay(for: f))
        }
        if let t = to.wrappedValue {
            _localTo = State(initialValue: Calendar.current.startOfDay(for: t))
        }
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
                            .onChange(of: localFrom) { _, newValue in
                                // Snap to start-of-day every time and pull
                                // To forward if the rep dragged From past
                                // it, so the same-day case always works.
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
                            // Inclusive end-of-day so a "today → today"
                            // range matches activities created later in
                            // the same day; callers compare against
                            // created_at which carries a timestamp.
                            from = Calendar.current.startOfDay(for: localFrom)
                            to = Calendar.current.date(
                                bySettingHour: 23, minute: 59, second: 59,
                                of: Calendar.current.startOfDay(for: localTo)
                            ) ?? localTo
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
