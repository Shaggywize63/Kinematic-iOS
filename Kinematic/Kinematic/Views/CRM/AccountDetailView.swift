import SwiftUI

struct AccountDetailView: View {
    @State var account: CRMAccount
    @State private var editing = false
    @State private var contacts: [Contact] = []
    @State private var deals: [Deal] = []
    @State private var activities: [Activity] = []
    @State private var isLoadingRelations = false
    @State private var loggingActivity = false
    @State private var composerInitialType: String = "call"
    @State private var composerInitialSubject: String = ""
    /// Set after a tap-to-call POSTs the minimal call row. Composer save
    /// PATCHes this id; cancel leaves the minimal record on the timeline.
    @State private var pendingCallActivityId: String?
    /// Server message from a failed Mark complete / Reopen; drives the alert.
    @State private var completionError: String?
    // Spark & Ray account journey: assign a task / activity and start a deal from the account.
    @State private var assigningActivity = false
    @State private var creatingDeal = false
    /// Server message from a failed assign-task / New deal; drives the alert.
    @State private var journeyError: String?
    /// Spark & Ray: the "Add contact" sheet (contact create, pre-linked to this account).
    @State private var addingContact = false
    /// Built-in field overrides — gate the Spark "Outcome" row (hide / relabel).
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()

    private let api = CRMService.shared

    /// Spark & Ray only — same client gate as the Spark lead forms. Everything the account
    /// journey adds is behind this; other tenants see the screen exactly as before.
    private var isSpark: Bool { SparkJourney.isActive }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AccountSummaryCard(account: account)

                Text("DETAILS").font(.system(size: 11, weight: .black)).tracking(1).foregroundColor(.gray)
                if let addr = account.billingAddress { detailRow("Billing", addr, icon: "mappin.and.ellipse", color: Brand.red) }
                if let phone = account.phone, !phone.isEmpty { phoneRow(phone) }
                websiteAndOutcomeRows

                if isSpark { sparkActionsRow }

