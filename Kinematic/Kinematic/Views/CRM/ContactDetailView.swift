import SwiftUI

struct ContactDetailView: View {
    let contact: Contact

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(contact.displayName).font(.system(size: 24, weight: .black))
                    if let t = contact.title { Text(t).foregroundColor(.secondary) }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))

                if let e = contact.email {
                    detailRow("Email", value: e, icon: "envelope.fill", color: .blue)
                }
                if let p = contact.phone {
                    detailRow("Phone", value: p, icon: "phone.fill", color: .green)
                }
                if let m = contact.mobile {
                    detailRow("Mobile", value: m, icon: "iphone", color: .indigo)
                }
                if let dept = contact.department {
                    detailRow("Department", value: dept, icon: "building.2.fill", color: .orange)
                }
            }
            .padding()
        }
        .navigationTitle("Contact")
    }

    private func detailRow(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(.gray)
                Text(value).font(.system(size: 14))
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }
}
