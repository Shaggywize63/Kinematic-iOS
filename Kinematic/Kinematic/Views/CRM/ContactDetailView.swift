import SwiftUI

struct ContactDetailView: View {
    let contact: Contact

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                if contact.isB2c == true {
                    customer360Card
                    customerProfileCard
                }

                if let e = contact.email {
                    detailRow("Email", value: e, icon: "envelope.fill", color: .blue)
                }
                if let p = contact.phone {
                    HStack(spacing: 12) {
                        Image(systemName: "phone.fill").foregroundColor(.green).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Phone").font(.caption).foregroundColor(.gray)
                            Text(p).font(.system(size: 14))
                        }
                        Spacer()
                        WhatsAppButton(phone: p, prefillText: "Hi \(contact.firstName ?? ""), ", compact: true)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
                }
                if let m = contact.mobile {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone").foregroundColor(.indigo).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mobile").font(.caption).foregroundColor(.gray)
                            Text(m).font(.system(size: 14))
                        }
                        Spacer()
                        WhatsAppButton(phone: m, prefillText: "Hi \(contact.firstName ?? ""), ", compact: true)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
                }
                if contact.isB2c != true, let dept = contact.department {
                    detailRow("Department", value: dept, icon: "building.2.fill", color: .orange)
                }
            }
            .padding()
        }
        .navigationTitle("Contact")
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(contact.displayName).font(.system(size: 24, weight: .black))
                Spacer()
                if contact.isB2c == true {
                    badge("CUSTOMER", color: .purple)
                } else {
                    badge("B2B", color: .blue)
                }
                if let tier = contact.loyaltyTier {
                    badge(tier.uppercased(), color: .orange)
                }
            }
            if contact.isB2c != true, let t = contact.title {
                Text(t).foregroundColor(.secondary)
            }
            if contact.isB2c == true, let addr = contact.fullAddress {
                Text(addr).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var customer360Card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CUSTOMER 360").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(.purple)
            HStack(spacing: 10) {
                stat("Lifetime Value", value: CurrencyFormatter.formatINR(contact.lifetimeValue))
                stat("Total Orders", value: "\(contact.totalOrders ?? 0)")
            }
            if let last = contact.lastPurchaseAt {
                Text("Last purchase: \(last)").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.purple.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.purple.opacity(0.18), lineWidth: 1))
        )
    }

    private var customerProfileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CUSTOMER PROFILE").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(.purple)
            if let dob = contact.dateOfBirth { profileRow("Date of Birth", value: dob) }
            if let g = contact.gender { profileRow("Gender", value: g.replacingOccurrences(of: "_", with: " ").capitalized) }
            if let pcm = contact.preferredContactMethod { profileRow("Preferred Channel", value: pcm.capitalized) }
            if let cs = contact.customerSince { profileRow("Customer Since", value: cs) }
            if let r = contact.referralSource { profileRow("Referral", value: r) }
            profileRow("Marketing Consent", value: (contact.marketingConsent ?? false) ? "Yes" : "No")
            profileRow("WhatsApp Consent", value: (contact.whatsappConsent ?? false) ? "Yes" : "No")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundColor(.gray)
            Text(value).font(.system(size: 18, weight: .black))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .tertiarySystemBackground)))
    }

    private func profileRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundColor(.gray)
                .frame(width: 130, alignment: .leading)
            Text(value).font(.system(size: 13)).foregroundColor(.primary)
            Spacer()
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(4)
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