                contactsSection
                if isSpark {
                    SparkAccountUpdatesSection(accountId: account.id, contacts: contacts)
                }
                dealsSection
                activitiesSection
            }
            .padding()
        }
        .navigationTitle(account.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true }.tint(Brand.red) } }
        .sheet(isPresented: $editing) {
            AccountEditView(account: account) { updated in
                account = updated
                Task { await loadRelations() }
            }
        }
        .sheet(
            isPresented: $loggingActivity,
            onDismiss: { Task { await autoLogCallIfNeeded() } }
        ) {
            ActivityComposeView(
                initialType: composerInitialType,
                initialSubject: composerInitialSubject
            ) { type, subject, description, imageUrl, when, _, customFields in
                await logActivity(
                    type: type, subject: subject, description: description,
                    imageUrl: imageUrl, completedAt: when,
                    customFields: customFields
                )
            }
        }
        // Spark & Ray: assign a task / activity to one or more people from this account.
        .sheet(isPresented: $assigningActivity) {
            ActivityComposeView(initialType: "task", scheduled: true) { type, subject, description, imageUrl, when, _, customFields in
                // Only reached if the Spark extras are unavailable; still creates the activity.
                let result = ActivityComposeResult(
                    type: type, subject: subject, description: description, imageUrl: imageUrl,
                    when: when, leadId: nil, customFields: customFields, extras: SparkActivityExtras()
                )
                do { try await createAssignedActivity(result) } catch { journeyError = error.localizedDescription }
            }
            .sparkSubmit { result in
                try await createAssignedActivity(result)
            }
        }
        // Spark & Ray: New deal for this customer (account preselected).
        .sheet(isPresented: $creatingDeal) {
            DealCreateView(prefillAccount: account) { body in
                do {
                    let created = try await api.createDeal(body)
                    deals.insert(created, at: 0)
                } catch {
                    journeyError = error.localizedDescription
                }
            }
            .sparkSubmit { body in
                let created = try await api.createDeal(body)
                deals.insert(created, at: 0)
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { journeyError != nil },
            set: { if !$0 { journeyError = nil } }
        )) {
            Button("OK", role: .cancel) { journeyError = nil }
        } message: { Text(journeyError ?? "") }
        .task {
            async let overrides: Void = loadOverrides()
            await loadRelations()
            await overrides
        }
        .refreshable { await loadRelations() }
        .activityCompletionAlert($completionError)
        // Tell KINI which record is on screen so the chat answers in context.
        .onAppear {
            KiniContextHolder.shared.set(
                screen: "account_detail",
                recordType: "account",
                recordId: account.id
            )
        }
    }

    // MARK: - Phone row with tap-to-call

    private func phoneRow(_ phone: String) -> some View {
        HStack {
            Image(systemName: "phone.fill").foregroundColor(Brand.red).frame(width: 24)
            VStack(alignment: .leading) {
                Text("Phone").font(.caption).foregroundColor(.gray)
                Text(phone).font(.system(size: 14))
            }
            Spacer()
            CallButton(
                phone: phone,
                prefillSubject: "Call with \(account.name)",
                onCallInitiated: {
                    let subject = "Call with \(account.name)"
                    composerInitialType = "call"
                    composerInitialSubject = subject
                    Task { await startCallActivity(subject: subject) }
                    loggingActivity = true
                }
            )
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: - Spark & Ray actions

    /// "Assign task / activity" + "New deal" for this customer.
    private var sparkActionsRow: some View {
        HStack(spacing: 10) {
            Button {
                assigningActivity = true
            } label: {
                Label("Assign task / activity", systemImage: "person.badge.plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Brand.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            Button {
                creatingDeal = true
            } label: {
                Label("New deal", systemImage: "briefcase.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Brand.red.opacity(0.10))
                    .foregroundColor(Brand.red)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.red.opacity(0.30), lineWidth: 1))
                    .cornerRadius(10)
            }
        }
    }

    /// Create an open, assigned activity on this account from the composer's result.
    /// Throws so the composer can show the server's message (e.g. a bad form serial) inline.
    private func createAssignedActivity(_ result: ActivityComposeResult) async throws {
        let body = SparkActivityBody.createBody(result, scheduled: true, links: ["account_id": account.id])
        let created = try await api.createActivity(body, spark: result.extras)
        activities.insert(created, at: 0)
    }

    // MARK: - Relation sections

    /// Website, then (Spark) the Outcome — one builder so the detail's main stack keeps its child count.
    @ViewBuilder
    private var websiteAndOutcomeRows: some View {
        if let site = account.website { detailRow("Website", site, icon: "globe", color: Brand.red) }
        outcomeRow
    }

    /// Spark & Ray: the account's Outcome (Spark only, once the overrides loaded, not hidden, and set).
    @ViewBuilder
    private var outcomeRow: some View {
        if isSpark, fieldOverrides.didLoad, !fieldOverrides.isHidden(entity: "account", "outcome"),
           let outcome = account.outcome?.trimmingCharacters(in: .whitespacesAndNewlines), !outcome.isEmpty {
            detailRow(
                fieldOverrides.labelFor(entity: "account", "outcome", "Outcome"),
                outcome, icon: "target", color: Brand.red
            )
        }
    }

    /// "Add contact" (Spark only): opens the contact form with this account already chosen.
    @ViewBuilder
    private var addContactButton: some View {
        if isSpark {
            Button {
                addingContact = true
            } label: {
                Label("Add contact", systemImage: "person.badge.plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Brand.red.opacity(0.10))
                    .foregroundColor(Brand.red)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.red.opacity(0.30), lineWidth: 1))
                    .cornerRadius(10)
            }
        }
    }

    private var addContactSheet: some View {
        ContactCreateView(prefillAccount: account) { body in
            do {
                let created = try await api.createContact(body)
                contacts.insert(created, at: 0)
            } catch {
                journeyError = error.localizedDescription
            }
        }
    }

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("CONTACTS", count: contacts.count)
            addContactButton
            if contacts.isEmpty {
                emptyRow("No contacts linked", icon: "person.2")
            } else {
                ForEach(contacts) { c in
                    NavigationLink(destination: ContactDetailView(contact: c)) {
                        contactRow(c)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $addingContact) { addContactSheet }
    }

    private var dealsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("DEALS", count: deals.count)
            if deals.isEmpty {
                emptyRow("No deals on this account", icon: "briefcase")
            } else {
                ForEach(deals) { d in
                    NavigationLink(destination: DealDetailView(dealId: d.id, initialDeal: d)) {
                        DealCard(deal: d)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("ACTIVITY", count: activities.count)
            if activities.isEmpty {
                emptyRow("No activity logged", icon: "clock")
            } else {
                ForEach(activities.prefix(10)) { a in
                    ActivityTimelineItem(
                        activity: a,
                        onSetComplete: { act, done in await setActivityCompleted(act, completed: done) }
                    )
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11, weight: .black)).tracking(1).foregroundColor(Brand.red)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.secondary)
                    .clipShape(Capsule())
            }
            Spacer()
            if isLoadingRelations { ProgressView().controlSize(.mini) }
        }
    }

    private func contactRow(_ c: Contact) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Brand.red.opacity(0.15)).frame(width: 36, height: 36)
                Text(initials(c)).font(.system(size: 12, weight: .black)).foregroundColor(Brand.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.displayName).font(.system(size: 14, weight: .semibold)).foregroundColor(Color(uiColor: .label))
                if let role = c.title { Text(role).font(.caption).foregroundColor(.secondary) }
                else if let e = c.email { Text(e).font(.caption).foregroundColor(.secondary) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func detailRow(_ label: String, _ value: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(color).frame(width: 24)
            VStack(alignment: .leading) {
                Text(label).font(.caption).foregroundColor(.gray)
                Text(value).font(.system(size: 14))
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func emptyRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.gray.opacity(0.5))
            Text(text).font(.caption).foregroundColor(.gray)
            Spacer()
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
    }

    private func initials(_ c: Contact) -> String {
        let s = "\(c.firstName?.prefix(1) ?? "")\(c.lastName?.prefix(1) ?? "")".uppercased()
        return s.isEmpty ? "C" : s
    }

    // MARK: - Activity logging

    private func startCallActivity(subject: String) async {
        let body: [String: Any] = [
            "type": "call",
            "subject": subject,
            "account_id": account.id,
            "completed_at": ISO8601DateFormatter().string(from: Date()),
            "status": "completed",
        ]
        if let created = try? await api.createActivity(body) {
            activities.insert(created, at: 0)
            pendingCallActivityId = created.id
        }
    }

    private func logActivity(type: String, subject: String, description: String, imageUrl: String?, completedAt: Date, customFields: [String: Any] = [:]) async {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if type == "call", let id = pendingCallActivityId {
            var patch: [String: Any] = ["subject": trimmed]
            let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDesc.isEmpty { patch["description"] = trimmedDesc }
            if let imageUrl, !imageUrl.isEmpty { patch["image_url"] = imageUrl }
            patch["completed_at"] = ISO8601DateFormatter().string(from: completedAt)
            if let duration = CallObserver.shared.consumeDuration(), duration > 0 {
                patch["duration_seconds"] = duration
            }
            // Backend PATCH merges custom_fields over the stored blob.
            if !customFields.isEmpty { patch["custom_fields"] = customFields }
            if let updated = try? await api.updateActivity(id: id, body: patch),
               let i = activities.firstIndex(where: { $0.id == id }) {
                activities[i] = updated
            }
            pendingCallActivityId = nil
            return
        }
        var body: [String: Any] = [
            "type": type,
            "subject": trimmed,
            "account_id": account.id,
        ]
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDesc.isEmpty { body["description"] = trimmedDesc }
        if let imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
        if type != "task" {
            body["completed_at"] = ISO8601DateFormatter().string(from: completedAt)
            body["status"] = "completed"
        } else {
            body["due_at"] = ISO8601DateFormatter().string(from: completedAt)
        }
        if type == "call", let duration = CallObserver.shared.consumeDuration(), duration > 0 {
            body["duration_seconds"] = duration
        }
        // Admin-defined activity custom fields; omitted when empty.
        if !customFields.isEmpty { body["custom_fields"] = customFields }
        if let created = try? await api.createActivity(body) {
            activities.insert(created, at: 0)
        }
    }

    /// "Mark complete" (`completed == true`) / "Reopen" (`false`) from an
    /// activity card. PATCHes status + completed_at, then flips that row in
    /// place from the response (keeping its lead / contact / deal names, which
    /// the PATCH response doesn't carry). On failure the row is left as it was
    /// and the server's message is shown in an alert.
    private func setActivityCompleted(_ activity: Activity, completed: Bool) async {
        do {
            let updated = try await api.setActivityCompleted(id: activity.id, completed: completed)
            activities.applyCompletion(updated)
        } catch {
            completionError = error.localizedDescription
        }
    }

    private func autoLogCallIfNeeded() async {
        guard let id = pendingCallActivityId else { return }
        defer { pendingCallActivityId = nil }
        guard let duration = CallObserver.shared.consumeDuration(), duration > 0 else { return }
        if let updated = try? await api.updateActivity(id: id, body: ["duration_seconds": duration]),
           let i = activities.firstIndex(where: { $0.id == id }) {
            activities[i] = updated
        }
    }

    // MARK: - Loading

    /// The admin's field overrides — only the Spark "Outcome" row reads them.
    private func loadOverrides() async {
        guard isSpark else { return }
        await fieldOverrides.load()
    }

    private func loadRelations() async {
        isLoadingRelations = true
        defer { isLoadingRelations = false }
        async let c = (try? api.accountContacts(id: account.id)) ?? []
        async let d = (try? api.accountDeals(id: account.id)) ?? []
        async let a = (try? api.accountActivities(id: account.id)) ?? []
        contacts = await c
        deals = await d
        activities = await a
    }
}
