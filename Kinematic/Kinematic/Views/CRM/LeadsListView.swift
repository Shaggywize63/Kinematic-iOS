import SwiftUI

struct LeadsListView: View {
    @StateObject var vm = LeadsViewModel()
    @State private var showCreate = false
    @State private var showImport = false
    @State private var showDateFilter = false
    @State private var confirmBulkDelete = false
    @State private var bulkResultToast: String?

    let statusOptions = ["all", "new", "contacted", "qualified", "unqualified", "converted"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Search leads…", text: $vm.search)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                if vm.dateFrom != nil || vm.dateTo != nil {
                    Button { vm.dateFrom = nil; vm.dateTo = nil; Task { await vm.refresh() } } label: {
                        Image(systemName: "calendar.badge.minus").foregroundColor(Brand.red)
                    }
                }
                Button { showDateFilter = true } label: {
                    Image(systemName: "calendar")
                        .foregroundColor(vm.dateFrom != nil || vm.dateTo != nil ? Brand.red : .secondary)
                }
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(statusOptions, id: \.self) { s in
                        Button {
                            vm.statusFilter = s
                            Task { await vm.refresh() }
                        } label: {
                            Text(s.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(vm.statusFilter == s ? Brand.red : Color(uiColor: .secondarySystemBackground))
                                .foregroundColor(vm.statusFilter == s ? .white : .secondary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.isLoading && vm.leads.isEmpty {
                        ProgressView().tint(Brand.red).padding(.top, 40)
                    } else if let err = vm.errorMessage, vm.leads.isEmpty {
                        // Surface fetch failures (most often 401 from a
                        // stale token) instead of falling through to the
                        // "No leads yet" empty state — the silent failure
                        // was the bug Hemanth ran into when his session
                        // expired and the list looked empty.
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(Brand.red)
                            Text("Couldn't load leads")
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
                            Text("If this keeps happening, sign out and back in.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(.top, 60)
                    } else if vm.filtered.isEmpty {
                        // Real empty state — auth + fetch worked, the
                        // client just has no leads matching the current
                        // filters.
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(Brand.red.opacity(0.5))
                            Text(vm.statusFilter == "all" && vm.search.isEmpty
                                 ? "No leads yet."
                                 : "No leads match your filters.")
                                .foregroundColor(.secondary)
                            Button("Create lead") { showCreate = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Brand.red)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(vm.filtered) { lead in
                            if vm.isMultiSelect {
                                // In multi-select mode the row becomes a
                                // tap-to-toggle target instead of a
                                // navigation link. Wrapping in a Button
                                // keeps the accessibility/hit-target
                                // behaviour consistent with the
                                // NavigationLink path.
                                Button {
                                    vm.toggleSelection(lead.id)
                                } label: {
                                    LeadRow(lead: lead, selected: vm.selectedIds.contains(lead.id))
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(destination: LeadDetailView(leadId: lead.id)) {
                                    LeadRow(lead: lead)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, vm.isMultiSelect && !vm.selectedIds.isEmpty ? 100 : 40)
            }
            .refreshable { await vm.refresh() }

            if vm.isMultiSelect && !vm.selectedIds.isEmpty {
                bulkActionBar
            }
        }
        .navigationTitle(vm.isMultiSelect
                         ? (vm.selectedIds.isEmpty
                            ? "Select leads"
                            : "\(vm.selectedIds.count) selected")
                         : "Leads")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.isMultiSelect {
                    Button("Done") { vm.exitMultiSelect() }
                        .fontWeight(.semibold)
                } else {
                    Menu {
                        Button { showCreate = true } label: { Label("New lead", systemImage: "plus") }
                        Button { showImport = true } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }
                        Button { vm.enterMultiSelect() } label: { Label("Select…", systemImage: "checkmark.circle") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            if vm.isMultiSelect {
                ToolbarItem(placement: .topBarLeading) {
                    Button(vm.selectedIds.count == vm.filtered.count ? "Clear" : "Select all") {
                        if vm.selectedIds.count == vm.filtered.count { vm.selectedIds.removeAll() }
                        else { vm.selectAllVisible() }
                    }
                    .font(.system(size: 14))
                }
            }
        }
        .alert("Delete \(vm.selectedIds.count) lead\(vm.selectedIds.count == 1 ? "" : "s")?", isPresented: $confirmBulkDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    await vm.bulkDeleteSelected()
                    if let res = vm.bulkResult {
                        bulkResultToast = res.failed == 0
                            ? "Deleted \(res.ok) lead\(res.ok == 1 ? "" : "s")"
                            : "Deleted \(res.ok), \(res.failed) failed"
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This soft-deletes them — rows can be restored from the database if needed.")
        }
        .overlay(alignment: .top) {
            if let msg = bulkResultToast {
                Text(msg)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(uiColor: .systemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.red, lineWidth: 1))
                    .cornerRadius(10)
                    .shadow(radius: 8)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation { bulkResultToast = nil }
                    }
            }
        }
        .sheet(isPresented: $showCreate) {
            LeadCreateView { body in
                await vm.create(body: body)
            }
        }
        .sheet(isPresented: $showImport) {
            LeadImportView()
        }
        .sheet(isPresented: $showDateFilter) {
            DateRangeFilterSheet(from: $vm.dateFrom, to: $vm.dateTo, label: "Created date") {
                Task { await vm.refresh() }
            }
        }
        .task { await vm.refresh() }
        .onChange(of: vm.search) { _, _ in
            Task { await vm.refresh() }
        }
    }

    /// Bottom action bar visible only while the user is in multi-select
    /// mode AND has at least one lead selected. Mirrors the dashboard's
    /// selection toolbar (`dashboard/crm/leads/page.tsx` L347-355).
    private var bulkActionBar: some View {
        HStack(spacing: 10) {
            Text("\(vm.selectedIds.count) selected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Button {
                confirmBulkDelete = true
            } label: {
                HStack(spacing: 6) {
                    if vm.bulkBusy {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "trash")
                    }
                    Text(vm.bulkBusy ? "Deleting…" : "Delete \(vm.selectedIds.count)")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Brand.red.opacity(vm.bulkBusy ? 0.6 : 1))
                .cornerRadius(10)
            }
            .disabled(vm.bulkBusy)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(.secondary.opacity(0.3)), alignment: .top)
    }
}
