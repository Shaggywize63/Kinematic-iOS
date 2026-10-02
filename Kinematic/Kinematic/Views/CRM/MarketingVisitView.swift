//
//  MarketingVisitView.swift
//  Kinematic CRM
//
//  Rajkamal's ad-hoc "Marketing Visit" — a GPS Start → End activity tied to a
//  CRM lead. The rep captures a one-shot GPS fix, then either creates a new
//  customer on the spot (name + 10-digit phone + city + area) or picks an
//  existing lead, and taps "Start Visit". While a visit is open they can Call /
//  WhatsApp the lead, jot notes, move the lead's status (the client's custom
//  statuses), set a follow-up, and tap "End Visit". A list of their recent
//  visits renders below.
//
//  Entirely separate from the outlet-visit flow (StoreVisitView / /api/v1/visits)
//  — this never touches appState.selectedOutlet. Gated to Rajkamal at every
//  entry point (ClientFeatures.isRajkamal).
//

import SwiftUI
import CoreLocation
import Combine

// MARK: - View model

@MainActor
final class MarketingVisitViewModel: ObservableObject {
    enum Phase: Equatable { case start, active }

    @Published var phase: Phase = .start
    @Published var activeVisit: MarketingVisit?
    @Published var activeLead: Lead?
    @Published var loadingActive: Bool = true
    @Published var starting: Bool = false
    @Published var ending: Bool = false
    @Published var errorMessage: String?

    // Recent visits + a per-lead cache so the cards can show Call / WhatsApp.
    @Published var visits: [MarketingVisit] = []
    @Published var leadsById: [String: Lead] = [:]
    @Published var loadingVisits: Bool = false

    private let api = CRMService.shared

    /// Resume an already-open visit (the backend enforces one open visit per
    /// rep), then load the recent-visits list.
    func bootstrap() async {
        loadingActive = true
        if let v = try? await api.activeVisit() {
            activeVisit = v
            phase = .active
            if let lid = v.leadId {
                activeLead = try? await api.getLead(id: lid)
            }
        }
        loadingActive = false
        await loadVisits()
    }

