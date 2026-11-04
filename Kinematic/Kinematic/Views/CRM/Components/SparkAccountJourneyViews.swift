import SwiftUI

// Spark & Ray account-journey UI building blocks:
//   - SparkAccountUpdatesSection   Recent updates on an account (contact picker + composer + list)
//   - SparkAssigneePickerSheet     multi-select of org users, first selected = Primary
//   - SparkProductPickerSheet      multi-select of the product catalogue ("Product interested")
//   - SparkAccountPickerSheet      searchable customer (account) picker for the deal form
//   - SparkActivityMeta            assignees / product chips / form serial on an activity row
//
// Every host shows these ONLY for the Spark & Ray client (`SparkJourney.isActive`); the pure
// logic behind them lives in `Models/CRM/SparkJourney.swift`.

// MARK: - Small chip

struct SparkChip: View {
    let icon: String?
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            }
            Text(text).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundColor(tint)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - Account "Recent updates"

/// Recent updates on a Spark account: a composer (contact-person picker + text + Post) above the
/// newest-first list (contact, author, relative time). Mirrors the lead detail's Recent Updates.
struct SparkAccountUpdatesSection: View {
    let accountId: String
    /// The account's contacts, for the "contact person" picker.
    let contacts: [Contact]

    @State private var updates: [AccountUpdate] = []
    @State private var isLoading = false
    @State private var text = ""
    /// Picked contact id; nil = "No specific contact".
    @State private var contactId: String? = nil
    @State private var posting = false
    @State private var errorText: String? = nil
    @State private var pendingDeleteId: String? = nil

    private let api = CRMService.shared

    private var canPost: Bool {
        !posting && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isCRMAdmin: Bool {
        let sysRole = (Session.currentUser?.role ?? "").lowercased()
        return ["super_admin", "admin", "sub_admin"].contains(sysRole)
    }

    /// Author or admin may delete (mirrors the backend).
    private func canDelete(_ u: AccountUpdate) -> Bool {
        if isCRMAdmin { return true }
        guard let me = Session.currentUser?.id, let author = u.createdBy else { return false }
        return author == me
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("RECENT UPDATES")
                    .font(.system(size: 11, weight: .black)).tracking(1).foregroundColor(Brand.red)
                if !updates.isEmpty {
                    Text("\(updates.count)")
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.mini) }
            }

            composer

            if let errorText {
                Text(errorText).font(.caption).foregroundColor(Brand.red)
            }

