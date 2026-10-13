//
//  TelecallerCallsView.swift
//  Kinematic CRM
//
//  The telecaller's "My Calls" tab — the leads an admin assigned to them. The
//  backend already force-scopes GET /api/v1/crm/leads to the telecaller's own
//  owner_id, so this is just the standard own-scoped list (reusing
//  LeadsViewModel) rendered as a lean call worklist: each row shows name /
//  phone / status with a one-tap Call button, and tapping the row opens the
//  streamlined Log Call sheet.
//

import SwiftUI

struct TelecallerCallsView: View {
    @StateObject private var vm = LeadsViewModel()
    /// The lead whose Log Call sheet is open; nil hides it.
    @State private var loggingLead: Lead?
    /// Skip the initial re-appear refresh (the .task below covers first load).
    @State private var hasAppearedOnce = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if vm.total > 0 {
                HStack {
                    Text(vm.leads.count >= vm.total
                         ? "\(vm.total) lead\(vm.total == 1 ? "" : "s")"
                         : "Showing \(vm.leads.count) of \(vm.total) leads")
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
                            TelecallerLeadRow(lead: lead) { loggingLead = lead }
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
        .sheet(item: $loggingLead) { lead in
            NavigationStack {
                TelecallerLogCallSheet(lead: lead) {
                    Task { await vm.refresh() }
                }
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "phone.badge.checkmark")
                .font(.system(size: 40))
                .foregroundColor(Brand.red.opacity(0.5))
            Text(vm.search.isEmpty ? "No leads assigned to you yet."
                                   : "No leads match your search.")
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
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

/// A compact call-worklist row: identity + status on the left, a Call pill and
/// a "Log" affordance on the right. The whole row (outside the Call button)
/// opens the Log Call sheet.
private struct TelecallerLeadRow: View {
    let lead: Lead
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onLog) {
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
