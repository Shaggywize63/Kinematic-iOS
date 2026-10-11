//
//  AttendanceStatusViews.swift
//  Kinematic
//
//  The pieces of UI the attendance rules add (see AttendanceRules.swift, OfflinePunch.swift). Opt-in per client BY
//  DATA — every one of them draws NOTHING for a client that configured nothing:
//
//    • TransportPickerSheet / ClockInTransportHost — the REQUIRED "How are you travelling today?" step in front of
//      Clock-In, and the same picker for "Change" on the chip;
//    • TransportModeChipView — "Travelling by Two-wheeler" + Change (or "Travel mode not set" + Set);
//    • OfflinePunchNoticeView — "Checked in 09:12 — will sync when online" / "Check-in 09:12 was not accepted: ...";
//    • AttendanceStatusExtras — what Home and the Attendance screen add under the attendance card: the late line, the
//      notice, the chip, and (Home, no-selfie clients) the outcome of a one-tap punch.
//

import SwiftUI

// MARK: - The question

/// A single-choice question: one row per option, nothing chosen until the rep taps one, and the confirm button stays
/// off until they have (`TransportMode.choice` — only an offered choice counts). `request.initial` pre-selects the
/// current answer when changing it.
struct TransportPickerSheet: View {
    let request: TransportPickRequest
    let onConfirm: (String) -> Void
    let onCancel: () -> Void
    @State private var picked: String?

    init(request: TransportPickRequest, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.request = request
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _picked = State(initialValue: TransportMode.choice(picked: request.initial, options: request.options))
    }

