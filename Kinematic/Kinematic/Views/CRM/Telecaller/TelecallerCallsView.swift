//
//  TelecallerCallsView.swift
//  Kinematic CRM
//
//  The telecaller's "My Calls" tab — the leads an admin assigned to them. The
//  backend already force-scopes GET /api/v1/crm/leads to the telecaller's own
//  owner_id, so this is just the standard own-scoped list (reusing
//  LeadsViewModel) rendered as a lean call worklist.
//
//  Phase 3 upgrades the phase-2 campaign filter chips into a real SECTION
//  switcher — All / General / App & DigiGold / After-Sales. Changing section
//  does NOT client-filter a single loaded page; it sets `vm.campaign` (the
//  exact server `campaign` value, nil for All) and REFETCHES, so every section
//  paginates independently on the server and shows its own count. Search and
//  infinite scroll keep working within the active section because both ride
//  the same `fetchPage` (which now carries `?campaign=`).
//
//  Tapping a lead pushes a shared, cross-linked lead profile (name / phone /
//  status / campaign + engaged-campaigns + full call history) which hosts the
//  existing Log Call sheet.
//

import SwiftUI

struct TelecallerCallsView: View {
    @StateObject private var vm = LeadsViewModel()
    /// The active campaign section; nil = "All". Drives the server `campaign`
    /// param — NOT a client-side filter over the loaded page.
    @State private var section: LeadCampaign?
    /// Skip the initial re-appear refresh (the .task below covers first load).
    @State private var hasAppearedOnce = false

    /// The sections in switcher order: All, then every campaign.
    private let sections: [LeadCampaign?] = [nil, .general, .appDigiGold, .afterSales]

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            sectionBar

            if vm.total > 0 {
                HStack {
                    Text(countLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal).padding(.bottom, 4)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.isLoading && vm.leads.isEmpty {
                        ProgressView().tint(Brand.red).padding(.top, 40)
                    } else if let err = vm.errorMessage, vm.leads.isEmpty {
                        errorState(err)
                    } else if vm.leads.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.leads) { lead in
                            TelecallerLeadRow(lead: lead)
                                .onAppear {
                                    if lead.id == vm.leads.last?.id {
                                        Task { await vm.loadMoreIfNeeded() }
                                    }
                                }
                        }
                        if vm.isLoadingMore {
                            ProgressView().tint(Brand.red).padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .refreshable { await vm.refresh() }
        }
        .navigationTitle("My Calls")
        .navigationDestination(for: Lead.self) { lead in
            TelecallerLeadProfileView(lead: lead) {
                // A call logged from the profile may have moved the lead's
                // status — refresh the worklist so the row reflects it.
                Task { await vm.refresh() }
            }
        }
        .task { await vm.refresh() }
        .onChange(of: vm.search) { _, _ in vm.searchChanged() }
        .onAppear {
            if hasAppearedOnce {
                Task { await vm.refresh() }
            } else {
                hasAppearedOnce = true
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)
            TextField("Search your leads…", text: $vm.search)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// Prominent section switcher: All / General / App & DigiGold / After-Sales.
    /// Styled as top-tabs (bold + red underline on the selected section) with a
    /// hairline divider beneath, so it reads as a section switcher rather than
    /// a loose set of filter chips. Horizontally scrollable so the long
    /// "App & DigiGold" label never truncates on a phone.
    private var sectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, s in
                    sectionTab(title: s?.shortLabel ?? "All",
                               isSelected: section == s) { select(s) }
                }
            }
            .padding(.horizontal)
        }
        .overlay(alignment: .bottom) { Divider() }
        .padding(.bottom, 8)
    }

    private func sectionTab(title: String, isSelected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? Brand.red : .secondary)
                Rectangle()
                    .fill(isSelected ? Brand.red : Color.clear)
                    .frame(height: 2.5)
            }
        }
        .buttonStyle(.plain)
    }

    /// Switch section → set the server `campaign` param and refetch. A no-op
    /// when the section is unchanged.
    private func select(_ s: LeadCampaign?) {
        guard section != s else { return }
        section = s
        vm.campaign = s?.serverValue
        Task { await vm.refresh() }
    }

    /// The active section's lead count (server total for this campaign), with a
    /// partial-load hint while more pages remain.
    private var countLabel: String {
        vm.leads.count >= vm.total
            ? "\(vm.total) lead\(vm.total == 1 ? "" : "s")"
            : "Showing \(vm.leads.count) of \(vm.total) leads"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "phone.badge.checkmark")
                .font(.system(size: 40))
                .foregroundColor(Brand.red.opacity(0.5))
            Text(emptyStateMessage)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private var emptyStateMessage: String {
        if !vm.search.isEmpty { return "No leads match your search." }
        if let s = section { return "No \(s.shortLabel) leads." }
        return "No leads assigned to you yet."
    }

    private func errorState(_ err: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(Brand.red)
            Text("Couldn't load your calls")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(uiColor: .label))
            Text(err)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                Task { await vm.refresh() }
            } label: {
                Text("Retry")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Brand.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(.top, 60)
    }
}

/// A compact call-worklist row: identity + status on the left, a Call pill on
/// the right. The identity area is a NavigationLink that pushes the lead's
/// profile / call-history; the Call button stays independently tappable.
private struct TelecallerLeadRow: View {
    let lead: Lead

    private var campaign: LeadCampaign { LeadCampaign.of(lead) }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: lead) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Brand.red.opacity(0.12)).frame(width: 44, height: 44)
                        Text(initials)
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(Brand.red)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lead.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(uiColor: .label))
                            .lineLimit(1)
                        if let p = lead.phone, !p.isEmpty {
                            Text(p).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                        }
                        if let s = lead.status, !s.isEmpty {
                            Text(s.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Brand.red)
                        }
                        if campaign != .general {
                            Text(campaign.shortLabel)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Brand.red.opacity(0.12))
                                .foregroundColor(Brand.red)
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let p = lead.phone, !p.isEmpty {
                CallButton(phone: p,
                           prefillSubject: "Call with \(lead.displayName)",
                           onCallInitiated: {},
                           compact: false)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var initials: String {
        let f = (lead.firstName ?? "").prefix(1)
        let l = (lead.lastName ?? "").prefix(1)
        let s = "\(f)\(l)".uppercased()
        if !s.isEmpty { return s }
        if let c = lead.displayName.first { return String(c).uppercased() }
        return "L"
    }
}
