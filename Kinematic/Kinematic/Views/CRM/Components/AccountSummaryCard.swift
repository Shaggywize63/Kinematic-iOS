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
