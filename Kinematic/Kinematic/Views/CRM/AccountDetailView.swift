import SwiftUI

struct AccountDetailView: View {
    @State var account: CRMAccount
    @State private var editing = false
    @State private var contacts: [Contact] = []
    @State private var deals: [Deal] = []
    @State private var activities: [Activity] = []
    @State private var isLoadingRelations = false

    private let api = CRMService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AccountSummaryCard(account: account)

                Text("DETAILS").font(.system(size: 11, weight: .black)).tracking(1).foregroundColor(.gray)
                if let addr = account.billingAddress { detailRow("Billing", addr, icon: "mappin.and.ellipse", color: .red) }
                if let phone = account.phone { detailRow("Phone", phone, icon: "phone.fill", color: .green) }
                if let site = account.website { detailRow("Website", site, icon: "globe", color: .blue) }

                contactsSection
                dealsSection
                activitiesSection
            }
            .padding()
        }
        .navigationTitle(account.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
        .sheet(isPresented: $editing) {
            AccountEditView(account: account) { updated in
                account = updated
                Task { await loadRelations() }
            }
        }
        .task { await loadRelations() }
        .refreshable { await loadRelations() }
    }

    // MARK: Sections

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("CONTACTS", count: contacts.count)
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
                ForEach(activities.prefix(10)) { a in ActivityTimelineItem(activity: a) }
            }
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11, weight: .black)).tracking(1).foregroundColor(.gray)
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
                Circle().fill(Color.orange.opacity(0.2)).frame(width: 36, height: 36)
                Text(initials(c)).font(.system(size: 12, weight: .black)).foregroundColor(.orange)
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

    // MARK: Loading

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
