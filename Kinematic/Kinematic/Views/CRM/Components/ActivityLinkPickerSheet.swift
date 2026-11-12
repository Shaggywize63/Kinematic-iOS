import SwiftUI

// The "Linked entity" record pickers of the activity edit sheet. Leads reuse the composer's
// `LeadSearchPickerSheet` and accounts the `SparkAccountPickerSheet`; contacts and deals get the same
// searchable-list sheet. Picking a row calls `onPick(id, name)` and dismisses.

struct ActivityLinkPickerSheet: View {
    let type: ActivityLinkType
    let onPick: (_ id: String, _ name: String) -> Void

    var body: some View {
        switch type {
        case .lead:
            LeadSearchPickerSheet { lead in onPick(lead.id, lead.displayName) }
        case .account:
            SparkAccountPickerSheet { account in onPick(account.id, account.name) }
        case .contact:
            ContactLinkPickerSheet { contact in onPick(contact.id, contact.displayName) }
        case .deal:
            DealLinkPickerSheet { deal in onPick(deal.id, deal.name) }
        }
    }
}

/// Searchable contact list (server-side `?q=`).
struct ContactLinkPickerSheet: View {
    let onPick: (Contact) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var contacts: [Contact] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List(contacts) { contact in
                Button {
                    onPick(contact)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName).foregroundColor(.primary)
                        if let sub = subtitle(contact) {
                            Text(sub).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if loading {
                    ProgressView()
                } else if contacts.isEmpty {
                    Text("No contacts found").font(.caption).foregroundColor(.secondary)
                }
            }
            .searchable(text: $search, prompt: "Search contacts")
            .navigationTitle("Select contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: search) { await load() }
        }
    }

    private func subtitle(_ contact: Contact) -> String? {
        let parts = [contact.accountName, contact.phone, contact.email]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func load() async {
        // Light debounce: a newer keystroke cancels this task (task(id:)) during the sleep.
        if !search.isEmpty {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
        }
        loading = true
        defer { loading = false }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        contacts = (try? await CRMService.shared.listContacts(search: q.isEmpty ? nil : q)) ?? []
    }
}

/// Searchable deal list. The deals endpoint has no search, so the list is loaded once and filtered by name here.
struct DealLinkPickerSheet: View {
    let onPick: (Deal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var deals: [Deal] = []
    @State private var loading = false

    private var shown: [Deal] {
        ActivityLinkEditing.filter(deals, query: search) { $0.name }
    }

    var body: some View {
        NavigationStack {
            List(shown) { deal in
                Button {
                    onPick(deal)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deal.name).foregroundColor(.primary)
                        if let stage = deal.stageName, !stage.isEmpty {
                            Text(stage).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if loading {
                    ProgressView()
                } else if shown.isEmpty {
                    Text("No deals found").font(.caption).foregroundColor(.secondary)
                }
            }
            .searchable(text: $search, prompt: "Search deals")
            .navigationTitle("Select deal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                loading = true
                defer { loading = false }
                deals = (try? await CRMService.shared.listDeals()) ?? []
            }
        }
    }
}

/// Fetches the display name of a linked record when the activity row did not carry it.
enum ActivityLinkLookup {
    static func name(for link: ActivityLink) async -> String? {
        let api = CRMService.shared
        switch link.type {
        case .lead:
            return (try? await api.getLead(id: link.id))?.displayName
        case .contact:
            return (try? await api.getContact(id: link.id))?.displayName
        case .deal:
            return (try? await api.getDeal(id: link.id))?.name
        case .account:
            return (try? await api.getAccount(id: link.id))?.name
        }
    }
}