            if updates.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "text.bubble").foregroundColor(.gray.opacity(0.5))
                    Text("No updates yet").font(.caption).foregroundColor(.gray)
                    Spacer()
                }
                .padding(.vertical, 6).padding(.horizontal, 4)
            } else {
                ForEach(updates) { u in
                    updateRow(u)
                }
            }
        }
        .task(id: accountId) { await load() }
        .confirmationDialog(
            "Delete this update? This cannot be undone.",
            isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteId {
                    pendingDeleteId = nil
                    Task { await delete(updateId: id) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteId = nil }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Contact person", selection: $contactId) {
                Text("No specific contact").tag(String?.none)
                ForEach(contacts) { c in
                    Text(c.displayName).tag(String?.some(c.id))
                }
            }
            .pickerStyle(.menu)
            .tint(Brand.red)

            HStack(spacing: 8) {
                TextField("Add an update…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await post() }
                } label: {
                    if posting {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill").foregroundColor(Brand.red)
                    }
                }
                .disabled(!canPost)
                .accessibilityLabel("Post update")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: Row

    private func updateRow(_ u: AccountUpdate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = u.contactName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                SparkChip(icon: "person.fill", text: name, tint: Brand.red)
            }
            Text(u.body).font(.system(size: 13)).foregroundColor(.primary)
            HStack(spacing: 6) {
                if let who = u.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !who.isEmpty {
                    Text(who).font(.caption2).foregroundColor(.secondary)
                }
                let when = SparkJourney.relativeTime(u.createdAt)
                if !when.isEmpty {
                    Text(when).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
        .contentShape(Rectangle())
        .contextMenu {
            if canDelete(u) {
                Button(role: .destructive) {
                    pendingDeleteId = u.id
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let rows = try? await api.listAccountUpdates(accountId: accountId) {
            updates = rows
        }
    }

    private func post() async {
        guard let payload = SparkJourney.updateBody(text: text, contactId: contactId),
              let body = payload["body"] as? String else { return }
        posting = true
        errorText = nil
        defer { posting = false }
        do {
            try await api.addAccountUpdate(accountId: accountId, body: body, contactId: contactId)
            text = ""
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(updateId: String) async {
        do {
            try await api.deleteAccountUpdate(accountId: accountId, updateId: updateId)
            updates.removeAll { $0.id == updateId }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Assignee multi-select

/// Multi-select of org users for an activity. Order is tap order and the first person is the
/// Primary assignee ("Make primary" moves someone to the front). Capped at the backend's 20.
struct SparkAssigneePickerSheet: View {
    let users: [AssignableUser]
    /// Names for already-assigned people who are not in `users` (e.g. when editing).
    let knownNames: [String: String]
    @Binding var selectedIds: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [AssignableUser] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter {
            $0.displayName.lowercased().contains(q) || ($0.email ?? "").lowercased().contains(q)
        }
    }

    private func name(for id: String) -> String {
        if let u = users.first(where: { $0.id == id }) { return u.displayName }
        return knownNames[id] ?? "User"
    }

    var body: some View {
        NavigationStack {
            List {
                if !selectedIds.isEmpty {
                    Section("Selected · first is Primary") {
                        ForEach(Array(selectedIds.enumerated()), id: \.element) { idx, id in
                            HStack(spacing: 8) {
                                Text(name(for: id))
                                if idx == 0 {
                                    Text("Primary")
                                        .font(.system(size: 10, weight: .black))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Brand.red.opacity(0.14))
                                        .foregroundColor(Brand.red)
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                if idx > 0 {
                                    Button("Make primary") {
                                        selectedIds = SparkJourney.makingPrimary(id, in: selectedIds)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                    .tint(Brand.red)
                                }
                                Button {
                                    selectedIds = SparkJourney.toggled(id, in: selectedIds)
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(name(for: id))")
                            }
                        }
                    }
                }
                Section("People") {
                    if users.isEmpty {
                        Text("No people available to assign.").font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(filtered) { user in
                        Button {
                            selectedIds = SparkJourney.toggled(user.id, in: selectedIds, limit: SparkJourney.maxAssignees)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName).foregroundColor(.primary)
                                    if let role = user.role, !role.isEmpty {
                                        Text(role.capitalized).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedIds.contains(user.id) {
                                    Image(systemName: "checkmark").foregroundColor(Brand.red)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search people")
            .navigationTitle("Assign to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Brand.red)
                }
            }
        }
    }
}

// MARK: - Product multi-select

/// Multi-select of the product catalogue — the activity's "Product interested".
struct SparkProductPickerSheet: View {
    let products: [Product]
    @Binding var selectedIds: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Product] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return products }
        return products.filter {
            $0.name.lowercased().contains(q) || ($0.sku ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if products.isEmpty {
                    Text("No products in the catalogue.").font(.caption).foregroundColor(.secondary)
                }
                ForEach(filtered) { p in
                    Button {
                        selectedIds = SparkJourney.toggled(p.id, in: selectedIds)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).foregroundColor(.primary)
                                if let sku = p.sku, !sku.isEmpty {
                                    Text(sku).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if selectedIds.contains(p.id) {
                                Image(systemName: "checkmark").foregroundColor(Brand.red)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search products")
            .navigationTitle("Product interested")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Brand.red)
                }
            }
        }
    }
}

// MARK: - Customer (account) picker

/// Searchable list of CRM accounts — the Spark deal form's Customer picker. Server-side search via
/// `?q=`; picking a row calls `onPick` and dismisses.
struct SparkAccountPickerSheet: View {
    let onPick: (CRMAccount) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var accounts: [CRMAccount] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List(accounts) { account in
                Button {
                    onPick(account)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name).foregroundColor(.primary)
                        if let industry = account.industry, !industry.isEmpty {
                            Text(industry).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if loading {
                    ProgressView()
                } else if accounts.isEmpty {
                    Text("No customers found").font(.caption).foregroundColor(.secondary)
                }
            }
            .searchable(text: $search, prompt: "Search customers")
            .navigationTitle("Select customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: search) { await load() }
        }
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
        accounts = (try? await CRMService.shared.listAccounts(search: q.isEmpty ? nil : q)) ?? []
    }
}

// MARK: - Activity row meta

/// Assignees (primary first), "Product interested" chips and the linked form serial for an
/// activity. Renders nothing for activities without them (every non-Spark activity).
struct SparkActivityMeta: View {
    let activity: Activity

    private var assigneeNames: [String] {
        (activity.assignees ?? []).map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var productNames: [String] {
        (activity.products ?? []).map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// "Asha (primary), Ravi" — the first assignee is the Primary.
    private var assigneeLine: String {
        var parts: [String] = []
        for (i, n) in assigneeNames.enumerated() {
            parts.append(i == 0 && assigneeNames.count > 1 ? "\(n) (primary)" : n)
        }
        return parts.joined(separator: ", ")
    }

    private var serial: String? {
        let s = (activity.formRefNo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    var hasContent: Bool {
        !assigneeNames.isEmpty || !productNames.isEmpty || serial != nil
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 6) {
                if !assigneeNames.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        // First name is the Primary assignee.
                        Text(assigneeLine)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !productNames.isEmpty || serial != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(productNames, id: \.self) { n in
                                SparkChip(icon: "shippingbox.fill", text: n, tint: Brand.red)
                            }
                            if let serial {
                                SparkChip(icon: "doc.text.fill", text: serial, tint: .blue)
                            }
                        }
                    }
                }
            }
        }
    }
}
