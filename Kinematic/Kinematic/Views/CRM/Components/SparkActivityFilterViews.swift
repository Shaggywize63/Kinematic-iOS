import SwiftUI

// Spark & Ray Activities list filters: an ACCOUNT filter (searchable account picker) and a USER filter (people
// from the assignable-users source), each with a clear option. Both feed the list call
// (`?account_id=` / `?owner_id=`, owner = owner OR assignee OR co-assignee) and reload on change.
// Shown ONLY for the Spark & Ray client (`SparkJourney.isActive`).

struct SparkActivityFilterBar: View {
    @ObservedObject var vm: ActivitiesViewModel

    @State private var showAccountPicker = false
    @State private var showUserPicker = false

    init(vm: ActivitiesViewModel) {
        self.vm = vm
    }

    private var accountActive: Bool { vm.accountFilterId != nil }
    private var userActive: Bool { ActivityQuery.ownerParam(vm.ownerFilter) != nil }

    var body: some View {
        HStack(spacing: 8) {
            chip(title: vm.accountFilterLabel ?? "Account", icon: "building.2", active: accountActive) {
                showAccountPicker = true
            }
            if accountActive {
                clearButton(label: "Clear account filter") { Task { await vm.setAccountFilter(nil) } }
            }
            chip(title: vm.userFilterTitle, icon: "person.crop.circle", active: userActive) {
                showUserPicker = true
            }
            if userActive {
                clearButton(label: "Clear user filter") { Task { await vm.setUserFilter(nil) } }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
        .sheet(isPresented: $showAccountPicker) {
            SparkAccountPickerSheet { account in
                Task { await vm.setAccountFilter(account) }
            }
        }
        .sheet(isPresented: $showUserPicker) {
            SparkUserFilterSheet(users: vm.owners, selectedId: ActivityQuery.ownerParam(vm.ownerFilter)) { id in
                Task { await vm.setUserFilter(id) }
            }
        }
    }

    private func chip(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemBackground))
                .foregroundColor(active ? Brand.red : .gray)
                .cornerRadius(8)
                .frame(maxWidth: 170)
        }
    }

    private func clearButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
        }
        .accessibilityLabel(label)
    }
}

/// Searchable list of people for the Activities User filter. "Everyone" clears the filter.
struct SparkUserFilterSheet: View {
    let users: [AssignableUser]
    let selectedId: String?
    /// The picked user id, or nil for "Everyone".
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    init(users: [AssignableUser], selectedId: String?, onPick: @escaping (String?) -> Void) {
        self.users = users
        self.selectedId = selectedId
        self.onPick = onPick
    }

    private var shown: [AssignableUser] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter { $0.displayName.lowercased().contains(q) || ($0.email ?? "").lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onPick(nil)
                    dismiss()
                } label: {
                    row("Everyone", selected: selectedId == nil)
                }
                ForEach(shown) { user in
                    Button {
                        onPick(user.id)
                        dismiss()
                    } label: {
                        row(user.displayName, selected: selectedId == user.id)
                    }
                }
            }
            .overlay {
                if users.isEmpty {
                    Text("No people available").font(.caption).foregroundColor(.secondary)
                }
            }
            .searchable(text: $search, prompt: "Search people")
            .navigationTitle("Filter by user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func row(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundColor(.primary)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundColor(Brand.red) }
        }
    }
}
