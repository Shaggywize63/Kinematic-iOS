import SwiftUI

struct StageColumn: View {
    let stage: Stage
    let deals: [Deal]
    let onMove: (Deal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(stage.name.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .tracking(1)
                    .foregroundColor(Color(uiColor: .label))
                Spacer()
                Text("\(deals.count)")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(deals) { d in
                    Button {
                        onMove(d)
                    } label: {
                        DealCard(deal: d)
                    }
                    .buttonStyle(.plain)
                }
                if deals.isEmpty {
                    Text("No deals")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.5))
        )
    }
}
