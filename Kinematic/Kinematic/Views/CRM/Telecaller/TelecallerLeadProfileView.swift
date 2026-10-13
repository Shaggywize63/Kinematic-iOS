//
//  TelecallerLeadProfileView.swift
//  Kinematic CRM
//
//  Phase 3 — the shared, cross-linked lead profile a telecaller lands on when
//  they tap a lead in "My Calls". It answers "who is this and what have we
//  already done with them, across every campaign?" before the rep dials.
//
//  It renders:
//    • a header — name / phone / current status / current campaign chip;
//    • an "Engaged campaigns" row — a chip per campaign the customer has been
//      worked under = { lead's campaign } ∪ { each call's campaign }, where a
//      call's campaign = metadata.campaign ?? the lead's campaign. When that
//      set holds more than one campaign, a "Multiple campaigns" flag shows —
//      the cross-linking the phase is about (one customer, many campaigns);
//    • the full call history — every type=="call" activity on the lead, newest
//      first, each with its derived campaign label, disposition (outcome),
//      date (completed_at), a humanised feedback summary from custom_fields,
//      and remarks (body);
//    • a "Log Call" button that opens the EXISTING TelecallerLogCallSheet for
//      this lead — the form is reused verbatim, never duplicated.
//
//  This is a read-only operational view (like the My Calls worklist row), not
//  a lead CREATE/EDIT/DETAIL form, so — consistent with the existing
//  telecaller worklist — its header is not a field-override render site.
//

import SwiftUI

struct TelecallerLeadProfileView: View {
    let lead: Lead
    /// Called after a call is logged from here, so the presenting My Calls
    /// list can refresh (a logged call may have moved the lead's status).
    var onLogged: () -> Void

    @State private var activities: [Activity] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogCall = false

    /// The lead's own campaign, from its `campaign` custom field.
    private var leadCampaign: LeadCampaign { LeadCampaign.of(lead) }

    /// The lead's `type=="call"` activities, newest first.
    private var callHistory: [Activity] {
        activities
            .filter { ($0.type ?? "").lowercased() == "call" }
            .sorted { sortDate($0) > sortDate($1) }
    }

    /// A single call's campaign: its `metadata.campaign` when present
    /// (imported calls), otherwise the lead's campaign.
    private func campaign(of call: Activity) -> LeadCampaign {
        if let raw = call.metadataCampaign { return LeadCampaign.lenient(raw) }
        return leadCampaign
    }

    /// The set of campaigns this customer has been worked under, in switcher
    /// order: { lead's campaign } ∪ { each call's campaign }.
    private var engagedCampaigns: [LeadCampaign] {
        var set: Set<LeadCampaign> = [leadCampaign]
        for c in callHistory { set.insert(campaign(of: c)) }
        return LeadCampaign.allCases.filter { set.contains($0) }
    }

    /// True when the customer has been engaged under more than one campaign.
    private var isMultiCampaign: Bool { engagedCampaigns.count > 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                engagedCampaignsCard
                logCallButton
                callHistoryCard
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("Lead Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showLogCall) {
            NavigationStack {
                TelecallerLogCallSheet(lead: lead) {
                    // Refresh this profile's history and bubble up to My Calls.
                    Task { await load() }
                    onLogged()
                }
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Brand.red.opacity(0.12)).frame(width: 52, height: 52)
                    Text(initials)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(Brand.red)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(lead.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(uiColor: .label))
                    if let p = lead.phone, !p.isEmpty {
                        Text(p).font(.system(size: 14)).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                if let s = lead.status, !s.isEmpty {
                    tagChip(text: s.replacingOccurrences(of: "_", with: " ").capitalized,
                            filled: true)
                }
                tagChip(text: leadCampaign.shortLabel, filled: false)
            }

            if let p = lead.phone, !p.isEmpty {
                CallButton(phone: p,
                           prefillSubject: "Call with \(lead.displayName)",
                           onCallInitiated: {},
                           compact: false)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: Engaged campaigns

    private var engagedCampaignsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ENGAGED CAMPAIGNS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                if isMultiCampaign {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Multiple campaigns")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Brand.red)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(engagedCampaigns) { c in
                        tagChip(text: c.shortLabel, filled: false)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: Log Call

    private var logCallButton: some View {
        Button {
            showLogCall = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "phone.arrow.up.right.fill")
                Text("Log Call").font(.system(size: 16, weight: .bold))
                Spacer()
            }
            .padding(.vertical, 14)
            .background(Brand.red)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: Call history

    private var callHistoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CALL HISTORY")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            if isLoading && activities.isEmpty {
                ProgressView().tint(Brand.red).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if let err = errorMessage, activities.isEmpty {
                VStack(spacing: 8) {
                    Text("Couldn't load call history")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(uiColor: .label))
                    Text(err).font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Brand.red)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if callHistory.isEmpty {
                Text("No calls logged yet.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(callHistory) { call in
                        callRow(call)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func callRow(_ call: Activity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                tagChip(text: campaign(of: call).shortLabel, filled: false)
                Spacer()
                if let when = callDate(call) {
                    Text(when).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            if let outcome = call.outcome?.trimmingCharacters(in: .whitespacesAndNewlines),
               !outcome.isEmpty {
                Text(outcome)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(uiColor: .label))
            }
            if let summary = feedbackSummary(call) {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let remarks = call.remarksText {
                Text(remarks)
                    .font(.system(size: 13))
                    .foregroundColor(Color(uiColor: .label).opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemBackground)))
    }

    // MARK: Pieces

    private func tagChip(text: String, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(filled ? Brand.red : Brand.red.opacity(0.12))
            .foregroundColor(filled ? .white : Brand.red)
            .clipShape(Capsule())
    }

    private var initials: String {
        let f = (lead.firstName ?? "").prefix(1)
        let l = (lead.lastName ?? "").prefix(1)
        let s = "\(f)\(l)".uppercased()
        if !s.isEmpty { return s }
        if let c = lead.displayName.first { return String(c).uppercased() }
        return "L"
    }

    // MARK: Data

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            activities = try await CRMService.shared.leadActivities(id: lead.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Humanised one-line summary of a call's `custom_fields` campaign
    /// feedback: "Digigold Explained: Yes - Enrolled · App Rating: 5". Scalar
    /// values only; empty values and non-scalar (array/object) fields are
    /// skipped. nil when there's nothing to show.
    private func feedbackSummary(_ call: Activity) -> String? {
        guard let cf = call.customFields, !cf.isEmpty else { return nil }
        let parts: [String] = cf.keys.sorted().compactMap { key in
            guard let raw = cf[key]?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            return "\(humanizeKey(key)): \(humanizeValue(raw))"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func humanizeKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func humanizeValue(_ value: String) -> String {
        switch value.lowercased() {
        case "true": return "Yes"
        case "false": return "No"
        default: return value
        }
    }

    /// Display date for a call row — completed_at preferred, else created_at.
    private func callDate(_ call: Activity) -> String? {
        guard let iso = call.completedAt ?? call.createdAt, !iso.isEmpty else { return nil }
        guard let date = Self.parseISO(iso) else { return iso }
        return Self.displayFormatter.string(from: date)
    }

    /// Sort key for newest-first ordering — the call's best timestamp, or the
    /// distant past so undated rows sink.
    private func sortDate(_ call: Activity) -> Date {
        let iso = call.completedAt ?? call.createdAt ?? call.updatedAt
        return iso.flatMap { Self.parseISO($0) } ?? .distantPast
    }

    /// Lenient ISO-8601 parse (with and without fractional seconds) — mirrors
    /// LeadDetailView's helper.
    private static func parseISO(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
