import SwiftUI

/// Attendance regularization: raise a request to fix a missing / wrong
/// check-in or check-out (or flag on-duty / WFH), and see the status of the
/// rep's own regularization requests. Backed by POST/GET /leave/regularizations.
struct RegularizationView: View {
    @State private var requests: [Regularization] = []
    @State private var isLoading = true
    @State private var didLoad = false
    @State private var showForm = false

    var body: some View {
        Group {
            if isLoading && !didLoad {
                ProgressView().tint(Brand.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if requests.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 50)).foregroundColor(.gray.opacity(0.4))
                    Text("No regularization requests")
                        .font(.subheadline).foregroundColor(.gray)
                    Button {
                        showForm = true
                    } label: {
                        Text("Raise a Request").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.red)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(requests) { RegularizationRow(item: $0) }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Regularization")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showForm = true
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(Brand.red)
                }
            }
        }
        .sheet(isPresented: $showForm) {
            RegularizationForm { await load() }
        }
        .task {
            guard !didLoad else { return }
            await load()
        }
        .refreshable { await load() }
    }

    private func load() async {
        await MainActor.run { isLoading = true }
        let list = await KinematicRepository.shared.fetchMyRegularizations()
        await MainActor.run {
            self.requests = list
            self.isLoading = false
            self.didLoad = true
        }
    }
}

// MARK: - Regularization type metadata

enum RegularizationType: String, CaseIterable, Identifiable {
    case missingCheckin = "missing_checkin"
    case missingCheckout = "missing_checkout"
    case wrongTime = "wrong_time"
    case onDuty = "on_duty"
    case wfh = "wfh"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .missingCheckin:  return "Missing Check-in"
        case .missingCheckout: return "Missing Check-out"
        case .wrongTime:       return "Wrong Time"
        case .onDuty:          return "On Duty"
        case .wfh:             return "Work From Home"
        }
    }

    var needsCheckin: Bool { self == .missingCheckin || self == .wrongTime }
    var needsCheckout: Bool { self == .missingCheckout || self == .wrongTime }

    static func label(for raw: String?) -> String {
        guard let raw = raw, let t = RegularizationType(rawValue: raw) else {
            return (raw ?? "Regularization").replacingOccurrences(of: "_", with: " ").capitalized
        }
        return t.label
    }
}

// MARK: - Row

private struct RegularizationRow: View {
    let item: Regularization
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(RegularizationType.label(for: item.type))
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                LeaveStatusChip(status: item.status)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption2).foregroundColor(.secondary)
                Text(LeaveUI.prettyDate(item.attDate)).font(.caption).foregroundColor(.secondary)
            }
            if let reason = item.reason, !reason.isEmpty {
                Text(reason).font(.caption2).foregroundColor(.secondary).lineLimit(2)
            }
            if let note = item.decisionNote, !note.isEmpty {
                Text("Note: \(note)").font(.caption2).foregroundColor(.secondary).italic()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

// MARK: - Form

private struct RegularizationForm: View {
    let onSubmitted: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var attDate = Date()
    @State private var type: RegularizationType = .missingCheckin
    @State private var checkinAt = Date()
    @State private var checkoutAt = Date()
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Date")) {
                    DatePicker("Attendance date", selection: $attDate, displayedComponents: .date)
                }
                Section(header: Text("Type")) {
                    Picker("Type", selection: $type) {
                        ForEach(RegularizationType.allCases) { Text($0.label).tag($0) }
                    }
                }
                if type.needsCheckin {
                    Section(header: Text("Requested Check-in")) {
                        DatePicker("Check-in", selection: $checkinAt)
                    }
                }
                if type.needsCheckout {
                    Section(header: Text("Requested Check-out")) {
                        DatePicker("Check-out", selection: $checkoutAt)
                    }
                }
                Section(header: Text("Reason")) {
                    TextEditor(text: $reason).frame(minHeight: 90)
                }
                if let error = error {
                    Section { Text(error).foregroundColor(.red).font(.caption) }
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text(isSubmitting ? "Submitting…" : "Submit")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Brand.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isSubmitting)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Regularize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        // Anchor the requested times to the chosen attendance date so a
        // manager sees the intended day, not "today at that clock time".
        let cal = Calendar.current
        func onAttDate(_ t: Date) -> Date {
            let d = cal.dateComponents([.year, .month, .day], from: attDate)
            let clock = cal.dateComponents([.hour, .minute], from: t)
            var merged = DateComponents()
            merged.year = d.year; merged.month = d.month; merged.day = d.day
            merged.hour = clock.hour; merged.minute = clock.minute
            return cal.date(from: merged) ?? t
        }
        let (ok, msg) = await KinematicRepository.shared.createRegularization(
            attDate: LeaveUI.ymd(attDate),
            type: type.rawValue,
            requestedCheckinAt: type.needsCheckin ? LeaveUI.iso(onAttDate(checkinAt)) : nil,
            requestedCheckoutAt: type.needsCheckout ? LeaveUI.iso(onAttDate(checkoutAt)) : nil,
            reason: reason
        )
        isSubmitting = false
        if ok {
            await onSubmitted()
            dismiss()
        } else {
            error = msg ?? "Could not submit your request. Please try again."
        }
    }
}
