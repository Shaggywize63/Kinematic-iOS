import SwiftUI

struct DealDetailView: View {
    let dealId: String
    @State var initialDeal: Deal?
    @State private var winProb: WinProbability?
    @State private var nextAction: NextBestAction?
    @State private var aiBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let d = initialDeal {
                    headerCard(d)
                    HStack(alignment: .top, spacing: 16) {
                        if let wp = winProb {
                            WinProbabilityGauge(probability: wp.probability, label: wp.band?.uppercased())
                                .frame(maxWidth: .infinity)
                        } else {
                            VStack {
                                Text("AI win prob.").font(.caption).foregroundColor(.gray)
                                Button { Task { await loadWinProb() } } label: {
                                    Text("Compute").font(.caption).bold()
                                }
                            }
                            .frame(maxWidth: .infinity).padding()
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
                        }
                    }
                    if let nba = nextAction {
                        NextBestActionCard(action: nba) { }
                    } else {
                        Button {
                            Task { await loadNextAction() }
                        } label: {
                            HStack {
                                if aiBusy { ProgressView().tint(.white) }
                                else { Image(systemName: "sparkles") }
                                Text("Suggest next action")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                } else {
                    ProgressView().padding()
                }
            }
            .padding()
        }
        .navigationTitle(initialDeal?.name ?? "Deal")
        .task {
            if initialDeal == nil {
                initialDeal = try? await CRMService.shared.getDeal(id: dealId)
            }
        }
    }

    private func headerCard(_ d: Deal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(d.name).font(.system(size: 20, weight: .black))
            HStack {
                Image(systemName: "dollarsign.circle.fill").foregroundColor(.green)
                Text(formattedAmount(d)).font(.headline).foregroundColor(.green)
                Spacer()
                if let stage = d.stageName {
                    Text(stage.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.15))
                        .foregroundColor(.indigo)
                        .cornerRadius(4)
                }
            }
            if let close = d.expectedCloseDate?.prefix(10) {
                Label("Closes \(close)", systemImage: "calendar").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func formattedAmount(_ d: Deal) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = d.currency ?? "USD"
        return f.string(from: NSNumber(value: d.amount ?? 0)) ?? "$\(d.amount ?? 0)"
    }

    private func loadWinProb() async {
        aiBusy = true; defer { aiBusy = false }
        winProb = try? await CRMService.shared.aiWinProbability(dealId: dealId)
    }

    private func loadNextAction() async {
        aiBusy = true; defer { aiBusy = false }
        nextAction = try? await CRMService.shared.aiNextBestAction(dealId: dealId)
    }
}
