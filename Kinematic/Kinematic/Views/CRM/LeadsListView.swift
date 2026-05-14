import SwiftUI

struct LeadsListView: View {
    @StateObject var vm = LeadsViewModel()
    @State private var showCreate = false
    @State private var showImport = false
    @State private var showDateFilter = false

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
                            NavigationLink(destination: LeadDetailView(leadId: lead.id)) {
                                LeadRow(lead: lead)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .refreshable { await vm.refresh() }
        }
        .navigationTitle("Leads")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showCreate = true } label: { Label("New lead", systemImage: "plus") }
                    Button { showImport = true } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }
                } label: {
                    Image(systemName: "ellipsis.circle")
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
}