    private var canConfirm: Bool {
        TransportMode.choice(picked: picked, options: request.options) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(request.options) { option in
                            optionRow(option)
                        }
                    }
                    .padding(20)
                }
                confirmButton
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func optionRow(_ option: TransportOption) -> some View {
        let selected: Bool = picked == option.id
        return Button {
            picked = option.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: TransportPickerSheet.symbol(for: option))
                    .foregroundColor(selected ? Brand.red : .secondary)
                    .frame(width: 26)
                Text(option.label)
                    .font(.body)
                    .foregroundColor(Color(uiColor: .label))
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? Brand.red : .secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Brand.red : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var confirmButton: some View {
        Button {
            if let id = TransportMode.choice(picked: picked, options: request.options) { onConfirm(id) }
        } label: {
            Text(request.confirmLabel)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canConfirm ? Brand.red : Color.gray.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(14)
        }
        .disabled(!canConfirm)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// A glyph for a choice (only symbols every supported iOS has).
    static func symbol(for option: TransportOption) -> String {
        let id: String = option.id
        if id == TransportMode.publicTransport { return "bus.fill" }
        if id == TransportMode.other { return "ellipsis.circle" }
        if id.contains("wheeler") || id.contains("bike") || id.contains("cycle") { return "bicycle" }
        if id.contains("walk") { return "figure.walk" }
        return "car.fill"
    }
}

/// Hosts the Clock-In question. Attach once, high in the view tree (next to the camera's full-screen cover): the
/// view model raises `transportRequest`, this shows it, and when the sheet has finished closing the interrupted
/// Clock-In goes on (`transportSheetDismissed`) — so the camera never opens while the sheet is still on its way out.
struct ClockInTransportHost: ViewModifier {
    @ObservedObject var vm: AttendanceViewModel

    func body(content: Content) -> some View {
        content.sheet(item: $vm.transportRequest, onDismiss: { vm.transportSheetDismissed() }) { request in
            TransportPickerSheet(
                request: request,
                onConfirm: { id in vm.transportAnswered(id) },
                onCancel: { vm.transportCancelled() }
            )
            .interactiveDismissDisabled(true)
        }
    }
}

extension View {
    /// See `ClockInTransportHost`.
    func clockInTransportHost(_ vm: AttendanceViewModel) -> some View {
        modifier(ClockInTransportHost(vm: vm))
    }
}

// MARK: - Today's mode, with "Change"

/// Today's mode of transport as a chip on Home / Attendance ("Travelling by Two-wheeler" + "Change"), for a client
/// whose rule is on and a rep who has checked in. "Change" asks again and sends `PATCH /attendance/transport-mode` —
/// online only: with no connection, or a check-in still waiting in the offline queue, the rep is told why instead.
/// Draws nothing for every other client.
struct TransportModeChipView: View {
    @EnvironmentObject var appState: KiniAppState
    @ObservedObject var vm: AttendanceViewModel
    @ObservedObject private var rulesStore = AttendanceRulesStore.shared
    @ObservedObject private var cache = AttendanceCache.shared
    @State private var editing = false

    static func chip(rules: AttendanceRules, record: AttendanceRecord?, queued: Bool) -> TransportMode.Chip? {
        TransportMode.chip(active: rules.transportPromptActive, record: record, options: rules.transportModes, checkinQueued: queued)
    }

    var body: some View {
        if let chip = TransportModeChipView.chip(rules: rulesStore.rules, record: appState.today, queued: vm.hasQueuedCheckIn()) {
            card(chip)
        }
    }

    private func card(_ chip: TransportMode.Chip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "car.fill").foregroundColor(Brand.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chip.text).font(.subheadline).fontWeight(.semibold)
                    if let note = chip.note {
                        Text(note).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let action = chip.action {
                    actionView(action)
                }
            }
            if let message = vm.transportMessage {
                Text(message).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
        .sheet(isPresented: $editing) {
            TransportPickerSheet(
                request: TransportPickRequest(confirmLabel: "Save",
                                              options: rulesStore.rules.transportModes,
                                              initial: appState.today?.transportMode),
                onConfirm: { id in
                    editing = false
                    vm.changeTransportMode(id)
                },
                onCancel: { editing = false }
            )
        }
    }

    @ViewBuilder
    private func actionView(_ title: String) -> some View {
        if vm.transportBusy {
            ProgressView()
        } else {
            Button(title) {
                if vm.beginTransportChange() { editing = true }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Brand.red)
        }
    }
}

// MARK: - Offline punch notice

/// One line about offline check-in / check-out, drawn only when there is something to say:
///  - a punch is waiting to sync → "Checked in 09:12 — will sync when online";
///  - the server refused a queued punch → "Check-in 09:12 was not accepted: <reason>" with a Dismiss button (the refused
///    punch stays visible until the rep has read it).
struct OfflinePunchNoticeView: View {
    @ObservedObject private var cache = AttendanceCache.shared

    var body: some View {
        if let notice = OfflinePunchState.notice(punches: cache.punchesForCurrentUser(), zone: TimeZone.current) {
            HStack(spacing: 8) {
                Text(notice.text)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(notice.isError ? .red : .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if notice.isError {
                    Button("Dismiss") { cache.dismissRefused() }
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }
}

// MARK: - What Home and the Attendance screen add

/// Under the attendance card: the late line ("Late by 45 min", clients with shift rules), the offline-punch notice, the
/// travel-mode chip, and — on Home, for a client whose rule says no selfie — what happened to the one-tap punch (there
/// is no camera screen to report it). Draws nothing at all when there is nothing to say, so a client that configured no
/// rules sees exactly the screen it always had.
struct AttendanceStatusExtras: View {
    @EnvironmentObject var appState: KiniAppState
    @ObservedObject var vm: AttendanceViewModel
    @ObservedObject private var rulesStore = AttendanceRulesStore.shared
    @ObservedObject private var cache = AttendanceCache.shared
    /// Home passes true: the Attendance screen shows `vm.message` itself.
    var showsPunchMessage: Bool = false

    private var lateText: String? { AttendanceLate.label(appState.today?.late) }

    private var punchMessage: String? {
        guard showsPunchMessage, !rulesStore.rules.selfieRequired, !vm.message.isEmpty else { return nil }
        return vm.message
    }

    private var hasChip: Bool {
        TransportModeChipView.chip(rules: rulesStore.rules, record: appState.today, queued: vm.hasQueuedCheckIn()) != nil
    }

    private var hasNotice: Bool {
        OfflinePunchState.notice(punches: cache.punchesForCurrentUser(), zone: TimeZone.current) != nil
    }

    var body: some View {
        if lateText != nil || hasNotice || hasChip || punchMessage != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let late = lateText {
                    Text(late)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                }
                OfflinePunchNoticeView()
                TransportModeChipView(vm: vm)
                if let message = punchMessage {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The outcome of a one-tap punch is shown for a few seconds, like a toast, then cleared.
            .onChange(of: punchMessage ?? "", initial: true) { _, shown in
                if shown.isEmpty { return }
                Task {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    if vm.message == shown { vm.message = "" }
                }
            }
        }
    }
}
