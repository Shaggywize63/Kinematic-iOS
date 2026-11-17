//
//  CallingDeskView.swift
//  Kinematic CRM
//
//  Pharma "Calling Desk" for Maa Mansha Pharma — a daily tele-calling worklist.
//  A desk operator picks a day, works the generated customer list, and
//  dispositions each call with one of three statuses (Order Taken / Order
//  Pending / No Order). "Order Taken" additionally captures an order value.
//
//  Gated to Maa Mansha Pharma via `ClientFeatures.isMaaMansha` (the CRM More
//  menu only surfaces the entry for that client — see CRMTabView).
//
//  All dates / times are shown in IST (Asia/Kolkata), a hard product
//  requirement — see `DeskTime`.
//

import SwiftUI

struct CallingDeskView: View {
    private let service = CRMService.shared

    /// The day being worked. Defaults to today (IST).
    @State private var selectedDate: Date = Date()
    /// nil = "All". Any specific status narrows the list on the server.
    @State private var statusFilter: DeskStatus?
    @State private var searchText: String = ""
    /// Debounced mirror of `searchText` — what actually drives a refetch.
    @State private var debouncedSearch: String = ""

    @State private var tasks: [DeskCallTask] = []
    @State private var summary: DeskDaySummary?

    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Transient info line under the controls (generate result, 403 notice, …).
    @State private var banner: String?
    @State private var isGenerating = false
    /// Task ids currently being PATCHed, to disable their row while in flight.
    @State private var updatingIds: Set<String> = []

    /// Row whose Order Taken value is being captured.
    @State private var orderValueTask: DeskCallTask?

    /// The sections shown in the filter bar, in order.
    private let filters: [DeskStatus?] = [nil, .pending, .orderTaken, .orderPending, .noOrder]