    func start(leadId: String?, lead: [String: Any]?, latitude: Double?, longitude: Double?, purpose: String?) async -> Bool {
        starting = true
        defer { starting = false }
        do {
            let result = try await api.startVisit(leadId: leadId, lead: lead, latitude: latitude, longitude: longitude, purpose: purpose)
            activeVisit = result.visit
            activeLead = result.lead
            phase = .active
            await loadVisits()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func end(latitude: Double?, longitude: Double?, notes: String?, nextStatus: String?, nextFollowupAt: String?) async -> Bool {
        guard let id = activeVisit?.id else { return false }
        ending = true
        defer { ending = false }
        do {
            _ = try await api.endVisit(id: id, latitude: latitude, longitude: longitude,
                                       outcome: nil, notes: notes,
                                       nextStatus: nextStatus, nextFollowupAt: nextFollowupAt)
            activeVisit = nil
            activeLead = nil
            phase = .start
            await loadVisits()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadVisits() async {
        loadingVisits = true
        defer { loadingVisits = false }
        do {
            visits = try await api.listMarketingVisits(mine: true, status: nil)
            // Enrich a bounded set of leads so the cards can show Call / WhatsApp.
            // Sequential (on the main actor) to keep it simple and avoid any
            // cross-actor Sendable juggling — the list is the rep's own visits,
            // so it's small in practice.
            let ids = visits.compactMap { $0.leadId }
            var seen = Set<String>()
            var fetched = 0
            for id in ids where !seen.contains(id) {
                seen.insert(id)
                if leadsById[id] != nil { continue }
                if fetched >= 25 { break }
                fetched += 1
                if let lead = try? await api.getLead(id: id) {
                    leadsById[id] = lead
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Root view

struct MarketingVisitView: View {
    /// When presented modally (field-force Home full-screen cover) the caller
    /// passes a closer so the view can offer a "Done" button. When pushed onto
    /// a NavigationStack (CRM More menu) this stays nil and the back button
    /// handles dismissal.
    var onClose: (() -> Void)? = nil

    @StateObject private var vm = MarketingVisitViewModel()
    @StateObject private var locator = OneShotLocationProvider()
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()
    @StateObject private var leadsVM = LeadsViewModel()

    // Start-form state
    private enum StartMode: Hashable { case new, existing }
    @State private var mode: StartMode = .new
    @State private var firstName: String = ""
    @State private var phone: String = ""
    @State private var city: String = ""
    @State private var area: String = ""
    @State private var purpose: String = ""
    @State private var selectedLead: Lead?

    // Active-visit state
    @State private var notes: String = ""
    @State private var nextStatus: String = ""
    @State private var hasFollowup: Bool = false
    @State private var followupDate: Date = Date().addingTimeInterval(86_400)

    /// Scope for the built-in field-override gate. Rajkamal walk-in customers
    /// are consumers (B2C); a "b2b" tenant flips it. Mirrors how the lead
    /// forms derive scope from the tenant's business_type.
    private var isB2C: Bool { fieldOverrides.businessType.lowercased() != "b2b" }

    private let defaultStatuses = ["new", "working", "qualified", "unqualified", "converted", "lost"]

    var body: some View {
        Group {
            if vm.loadingActive {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Checking for an open visit…")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    if vm.phase == .active {
                        activeVisitSections
                    } else {
                        startSections
                    }
                    visitsSection
                }
            }
        }
        .navigationTitle("Marketing Visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
        .task { await fieldOverrides.load() }
        .task { await vm.bootstrap() }
        .onAppear {
            if locator.coordinate == nil && !locator.isLocating {
                locator.requestLocation()
            }
        }
        // Capture a fresh fix for the end coordinate the moment a visit opens.
        .onChange(of: vm.phase) { _, newPhase in
            if newPhase == .active { locator.requestLocation() }
        }
        // Prime the lead list the first time the rep switches to "Existing lead".
        .onChange(of: mode) { _, newMode in
            if newMode == .existing && leadsVM.leads.isEmpty && selectedLead == nil {
                Task { await leadsVM.refresh() }
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { vm.errorMessage != nil },
                                    set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: Start phase

    @ViewBuilder
    private var startSections: some View {
        Section {
            locationRow
        } header: {
            Text("Location")
        } footer: {
            Text("Your current location is captured and saved with the visit.")
        }

        Section {
            Picker("Customer", selection: $mode) {
                Text("New customer").tag(StartMode.new)
                Text("Existing lead").tag(StartMode.existing)
            }
            .pickerStyle(.segmented)
        }

        if mode == .new {
            newCustomerSection
        } else {
            existingLeadSection
        }

        Section("Purpose (optional)") {
            TextField("e.g. Product demo, Site survey", text: $purpose)
                .onChange(of: purpose) { _, v in
                    if v.count > 64 { purpose = String(v.prefix(64)) }
                }
        }

        Section {
            Button {
                Task { await startTapped() }
            } label: {
                HStack {
                    Spacer()
                    if vm.starting { ProgressView().tint(.white) }
                    Text(vm.starting ? "Starting…" : "Start Visit")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(canStart ? Brand.red : Color.gray.opacity(0.4))
            .disabled(!canStart)
        }
    }

    @ViewBuilder
    private var newCustomerSection: some View {
        // Built-in lead columns (first_name / phone / city) are gated through
        // the field-override contract exactly like the lead-create form —
        // deferred until the override map loads, hidden when the admin hid
        // them, and relabelled via labelFor. `area` is a custom jsonb field,
        // so it renders unconditionally.
        if fieldOverrides.didLoad {
            Section("New customer") {
                if !fieldOverrides.isHidden("first_name", isB2C: isB2C) {
                    TextField(fieldOverrides.labelFor("first_name", defaultLabel: "Name", isB2C: isB2C),
                              text: $firstName)
                }
                if !fieldOverrides.isHidden("phone", isB2C: isB2C) {
                    TextField(fieldOverrides.labelFor("phone", defaultLabel: "Phone (10 digits)", isB2C: isB2C),
                              text: Binding(
                                get: { phone },
                                set: { phone = String($0.filter { $0.isNumber }.prefix(10)) }
                              ))
                        .keyboardType(.phonePad)
                }
                if !fieldOverrides.isHidden("city", isB2C: isB2C) {
                    TextField(fieldOverrides.labelFor("city", defaultLabel: "City", isB2C: isB2C),
                              text: $city)
                }
                TextField("Area", text: $area)
            }
        } else {
            Section { ProgressView() }
        }
    }

    @ViewBuilder
    private var existingLeadSection: some View {
        Section("Find a lead") {
            if let lead = selectedLead {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lead.displayName).font(.system(size: 15, weight: .semibold))
                        if let p = lead.phone, !p.isEmpty {
                            Text(p).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button("Change") { selectedLead = nil }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Brand.red)
                }
            } else {
                TextField("Search by name or phone", text: $leadsVM.search)
                    .autocorrectionDisabled()
                    .onChange(of: leadsVM.search) { _, _ in leadsVM.searchChanged() }
                if leadsVM.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if leadsVM.leads.isEmpty {
                    Text(leadsVM.search.trimmingCharacters(in: .whitespaces).isEmpty
                         ? "Type a name or phone to search"
                         : "No matching leads")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(Array(leadsVM.leads.prefix(15))) { lead in
                        Button {
                            selectedLead = lead
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lead.displayName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                    if let p = lead.phone, !p.isEmpty {
                                        Text(p).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill").foregroundColor(Brand.red)
            if let c = locator.coordinate {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location captured").font(.subheadline)
                    Text(String(format: "%.5f, %.5f", c.latitude, c.longitude))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else if locator.isLocating {
                Text("Capturing current location…")
                Spacer()
                ProgressView()
            } else {
                Text("Location not captured")
                Spacer()
                Button("Retry") { locator.requestLocation() }
            }
        }
        if let msg = locator.errorMessage {
            Text(msg).font(.caption).foregroundColor(.secondary)
        }
    }

    private var canStart: Bool {
        if vm.starting { return false }
        switch mode {
        case .new:
            let nameOK = !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // Phone required (10 digits) unless the admin hid the phone field.
            let phoneOK = fieldOverrides.isHidden("phone", isB2C: isB2C) || phone.count == 10
            return nameOK && phoneOK
        case .existing:
            return selectedLead != nil
        }
    }

    private func startTapped() async {
        let coord = locator.coordinate
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        var leadBody: [String: Any]? = nil
        var leadId: String? = nil

        switch mode {
        case .existing:
            leadId = selectedLead?.id
        case .new:
            var lead: [String: Any] = ["is_b2c": isB2C]
            let fn = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fn.isEmpty, !fieldOverrides.isHidden("first_name", isB2C: isB2C) {
                lead["first_name"] = fn
            }
            if phone.count == 10, !fieldOverrides.isHidden("phone", isB2C: isB2C) {
                lead["phone"] = phone
            }
            let ct = city.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ct.isEmpty, !fieldOverrides.isHidden("city", isB2C: isB2C) {
                lead["city"] = ct
            }
            let ar = area.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ar.isEmpty {
                lead["custom_fields"] = ["area": ar]
            }
            leadBody = lead
        }

        let ok = await vm.start(
            leadId: leadId,
            lead: leadBody,
            latitude: coord?.latitude,
            longitude: coord?.longitude,
            purpose: trimmedPurpose.isEmpty ? nil : trimmedPurpose
        )
        if ok {
            // Clear the start form so a later visit starts fresh.
            firstName = ""; phone = ""; city = ""; area = ""; purpose = ""
            selectedLead = nil; leadsVM.search = ""
        }
    }

    // MARK: Active phase

    @ViewBuilder
    private var activeVisitSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeLeadName).font(.system(size: 20, weight: .bold))
                        if let p = activeLeadPhone, !p.isEmpty {
                            Text(p).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    inProgressBadge
                }
                if let started = vm.activeVisit?.detail?.startedAt {
                    Label("Started \(MarketingVisitDate.short(started))", systemImage: "clock")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let p = activeLeadPhone, !p.isEmpty {
                    HStack(spacing: 8) {
                        CallButton(phone: p,
                                   prefillSubject: "Call with \(activeLeadName)",
                                   onCallInitiated: {},
                                   compact: false)
                        if WhatsAppHelper.canOpen(phone: p) {
                            WhatsAppButton(phone: p,
                                           prefillText: "Hi \(activeLeadName), ",
                                           compact: false)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }

        Section("Notes") {
            TextField("What happened on this visit?", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .onChange(of: notes) { _, v in
                    if v.count > 2000 { notes = String(v.prefix(2000)) }
                }
        }

        Section("Move status to") {
            Picker("Status", selection: $nextStatus) {
                Text("Don't change").tag("")
                ForEach(fieldOverrides.statusOptions(default: defaultStatuses)) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
        }

        Section("Follow-up") {
            Toggle("Set next follow-up", isOn: $hasFollowup)
            if hasFollowup {
                DatePicker("When", selection: $followupDate,
                           displayedComponents: [.date, .hourAndMinute])
            }
        }

        Section {
            Button {
                Task { await endTapped() }
            } label: {
                HStack {
                    Spacer()
                    if vm.ending { ProgressView().tint(.white) }
                    Text(vm.ending ? "Ending…" : "End Visit")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(vm.ending ? Color.gray.opacity(0.4) : Brand.red)
            .disabled(vm.ending)
        } footer: {
            locationFooter
        }
    }

    @ViewBuilder
    private var locationFooter: some View {
        if locator.coordinate != nil {
            Text("Your current location will be saved as the visit's end point.")
        } else if locator.isLocating {
            Text("Capturing your end location…")
        } else {
            Text("End location unavailable — the visit still ends.")
        }
    }

    private var inProgressBadge: some View {
        Text("IN PROGRESS")
            .font(.system(size: 10, weight: .heavy)).tracking(0.8)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Brand.red.opacity(0.14))
            .foregroundColor(Brand.red)
            .cornerRadius(6)
    }

    private var activeLeadName: String {
        vm.activeLead?.displayName ?? vm.activeVisit?.leadNameFromSubject ?? "Lead"
    }
    private var activeLeadPhone: String? { vm.activeLead?.phone }

    private func endTapped() async {
        let coord = locator.coordinate
        let followupIso = hasFollowup ? MarketingVisitDate.iso(from: followupDate) : nil
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await vm.end(
            latitude: coord?.latitude,
            longitude: coord?.longitude,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            nextStatus: nextStatus.isEmpty ? nil : nextStatus,
            nextFollowupAt: followupIso
        )
        if ok {
            notes = ""; nextStatus = ""; hasFollowup = false
            followupDate = Date().addingTimeInterval(86_400)
        }
    }

    // MARK: Recent visits

    @ViewBuilder
    private var visitsSection: some View {
        Section("Your Visits") {
            if vm.loadingVisits && vm.visits.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if vm.visits.isEmpty {
                Text("No visits yet").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(vm.visits) { visit in
                    visitCard(visit)
                }
            }
        }
    }

    @ViewBuilder
    private func visitCard(_ visit: MarketingVisit) -> some View {
        let lead = visit.leadId.flatMap { vm.leadsById[$0] }
        let name = lead?.displayName ?? visit.leadNameFromSubject
        let phone = lead?.phone
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.system(size: 15, weight: .semibold))
                Spacer()
                statusChip(visit)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let started = visit.detail?.startedAt, !started.isEmpty {
                    Text("Started \(MarketingVisitDate.short(started))")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let ended = visit.detail?.endedAt, !ended.isEmpty {
                    Text("Ended \(MarketingVisitDate.short(ended))")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let fu = visit.detail?.nextFollowupAt, !fu.isEmpty {
                    Label("Follow-up \(MarketingVisitDate.short(fu))", systemImage: "bell")
                        .font(.caption).foregroundColor(Brand.red)
                }
            }
            if let p = phone, !p.isEmpty {
                HStack(spacing: 8) {
                    CallButton(phone: p, prefillSubject: "Call with \(name)", onCallInitiated: {})
                    if WhatsAppHelper.canOpen(phone: p) {
                        WhatsAppButton(phone: p, prefillText: "Hi \(name), ")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusChip(_ visit: MarketingVisit) -> some View {
        let done = !visit.isInProgress
        Text(done ? "COMPLETED" : "IN PROGRESS")
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((done ? Brand.success : Brand.red).opacity(0.14))
            .foregroundColor(done ? Brand.success : Brand.red)
            .cornerRadius(6)
    }
}
