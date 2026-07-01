import SwiftUI

// MARK: - Shared Leave UI helpers
//
// Small building blocks reused across LeaveHomeView / RegularizationView /
// LeaveApprovalsView: a status chip, a tolerant hex-colour parser (leave
// types ship a brand colour from the web settings panel) and light date
// helpers. Kept `internal` so all three files in this folder can share them.

enum LeaveUI {
    /// Tolerant `#rrggbb` / `rrggbb` parser. Mirrors the private helper used
    /// by the CRM kanban stages so leave-type colours render identically.
    static func color(fromHex raw: String?) -> Color? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard trimmed.count == 6, let v = UInt32(trimmed, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// Tint + label for a request/regularization `status` string.
    static func statusTint(_ status: String?) -> Color {
        switch (status ?? "").lowercased() {
        case "approved":  return Brand.success
        case "rejected":  return Brand.red
        case "cancelled", "canceled": return .gray
        default:          return Brand.caution   // pending
        }
    }

    /// "yyyy-MM-dd" → "d MMM" for compact display. Falls back to the raw
    /// string when it can't be parsed.
    static func prettyDate(_ ymd: String?) -> String {
        guard let ymd = ymd else { return "—" }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let d = inFmt.date(from: String(ymd.prefix(10))) else { return ymd }
        let out = DateFormatter()
        out.dateFormat = "d MMM"
        return out.string(from: d)
    }

    static func ymd(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

/// Small pill that colours itself by status.
struct LeaveStatusChip: View {
    let status: String?
    var body: some View {
        let tint = LeaveUI.statusTint(status)
        Text((status ?? "pending").capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15))
            .foregroundColor(tint)
            .cornerRadius(6)
    }
}

// MARK: - Leave Home

/// Leave dashboard: per-type balance cards + the rep's own leave requests
/// (with cancel on pending). An "Apply Leave" sheet raises a new request.
/// Data comes from GET /leave/balances, GET /leave/requests, GET /leave/types.
struct LeaveHomeView: View {
    @State private var balances: [LeaveBalance] = []
    @State private var requests: [LeaveRequest] = []
    @State private var types: [LeaveType] = []
    @State private var isLoading = true
    @State private var didLoad = false
    @State private var showApply = false

    /// Supervisors/admins get the Approvals entry. Mirrors the role gate used
    /// in CRMTabView (`role != executive / field_executive` ⇒ manager). If the
    /// role string is unexpected we still show it and let the API 403 handle it.
    private var isManager: Bool {
        let r = (Session.currentUser?.role ?? "").lowercased()
        return r != "executive" && r != "field_executive"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                navSection
                balanceSection
                requestsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("Leave")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showApply = true
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(Brand.red)
                }
                .disabled(types.isEmpty)
            }
        }
        .sheet(isPresented: $showApply) {
            ApplyLeaveSheet(types: types) { await load() }
        }
        .task {
            guard !didLoad else { return }
            await load()
        }
        .refreshable { await load() }
    }

    // MARK: Navigation shortcuts

    @ViewBuilder private var navSection: some View {
        VStack(spacing: 10) {
            NavigationLink {
                RegularizationView()
            } label: {
                navRow(icon: "clock.arrow.circlepath", tint: Brand.info, title: "Attendance Regularization", subtitle: "Fix a missing or wrong punch")
            }
            if isManager {
                NavigationLink {
                    LeaveApprovalsView()
                } label: {
                    navRow(icon: "checkmark.seal.fill", tint: Brand.success, title: "Approvals", subtitle: "Pending leave & regularizations")
                }
            }
        }
    }

    private func navRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient)
                    .frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                Text(subtitle).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    // MARK: Balances

    @ViewBuilder private var balanceSection: some View {
        HStack {
            Text("Balances").font(.headline)
            Spacer()
        }
        if isLoading && !didLoad {
            ProgressView().tint(Brand.red).frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if balances.isEmpty {
            emptyCard(icon: "calendar", text: "No leave balances yet")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(balances) { BalanceCard(balance: $0) }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Requests

    @ViewBuilder private var requestsSection: some View {
        HStack {
            Text("My Requests").font(.headline)
            Spacer()
        }
        if isLoading && !didLoad {
            EmptyView()
        } else if requests.isEmpty {
            emptyCard(icon: "tray", text: "No leave requests yet")
        } else {
            VStack(spacing: 10) {
                ForEach(requests) { req in
                    LeaveRequestRow(request: req, typeName: typeName(req.leaveTypeId)) {
                        await cancel(req)
                    }
                }
            }
        }
    }

    private func typeName(_ id: String?) -> String {
        if let id = id, let t = types.first(where: { $0.id == id }) { return t.name }
        return "Leave"
    }

    private func emptyCard(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.gray.opacity(0.5))
            Text(text).font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    // MARK: Data

    private func load() async {
        await MainActor.run { isLoading = true }
        async let b = KinematicRepository.shared.fetchLeaveBalances()
        async let r = KinematicRepository.shared.fetchMyLeaveRequests()
        async let t = KinematicRepository.shared.fetchLeaveTypes()
        let (bal, reqs, tps) = await (b, r, t)
        await MainActor.run {
            self.balances = bal
            self.requests = reqs
            self.types = tps
            self.isLoading = false
            self.didLoad = true
        }
    }

    private func cancel(_ req: LeaveRequest) async {
        let ok = await KinematicRepository.shared.cancelLeaveRequest(id: req.id)
        if ok { await load() }
    }
}

// MARK: - Balance card

private struct BalanceCard: View {
    let balance: LeaveBalance
    private var tint: Color { LeaveUI.color(fromHex: balance.color) ?? Brand.info }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(balance.name ?? balance.code ?? "Leave")
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
            }
            if balance.unlimited == true {
                Text("Unlimited")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(tint)
            } else {
                Text(fmt(balance.available))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(tint)
                Text("available")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Divider().padding(.vertical, 2)
            HStack(spacing: 10) {
                metric("Used", balance.used)
                metric("Pending", balance.pending)
                if balance.unlimited != true { metric("Total", balance.entitled) }
            }
        }
        .padding(14)
        .frame(width: 180, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }

    private func metric(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(fmt(value)).font(.caption).fontWeight(.semibold)
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
        }
    }

    private func fmt(_ v: Double?) -> String {
        guard let v = v else { return "0" }
        return v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }
}