    /// Single key that changes whenever any input that affects the fetch
    /// changes — drives `.task(id:)` so date / status / search all refetch.
    private var reloadKey: String {
        "\(DeskTime.dateKey.string(from: selectedDate))|\(statusFilter?.rawValue ?? "all")|\(debouncedSearch)"
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            if let banner {
                Text(banner)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 6)
            }
            summaryStrip
            Divider()
            listBody
        }
        .navigationTitle("Calling Desk")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await generateToday() }
                } label: {
                    if isGenerating {
                        ProgressView().tint(Brand.red)
                    } else {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                }
                .disabled(isGenerating)
                .accessibilityLabel("Generate today's list")
            }
        }
        // Refetch whenever the day, the status filter, or the (debounced)
        // search text changes.
        .task(id: reloadKey) { await load() }
        // Debounce the search field so we refetch after the user pauses typing.
        .onChange(of: searchText) { _, newValue in
            Task {
                let mine = newValue
                try? await Task.sleep(nanoseconds: 350_000_000)
                if mine == searchText { debouncedSearch = mine.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        .sheet(item: $orderValueTask) { task in
            OrderValueSheet(task: task) { amount in
                orderValueTask = nil
                Task { await disposition(task, status: .orderTaken, orderValue: amount) }
            } onCancel: {
                orderValueTask = nil
            }
        }
    }

    // MARK: Controls

    private var controlBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundColor(Brand.red)
                DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.timeZone, DeskTime.ist)
                Spacer()
                Text(DeskTime.prettyDate.string(from: selectedDate))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search name or phone", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { f in
                        filterChip(f)
                    }
                }
            }
        }
        .padding(.horizontal).padding(.top, 10).padding(.bottom, 8)
    }

    private func filterChip(_ f: DeskStatus?) -> some View {
        let isActive = statusFilter == f
        let title = f?.shortLabel ?? "All"
        return Button {
            statusFilter = f
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(isActive ? Brand.red : Color(uiColor: .secondarySystemBackground))
                .foregroundColor(isActive ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Summary strip

    private var summaryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                summaryTile("Assigned", "\(summary?.assigned ?? 0)", .primary)
                summaryTile("Called", "\(summary?.called ?? 0)", Brand.info)
                summaryTile("Order Taken", "\(summary?.orderTaken ?? 0)", Brand.success)
                summaryTile("Order Pending", "\(summary?.orderPending ?? 0)", Brand.caution)
                summaryTile("No Order", "\(summary?.noOrder ?? 0)", .secondary)
                summaryTile("Order Value", RupeeTargets.inr(summary?.ordersValue ?? 0), Brand.success)
            }
            .padding(.horizontal).padding(.vertical, 10)
        }
    }

    private func summaryTile(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minWidth: 92, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: List

    @ViewBuilder
    private var listBody: some View {
        if isLoading && tasks.isEmpty {
            Spacer()
            ProgressView().tint(Brand.red)
            Spacer()
        } else if let errorMessage, tasks.isEmpty {
            errorState(errorMessage)
        } else if tasks.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        DeskCallRow(
                            task: task,
                            isUpdating: updatingIds.contains(task.id),
                            onDial: { dial(task) },
                            onSelect: { status in
                                if status.requiresOrderValue {
                                    orderValueTask = task
                                } else {
                                    Task { await disposition(task, status: status, orderValue: nil) }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal).padding(.vertical, 12)
            }
            .refreshable { await load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "phone.down.circle")
                .font(.system(size: 42)).foregroundColor(.secondary)
            Text("No customers for this day")
                .font(.system(size: 15, weight: .semibold))
            Text("Pick another day, or tap the refresh icon to generate today's list (admins only).")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36)).foregroundColor(Brand.caution)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") { Task { await load() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Brand.red)
            Spacer()
        }
    }

    // MARK: Actions

    private func dial(_ task: DeskCallTask) {
        guard let normalized = CallHelper.normalize(task.customerPhone) else { return }
        CallHelper.dial(normalized: normalized)
    }

    private func load() async {
        let dateKey = DeskTime.dateKey.string(from: selectedDate)
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await service.deskCallList(
                date: dateKey,
                status: statusFilter,
                query: debouncedSearch,
                mine: true
            )
            tasks = page.rows
            errorMessage = nil
        } catch {
            errorMessage = friendly(error)
        }
        // Summary is best-effort — a failure here must not blank the worklist.
        summary = try? await service.deskSummary(date: dateKey)
    }

    private func disposition(_ task: DeskCallTask, status: DeskStatus, orderValue: Double?) async {
        let dateKey = DeskTime.dateKey.string(from: selectedDate)
        updatingIds.insert(task.id)
        defer { updatingIds.remove(task.id) }
        do {
            let updated = try await service.deskUpdateTask(
                id: task.id,
                status: status,
                orderValue: orderValue,
                notes: nil
            )
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx] = updated
            }
            // If a specific status filter is active and the task no longer
            // matches it, drop it from the visible list so the filter stays true.
            if let f = statusFilter, updated.dispositionStatus != f {
                tasks.removeAll { $0.id == task.id }
            }
            banner = nil
        } catch {
            banner = friendly(error)
        }
        summary = try? await service.deskSummary(date: dateKey)
    }

    private func generateToday() async {
        let dateKey = DeskTime.dateKey.string(from: selectedDate)
        isGenerating = true
        defer { isGenerating = false }
        do {
            let result = try await service.deskGenerate(date: dateKey)
            let created = result.created ?? 0
            let existing = result.existing ?? 0
            banner = "List ready — \(created) new, \(existing) already there."
            await load()
        } catch CRMServiceError.serverStatus(403, _), CRMServiceError.badResponse(403) {
            banner = "Generating the list is an admin-only action."
        } catch {
            banner = friendly(error)
        }
    }

    private func friendly(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Row

private struct DeskCallRow: View {
    let task: DeskCallTask
    let isUpdating: Bool
    let onDial: () -> Void
    let onSelect: (DeskStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if let phone = task.customerPhone, !phone.isEmpty {
                        Text(phone)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    metaRow
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 8) {
                if CallHelper.normalize(task.customerPhone) != nil {
                    actionButton("Call", system: "phone.fill", tint: Brand.info, action: onDial)
                }
                Spacer()
                if isUpdating {
                    ProgressView().tint(Brand.red)
                }
            }

            // The three dispositions.
            HStack(spacing: 8) {
                ForEach(DeskStatus.dispositions, id: \.self) { s in
                    dispositionButton(s)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var metaRow: some View {
        let status = task.dispositionStatus
        HStack(spacing: 6) {
            if status == .orderTaken, let v = task.orderValue {
                Text(RupeeTargets.inr(v))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Brand.success)
            }
            if let called = DeskTime.calledTime(task.calledAt) {
                Text("Called \(called)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusBadge: some View {
        let status = task.dispositionStatus
        return Text(status.shortLabel)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(badgeColor(status).opacity(0.15))
            .foregroundColor(badgeColor(status))
            .clipShape(Capsule())
    }

    private func dispositionButton(_ s: DeskStatus) -> some View {
        let isCurrent = task.dispositionStatus == s
        return Button {
            onSelect(s)
        } label: {
            Text(s.shortLabel)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isCurrent ? badgeColor(s) : badgeColor(s).opacity(0.12))
                .foregroundColor(isCurrent ? .white : badgeColor(s))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
    }

    private func actionButton(_ title: String, system: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: system).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(tint.opacity(0.12))
            .foregroundColor(tint)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func badgeColor(_ s: DeskStatus) -> Color {
        switch s {
        case .orderTaken:   return Brand.success
        case .orderPending: return Brand.caution
        case .noOrder:      return .secondary
        case .pending:      return Brand.info
        }
    }
}

// MARK: - Order value capture

private struct OrderValueSheet: View {
    let task: DeskCallTask
    let onSave: (Double) -> Void
    let onCancel: () -> Void

    @State private var amountText: String = ""

    private var parsedAmount: Double? {
        var s = amountText.trimmingCharacters(in: .whitespaces)
        for mark in ["₹", ",", " "] { s = s.replacingOccurrences(of: mark, with: "") }
        guard let v = Double(s), v >= 0, v.isFinite else { return nil }
        return v
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(task.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    if let phone = task.customerPhone, !phone.isEmpty {
                        Text(phone).font(.system(size: 13)).foregroundColor(.secondary)
                    }
                } header: {
                    Text("Order Taken")
                }

                Section {
                    HStack(spacing: 6) {
                        Text("₹").font(.system(size: 17, weight: .semibold)).foregroundColor(.secondary)
                        TextField("Order value", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Order Value")
                } footer: {
                    Text("Enter the value of the order placed on this call.")
                }
            }
            .navigationTitle("Capture Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = parsedAmount { onSave(v) }
                    }
                    .disabled(parsedAmount == nil)
                }
            }
        }
    }
}

// MARK: - IST date / time helpers (hard product requirement)

private enum DeskTime {
    /// Asia/Kolkata, with a +05:30 fallback so the app never falls back to UTC
    /// if the tz database somehow lacks the identifier.
    static let ist: TimeZone = TimeZone(identifier: "Asia/Kolkata")
        ?? TimeZone(secondsFromGMT: 19800)
        ?? TimeZone(secondsFromGMT: 0)!

    /// "YYYY-MM-DD" in IST — the `date` query param the backend expects.
    static let dateKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = ist
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Human day label for the header, e.g. "Thu, 13 Nov".
    static let prettyDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = ist
        f.dateFormat = "EEE, d MMM"
        return f
    }()

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = ist
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Format an ISO-8601 `called_at` as an IST clock time ("9:30 AM"), or nil.
    static func calledTime(_ iso: String?) -> String? {
        guard let date = RupeeTargets.parseTimestamp(iso) else { return nil }
        return clock.string(from: date)
    }
}
