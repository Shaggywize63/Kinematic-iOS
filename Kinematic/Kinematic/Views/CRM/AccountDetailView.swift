import SwiftUI

struct AccountDetailView: View {
    @State var account: CRMAccount
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AccountSummaryCard(account: account)
                Text("DETAILS").font(.system(size: 11, weight: .black)).tracking(1).foregroundColor(.gray)
                if let addr = account.billingAddress { detailRow("Billing", addr, icon: "mappin.and.ellipse", color: .red) }
                if let phone = account.phone { detailRow("Phone", phone, icon: "phone.fill", color: .green) }
                if let site = account.website { detailRow("Website", site, icon: "globe", color: .blue) }
            }
            .padding()
        }
        .navigationTitle(account.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
        .sheet(isPresented: $editing) {
            AccountEditView(account: account) { updated in account = updated }
        }
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
}