// MARK: - Request row

private struct LeaveRequestRow: View {
    let request: LeaveRequest
    let typeName: String
    let onCancel: () async -> Void
    @State private var cancelling = false

    private var isPending: Bool { (request.status ?? "pending").lowercased() == "pending" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(request.leaveTypeName ?? typeName)
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                LeaveStatusChip(status: request.status)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption2).foregroundColor(.secondary)
                Text("\(LeaveUI.prettyDate(request.fromDate)) – \(LeaveUI.prettyDate(request.toDate))")
                    .font(.caption).foregroundColor(.secondary)
                if let days = request.days {
                    Text("· \(days.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(days)) : String(format: "%.1f", days)) day\(days == 1 ? "" : "s")")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if let reason = request.reason, !reason.isEmpty {
                Text(reason).font(.caption2).foregroundColor(.secondary).lineLimit(2)
            }
            if let note = request.decisionNote, !note.isEmpty {
                Text("Note: \(note)").font(.caption2).foregroundColor(.secondary).italic()
            }
            if isPending {
                Button {
                    Task { cancelling = true; await onCancel(); cancelling = false }
                } label: {
                    HStack(spacing: 4) {
                        if cancelling { ProgressView().scaleEffect(0.7) }
                        Text(cancelling ? "Cancelling…" : "Cancel Request")
                    }
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(Brand.red)
                }
                .disabled(cancelling)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

// MARK: - Apply Leave sheet

private struct ApplyLeaveSheet: View {
    let types: [LeaveType]
    let onSubmitted: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTypeId: String = ""
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var halfDayStart = false
    @State private var halfDayEnd = false
    @State private var reason = ""
    @State private var contactNumber = ""
    @State private var attachmentUrl = ""
    @State private var isSubmitting = false
    @State private var error: String?

    private var selectedType: LeaveType? { types.first(where: { $0.id == selectedTypeId }) }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Leave Type")) {
                    Picker("Type", selection: $selectedTypeId) {
                        ForEach(types) { Text($0.name).tag($0.id) }
                    }
                }
                Section(header: Text("Dates")) {
                    DatePicker("From", selection: $fromDate, displayedComponents: .date)
                    DatePicker("To", selection: $toDate, in: fromDate..., displayedComponents: .date)
                    if selectedType?.allowHalfDay == true {
                        Toggle("Half day (start)", isOn: $halfDayStart)
                        Toggle("Half day (end)", isOn: $halfDayEnd)
                    }
                }
                Section(header: Text("Reason")) {
                    TextEditor(text: $reason).frame(minHeight: 90)
                }
                Section(header: Text("Contact (optional)")) {
                    TextField("Contact number while away", text: $contactNumber)
                        .keyboardType(.phonePad)
                }
                if selectedType?.requiresAttachment == true {
                    Section(header: Text("Attachment URL")) {
                        TextField("https://…", text: $attachmentUrl)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                    }
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
                        .background(canSubmit ? Brand.red : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!canSubmit || isSubmitting)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Apply Leave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if selectedTypeId.isEmpty { selectedTypeId = types.first?.id ?? "" }
            }
        }
    }

    private var canSubmit: Bool { !selectedTypeId.isEmpty && toDate >= fromDate }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        error = nil
        let (ok, msg) = await KinematicRepository.shared.applyLeave(
            leaveTypeId: selectedTypeId,
            fromDate: LeaveUI.ymd(fromDate),
            toDate: LeaveUI.ymd(toDate),
            halfDayStart: (selectedType?.allowHalfDay == true && halfDayStart) ? true : nil,
            halfDayEnd: (selectedType?.allowHalfDay == true && halfDayEnd) ? true : nil,
            reason: reason,
            contactNumber: contactNumber,
            attachmentUrl: attachmentUrl
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
