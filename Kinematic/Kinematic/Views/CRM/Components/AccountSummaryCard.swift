import SwiftUI

struct AccountSummaryCard: View {
    let account: CRMAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundColor(.blue)
                Text(account.name)
                    .font(.headline)
                Spacer()
                if let industry = account.industry {
                    Text(industry.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }
            HStack(spacing: 16) {
                if let employees = account.employees {
                    Label("\(employees)", systemImage: "person.3.fill")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let rev = account.annualRevenue {
                    Label(formatCurrency(rev), systemImage: "dollarsign.circle.fill")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if let site = account.website {
                Text(site).font(.caption2).foregroundColor(.blue).lineLimit(1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}
