//
//  TelecallerLogCallSheet.swift
//  Kinematic CRM
//
//  The telecaller's core action: after calling an assigned lead, log the
//  outcome. Modelled on MarketingVisitView's end-step (notes + status picker +
//  follow-up), minus all GPS — a telecaller is a phone agent.
//
//  On Save, the actions are orchestrated in order against the backend contract:
//    (a) POST /api/v1/crm/activities — the call (type "call", outbound), with
//        the disposition as `outcome`, remarks as `description`, completed now,
//        and the CallObserver duration if a call was placed from this sheet.
//    (b) PATCH /api/v1/crm/leads/:id { status } — only when the status changed.
//    (c) POST /api/v1/crm/activities — an open follow-up call (due_at) when set.
//    (d) POST /api/v1/crm/targets/entries (via createRupeeTargetEntry kind
//        "sales") — the optional scheme amount (₹).
//
//  Gated to telecallers at the shell; this sheet itself is a plain form.
//

import SwiftUI

struct TelecallerLogCallSheet: View {
    let lead: Lead
    /// Called once the save fully succeeds, so the presenting list can refresh.
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()

    /// The eight dispositions the backend accepts as `outcome`, verbatim.
    static let dispositions = [
        "Connected - Interested",
        "Connected - Not Interested",
        "Connected - Call Back",
        "No Answer",
        "Busy",
        "Switched Off",
        "Wrong Number",
        "Not Reachable",
    ]

    /// Rajkamal's lead statuses — the fallback when the tenant has no custom
    /// `lead_statuses` configured (it normally does, via statusOptions).
    private let defaultStatuses = [
        "new", "contacted", "interested", "visit_planned",
        "quotation", "converted", "not_interested", "later",
    ]

    // Campaign-specific picker options — verbatim per the backend activity
    // custom-field defs for App & DigiGold / After-Sales.
    private static let explainedOptions = [
        "Yes - Enrolled", "Explained - Will Visit Store",
        "Explained - Not Interested", "Already Using", "Not Explained",
    ]
    private static let ratingOptions = ["5", "4", "3", "2", "1"]
    private static let qualityOptions = ["Excellent", "Good", "Average", "Poor"]
    private static let priorityOptions = ["High", "Medium", "Low"]
    private static let interestOptions = ["Yes", "Maybe", "No"]

    /// Formats a date-only value as the backend expects (`yyyy-MM-dd`).
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The lead's campaign, read from its `campaign` custom field. Empty /
    /// missing / unknown → `.general`.
    private var campaign: LeadCampaign { LeadCampaign.of(lead) }

    // Form state
    @State private var disposition: String = ""          // required — empty until chosen
    @State private var nextStatus: String = ""           // defaults to the lead's current status
    @State private var hasFollowup: Bool = false
    @State private var followupDate: Date = Date().addingTimeInterval(86_400)
    @State private var amountText: String = ""
    @State private var remarks: String = ""

    @State private var saving: Bool = false
    @State private var errorMessage: String?
    /// True once the rep tapped Call from this sheet — gates whether we read a
    /// CallObserver duration onto the logged activity.
    @State private var callPlaced: Bool = false
    /// The tenant's own label for the "sales" rupee-target type ("Scheme Amount"
    /// for Rajkamal); falls back to that default until the types load.
    @State private var schemeLabel: String = "Scheme Amount"

    // Campaign-specific state — App & DigiGold
    @State private var hasAppDownloadDate: Bool = false
    @State private var appDownloadDate: Date = Date()
    @State private var digigoldExplained: String = ""
    @State private var goldSchemeExplained: String = ""
    @State private var appRating: String = ""
    @State private var bugsReported: String = ""
    @State private var featureRequests: String = ""

    // Campaign-specific state — After-Sales
    @State private var productSatisfaction: String = ""
    @State private var staffBehaviour: String = ""
    @State private var billingExperience: String = ""
    @State private var afterSalesService: String = ""
    @State private var customerRating: String = ""
    @State private var complaint: String = ""
    @State private var complaintPriority: String = ""
    @State private var resolutionRequired: Bool = false
    @State private var nextPurchaseInterest: String = ""
    @State private var referralPotential: String = ""

    private var canSave: Bool {
        !saving && !disposition.isEmpty
    }

