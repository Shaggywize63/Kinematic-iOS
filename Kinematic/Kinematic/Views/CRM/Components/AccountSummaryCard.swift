import SwiftUI

struct AccountSummaryCard: View {
    let account: CRMAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundColor(Brand.red)
                Text(account.name)
                    .font(.headline)
                Spacer()
                if let industry = account.industry {
                    Text(industry.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Brand.red.opacity(0.15))
                        .foregroundColor(Brand.red)
                        .cornerRadius(4)
                }
            }
            HStack(spacing: 16) {
                if let employees = account.employees {
                    Label("\(employees)", systemImage: "person.3.fill")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let rev = account.annualRevenue {
                    Label(CurrencyFormatter.formatINR(rev), systemImage: "indianrupeesign.circle.fill")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if let site = account.website {
                Text(site).font(.caption2).foregroundColor(Brand.red).lineLimit(1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

}
