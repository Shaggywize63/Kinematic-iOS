import SwiftUI

/// Pick a salesperson, then open their sales & target drill-down. The list is
/// `/users?scope=assignable`, already scoped to the caller's hierarchy subtree
/// server-side (a manager sees their team, an admin everyone, a frontline rep
/// only themselves), so this surface needs no extra client gating.
struct SalespersonListView: View {
    @State private var users: [AssignableUser] = []
    @State private var loading = true
    @State private var query = ""

    private var shown: [AssignableUser] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter {
            $0.displayName.lowercased().contains(q) || ($0.email ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if loading && users.isEmpty {
                HStack { Spacer(); ProgressView().padding(.top, 40); Spacer() }
            } else if shown.isEmpty {
                Text(users.isEmpty ? "No salespeople to show." : "No match.")
                    .font(.callout).foregroundColor(.secondary).padding(.top, 40)
            } else {
                List {
                    ForEach(shown) { u in
                        NavigationLink(destination: SalespersonDetailView(userId: u.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.displayName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                let sub = [u.role, u.email].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                                if !sub.isEmpty {
                                    Text(sub).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $query, prompt: "Search salesperson")
        .navigationTitle("Salesperson Sales")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        users = await CRMService.shared.listAssignableUsers()
        loading = false
    }
}
