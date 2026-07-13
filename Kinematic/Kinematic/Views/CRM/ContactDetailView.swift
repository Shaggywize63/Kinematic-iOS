import SwiftUI

struct ContactDetailView: View {
    @State var contact: Contact
    @State private var editing = false
    @State private var deals: [Deal] = []
    @State private var activities: [Activity] = []
    @State private var linkedAccount: CRMAccount?
    @State private var isLoadingRelations = false
    @State private var loggingActivity = false
    @State private var composerInitialType: String = "call"
    @State private var composerInitialSubject: String = ""
    /// Set after a tap-to-call POSTs the minimal call row. The composer
    /// that opens after will PATCH this same id instead of creating a
    /// duplicate; cancelling leaves the minimal record on the timeline.
    @State private var pendingCallActivityId: String?

    private let api = CRMService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                if contact.isB2c == true { customer360Card; customerProfileCard }
                if let e = contact.email { detailRow("Email", value: e, icon: "envelope.fill", color: Brand.red) }
                if let p = contact.phone {
                    phoneRow(label: "Phone", value: p, icon: "phone.fill")
                }
                if let m = contact.mobile {
                    phoneRow(label: "Mobile", value: m, icon: "iphone")
                }
                if contact.isB2c != true, let dept = contact.department {
                    detailRow("Department", value: dept, icon: "building.2.fill", color: Brand.red)
                }
                linkedAccountSection
                dealsSection
                activitiesSection
            }
            .padding()
        }
        .navigationTitle("Contact")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true }.tint(Brand.red) } }
        .sheet(isPresented: $editing) {
            ContactEditView(contact: contact) { updated in contact = updated; Task { await loadRelations() } }
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
        .task { await loadRelations() }
        .refreshable { await loadRelations() }
        // Tell KINI which record is on screen so the chat answers in context.
        .onAppear {
            KiniContextHolder.shared.set(
                screen: "contact_detail",
                recordType: "contact",
                recordId: contact.id
            )
        }
    }

    // MARK: - Phone row with tap-to-call

    private func phoneRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(Brand.red).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(.gray)
                Text(value).font(.system(size: 14))
            }
            Spacer()
            CallButton(
                phone: value,
                prefillSubject: "Call with \(contact.displayName)",
                onCallInitiated: {
                    let subject = "Call with \(contact.displayName)"
                    composerInitialType = "call"
                    composerInitialSubject = subject
                    Task { await startCallActivity(subject: subject) }
                    loggingActivity = true
                }
            )
            WhatsAppButton(phone: value, prefillText: "Hi \(contact.firstName ?? ""), ", compact: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: - Relation sections

    private var dealsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("DEALS", count: deals.count)
            if deals.isEmpty {
                emptyRow("No deals linked", icon: "briefcase")
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
                ForEach(activities.prefix(10)) { a in ActivityTimelineItem(activity: a) }
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

    private func emptyRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.gray.opacity(0.5))
            Text(text).font(.caption).foregroundColor(.gray)
            Spacer()
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
    }

    // MARK: - Activity logging

    /// Tap-to-call entry: POST a minimal call row right away so the
    /// timeline reflects the call. Stash the id so the composer save
    /// PATCHes the same row.
    private func startCallActivity(subject: String) async {
        let body: [String: Any] = [
            "type": "call",
            "subject": subject,
            "contact_id": contact.id,
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
        // Tap-to-call save → PATCH the already-created minimal row.
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
            "contact_id": contact.id,
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

    /// Composer dismissed without save. If there's a pending call row,
    /// flush the captured duration onto it. Otherwise no-op.
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

    private func loadRelations() async {
        isLoadingRelations = true
        defer { isLoadingRelations = false }
        async let d = (try? api.contactDeals(id: contact.id)) ?? []
        async let a = (try? api.contactActivities(id: contact.id)) ?? []
        // Parent account: only fetched when the contact actually links to
        // one. B2C contacts and unlinked B2B contacts skip the round trip.
        async let acct: CRMAccount? = {
            guard let aid = contact.accountId, !aid.isEmpty else { return nil }
            return try? await api.getAccount(id: aid)
        }()
        deals = await d
        activities = await a
        linkedAccount = await acct
    }

    /// Card that surfaces the contact's parent account with a NavigationLink
    /// to AccountDetailView. Hidden entirely for unlinked / B2C contacts so
    /// the section doesn't visually weigh down their detail page.
    @ViewBuilder
    private var linkedAccountSection: some View {
        if let account = linkedAccount {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("ACCOUNT", count: 1)
                NavigationLink(destination: AccountDetailView(account: account)) {
                    HStack(spacing: 12) {
                        Image(systemName: "building.2.fill")
                            .foregroundColor(Brand.red)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(uiColor: .label))
                            if let industry = account.industry, !industry.isEmpty {
                                Text(industry)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Header + customer cards (unchanged from main)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(contact.displayName).font(.system(size: 24, weight: .black))
                Spacer()
                if contact.isB2c == true { badge("CUSTOMER", color: Brand.red) } else { badge("B2B", color: Brand.red) }
                if let tier = contact.loyaltyTier { badge(tier.uppercased(), color: Brand.red) }
            }
            if contact.isB2c != true, let t = contact.title { Text(t).foregroundColor(.secondary) }
            if contact.isB2c == true, let addr = contact.fullAddress { Text(addr).font(.caption).foregroundColor(.secondary) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var customer360Card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CUSTOMER 360").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(Brand.red)
            HStack(spacing: 10) {
                stat("Lifetime Value", value: CurrencyFormatter.formatINR(contact.lifetimeValue))
                stat("Total Orders", value: "\(contact.totalOrders ?? 0)")
            }
            if let last = contact.lastPurchaseAt { Text("Last purchase: \(last)").font(.caption).foregroundColor(.secondary) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Brand.red.opacity(0.06)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.red.opacity(0.18), lineWidth: 1)))
    }

    private var customerProfileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CUSTOMER PROFILE").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(Brand.red)
            if let dob = contact.dateOfBirth { profileRow("Date of Birth", value: dob) }
            if let g = contact.gender { profileRow("Gender", value: g.replacingOccurrences(of: "_", with: " ").capitalized) }
            if let pcm = contact.preferredContactMethod { profileRow("Preferred Channel", value: pcm.capitalized) }
            if let cs = contact.customerSince { profileRow("Customer Since", value: cs) }
            if let r = contact.referralSource { profileRow("Referral", value: r) }
            profileRow("Marketing Consent", value: (contact.marketingConsent ?? false) ? "Yes" : "No")
            profileRow("WhatsApp Consent", value: (contact.whatsappConsent ?? false) ? "Yes" : "No")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundColor(.gray)
            Text(value).font(.system(size: 18, weight: .black))
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .tertiarySystemBackground)))
    }

    private func profileRow(_ label: String, value: String) -> some View {
        // Flexible label column (caps at 130pt) + wrapping value so long
        // values and large Dynamic Type don't clip on small phones.
        HStack(alignment: .top, spacing: 10) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundColor(.gray)
                .frame(maxWidth: 130, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(value).font(.system(size: 13)).foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .heavy)).padding(.horizontal, 6).padding(.vertical, 2).background(color).foregroundColor(.white).cornerRadius(4)
    }

    private func detailRow(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) { Text(label).font(.caption).foregroundColor(.gray); Text(value).font(.system(size: 14)) }
            Spacer()
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }
}