    var body: some View {
        Form {
            leadSection
            dispositionSection
            statusSection
            followupSection
            campaignSection
            remarksSection
            saveSection
        }
        .navigationTitle("Log Call")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task { await fieldOverrides.load() }
        .task { await loadSchemeLabel() }
        .onAppear {
            // Default the status picker to where the lead is now, so an unchanged
            // selection is a no-op and any change moves the lead.
            if nextStatus.isEmpty { nextStatus = lead.status ?? "" }
        }
        .alert("Couldn't save",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var leadSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(lead.displayName).font(.system(size: 20, weight: .bold))
                if let p = lead.phone, !p.isEmpty {
                    Text(p).font(.subheadline).foregroundColor(.secondary)
                    CallButton(phone: p,
                               prefillSubject: "Call with \(lead.displayName)",
                               onCallInitiated: { callPlaced = true },
                               compact: false)
                } else {
                    Text("No phone number on this lead")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var dispositionSection: some View {
        Section("Disposition") {
            Picker("Outcome", selection: $disposition) {
                Text("Select…").tag("")
                ForEach(Self.dispositions, id: \.self) { d in
                    Text(d).tag(d)
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Move status to") {
            Picker("Status", selection: $nextStatus) {
                Text("Keep current").tag("")
                ForEach(fieldOverrides.statusOptions(default: defaultStatuses)) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
        }
    }

    @ViewBuilder
    private var followupSection: some View {
        Section("Follow-up") {
            Toggle("Set a follow-up", isOn: $hasFollowup)
            if hasFollowup {
                DatePicker("When", selection: $followupDate,
                           displayedComponents: [.date, .hourAndMinute])
            }
        }
    }

    /// The campaign-specific section. General keeps the phase-1 scheme (₹)
    /// field; App & DigiGold and After-Sales each render their own feedback
    /// block (no scheme field for those campaigns).
    @ViewBuilder
    private var campaignSection: some View {
        switch campaign {
        case .general:
            schemeSection
        case .appDigiGold:
            appDigiGoldSection
        case .afterSales:
            afterSalesSection
        }
    }

    @ViewBuilder
    private var schemeSection: some View {
        Section(schemeLabel) {
            TextField("₹ amount (optional)", text: $amountText)
                .keyboardType(.decimalPad)
        }
    }

    @ViewBuilder
    private var appDigiGoldSection: some View {
        Section("App & DigiGold") {
            Toggle("Set app download date", isOn: $hasAppDownloadDate)
            if hasAppDownloadDate {
                DatePicker("Downloaded on", selection: $appDownloadDate,
                           displayedComponents: [.date])
            }
            optionPicker("DigiGold explained", selection: $digigoldExplained,
                         options: Self.explainedOptions)
            optionPicker("Gold scheme explained", selection: $goldSchemeExplained,
                         options: Self.explainedOptions)
            optionPicker("App rating", selection: $appRating,
                         options: Self.ratingOptions)
            multilineField("Bugs reported", placeholder: "Any bugs the customer mentioned",
                           text: $bugsReported)
            multilineField("Feature requests", placeholder: "Anything the customer asked for",
                           text: $featureRequests)
        }
    }

    @ViewBuilder
    private var afterSalesSection: some View {
        Section("After-Sales") {
            optionPicker("Product satisfaction", selection: $productSatisfaction,
                         options: Self.qualityOptions)
            optionPicker("Staff behaviour", selection: $staffBehaviour,
                         options: Self.qualityOptions)
            optionPicker("Billing experience", selection: $billingExperience,
                         options: Self.qualityOptions)
            optionPicker("After-sales service", selection: $afterSalesService,
                         options: Self.qualityOptions)
            optionPicker("Customer rating", selection: $customerRating,
                         options: Self.ratingOptions)
            multilineField("Complaint", placeholder: "Any complaint raised",
                           text: $complaint)
            optionPicker("Complaint priority", selection: $complaintPriority,
                         options: Self.priorityOptions)
            Toggle("Resolution required", isOn: $resolutionRequired)
            optionPicker("Next purchase interest", selection: $nextPurchaseInterest,
                         options: Self.interestOptions)
            optionPicker("Referral potential", selection: $referralPotential,
                         options: Self.priorityOptions)
        }
    }

    /// A labelled "Select…"-prefixed picker; empty tag means "not set" so the
    /// save omits it.
    @ViewBuilder
    private func optionPicker(_ title: String, selection: Binding<String>,
                              options: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("Select…").tag("")
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
    }

    /// A captioned multiline text field matching the Remarks styling.
    @ViewBuilder
    private func multilineField(_ title: String, placeholder: String,
                                text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    @ViewBuilder
    private var remarksSection: some View {
        Section("Remarks") {
            TextField("Notes from the call", text: $remarks, axis: .vertical)
                .lineLimit(3...6)
                .onChange(of: remarks) { _, v in
                    if v.count > 2000 { remarks = String(v.prefix(2000)) }
                }
        }
    }

    @ViewBuilder
    private var saveSection: some View {
        Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if saving { ProgressView().tint(.white) }
                    Text(saving ? "Saving…" : "Save")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(canSave ? Brand.red : Color.gray.opacity(0.4))
            .disabled(!canSave)
        } footer: {
            if disposition.isEmpty {
                Text("Pick a disposition to save.")
            }
        }
    }

    // MARK: Actions

    private func loadSchemeLabel() async {
        guard let types = try? await CRMService.shared.rupeeTargetTypes() else { return }
        if let sales = types.first(where: { $0.key == "sales" }) {
            schemeLabel = sales.label
        }
    }

    /// Builds the activity `custom_fields` map for the lead's campaign, holding
    /// ONLY the fields the rep actually filled (trimmed-empty strings and
    /// unset pickers/toggles are omitted). General campaigns contribute none
    /// (their scheme ₹ flows through the rupee-target entry instead).
    private func buildCampaignCustomFields() -> [String: Any] {
        var cf: [String: Any] = [:]
        func putString(_ key: String, _ raw: String) {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { cf[key] = v }
        }
        switch campaign {
        case .general:
            break
        case .appDigiGold:
            if hasAppDownloadDate {
                cf["app_download_date"] = Self.dateOnlyFormatter.string(from: appDownloadDate)
            }
            putString("digigold_explained", digigoldExplained)
            putString("gold_scheme_explained", goldSchemeExplained)
            putString("app_rating", appRating)
            putString("bugs_reported", bugsReported)
            putString("feature_requests", featureRequests)
        case .afterSales:
            putString("product_satisfaction", productSatisfaction)
            putString("staff_behaviour", staffBehaviour)
            putString("billing_experience", billingExperience)
            putString("after_sales_service", afterSalesService)
            putString("customer_rating", customerRating)
            putString("complaint", complaint)
            putString("complaint_priority", complaintPriority)
            // Boolean toggle: only sent when flagged on (an untouched toggle is
            // treated as unset so it isn't recorded as a negative).
            if resolutionRequired { cf["resolution_required"] = true }
            putString("next_purchase_interest", nextPurchaseInterest)
            putString("referral_potential", referralPotential)
        }
        return cf
    }

    private func save() async {
        guard !disposition.isEmpty else { return }

        // Validate the optional scheme amount up front — a non-empty but
        // unparseable value blocks the save rather than being silently dropped.
        // Scheme (₹) is a General-campaign-only field; the other campaigns
        // never render it and never send it.
        var schemeAmount: Double? = nil
        if campaign == .general {
            let amtRaw = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !amtRaw.isEmpty {
                switch RupeeTargets.parseAmount(amtRaw) {
                case .ok(let v): schemeAmount = v
                case let other:
                    errorMessage = RupeeTargets.message(for: other) ?? "Enter a valid amount."
                    return
                }
            }
        }

        saving = true
        defer { saving = false }

        let trimmedRemarks = remarks.trimmingCharacters(in: .whitespacesAndNewlines)
        let isoNow = ISO8601DateFormatter().string(from: Date())

        do {
            // (a) The call activity — the critical record. Aborts on failure.
            var callBody: [String: Any] = [
                "type": "call",
                "direction": "outbound",
                "lead_id": lead.id,
                "subject": "Call with \(lead.displayName)",
                "outcome": disposition,
                "description": trimmedRemarks,
                "completed_at": isoNow,
                "status": "completed",
            ]
            if callPlaced, let duration = CallObserver.shared.consumeDuration(), duration > 0 {
                callBody["duration_seconds"] = duration
            }
            // Campaign-specific feedback — only the fields the rep actually
            // filled, sent on the call activity's custom_fields map. The
            // backend validates these against its activity custom-field defs.
            let campaignFields = buildCampaignCustomFields()
            if !campaignFields.isEmpty {
                callBody["custom_fields"] = campaignFields
            }
            _ = try await CRMService.shared.createActivity(callBody)

            // (b) Move the lead's status only when it actually changed.
            let newStatus = nextStatus.trimmingCharacters(in: .whitespaces)
            if !newStatus.isEmpty, newStatus != (lead.status ?? "") {
                _ = try await CRMService.shared.updateLead(id: lead.id, body: ["status": newStatus])
            }

            // (c) Optional follow-up — an open call activity with a due date.
            if hasFollowup {
                let followBody: [String: Any] = [
                    "type": "call",
                    "lead_id": lead.id,
                    "subject": "Follow-up call",
                    "due_at": ISO8601DateFormatter().string(from: followupDate),
                    "status": "open",
                ]
                _ = try await CRMService.shared.createActivity(followBody)
            }

            // (d) Optional scheme amount (₹) against the "sales" rupee target.
            if let amount = schemeAmount {
                try await CRMService.shared.createRupeeTargetEntry(
                    kind: "sales", amount: amount, leadId: lead.id, note: nil)
            }

            onSaved()
            dismiss()
        } catch {
            errorMessage = RupeeTargets.failureMessage(for: error, fallback: "Couldn't save the call. Please try again.")
        }
    }
}

/// The campaign a lead belongs to, read from its `campaign` custom field.
/// Drives both the Log Call sheet's campaign-specific feedback section and the
/// My Calls filter / row badge. Empty / missing / unrecognised → `.general`.
enum LeadCampaign: String, CaseIterable, Identifiable {
    case general
    case appDigiGold
    case afterSales

    var id: String { rawValue }

    /// Short label used by the My Calls filter chips and the row badge.
    var shortLabel: String {
        switch self {
        case .general: return "General"
        case .appDigiGold: return "App & DigiGold"
        case .afterSales: return "After-Sales"
        }
    }

    /// Maps the server `campaign` custom-field string to a case. "General
    /// Calls", empty, missing, and anything unrecognised all fall to `.general`.
    static func from(_ raw: String?) -> LeadCampaign {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
        case "App & DigiGold": return .appDigiGold
        case "After-Sales": return .afterSales
        default: return .general
        }
    }

    /// Classifies a lead by its `campaign` custom field.
    static func of(_ lead: Lead) -> LeadCampaign {
        from(lead.customFields?["campaign"]?.value)
    }
}
