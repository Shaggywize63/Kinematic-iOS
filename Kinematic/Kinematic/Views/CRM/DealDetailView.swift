import SwiftUI

struct DealDetailView: View {
    let dealId: String
    @State var initialDeal: Deal?
    @State private var winProb: WinProbability?
    @State private var nextAction: NextBestAction?
    @State private var aiBusy = false
    @State private var editing = false
    @State private var stages: [Stage] = []
    /// Primary contact loaded lazily from `Deal.contactId` so the deal
    /// header can offer tap-to-call without a separate navigation.
    @State private var primaryContact: Contact?
    @State private var loggingActivity = false
    @State private var composerInitialType: String = "call"
    @State private var composerInitialSubject: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let d = initialDeal {
                    headerCard(d)
                    if let contact = primaryContact, let phone = contact.phone ?? contact.mobile, !phone.isEmpty {
                        primaryContactCard(contact: contact, phone: phone, dealName: d.name)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        if let wp = winProb {
                            WinProbabilityGauge(probability: wp.probability, label: wp.band?.uppercased())
                                .frame(maxWidth: .infinity)
                        } else {
                            VStack {
                                Text("AI win prob.").font(.caption).foregroundColor(.gray)
                                Button { Task { await loadWinProb() } } label: { Text("Compute").font(.caption).bold() }
                            }
                            .frame(maxWidth: .infinity).padding()
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
                        }
                    }
                    LineItemsCard(dealId: dealId)
                    if let nba = nextAction {
                        NextBestActionCard(action: nba) { }
                    } else {
                        Button { Task { await loadNextAction() } } label: {
                            HStack {
                                if aiBusy { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                                Text("Suggest next action")
                            }
                            .font(.system(size: 13, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.purple).foregroundColor(.white).cornerRadius(10)
                        }
                    }
                } else {
                    ProgressView().padding()
                }
            }
            .padding()
        }
        .navigationTitle(initialDeal?.name ?? "Deal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if initialDeal != nil { Button("Edit") { editing = true } }
            }
        }
        .sheet(isPresented: $editing) {
            if let d = initialDeal {
                DealEditView(deal: d, stages: stages) { updated in initialDeal = updated }
            }
        }
        .sheet(
            isPresented: $loggingActivity,
            onDismiss: { Task { await autoLogCallIfNeeded() } }
        ) {
            ActivityComposeView(
                initialType: composerInitialType,
                initialSubject: composerInitialSubject
            ) { type, subject, description in
                await logActivity(type: type, subject: subject, description: description)
            }
        }
        .task {
            if initialDeal == nil {
                initialDeal = try? await CRMService.shared.getDeal(id: dealId)
            }
            if let pid = initialDeal?.pipelineId {
                stages = (try? await CRMService.shared.listStages(pipelineId: pid)) ?? []
            }
            if let cid = initialDeal?.contactId, primaryContact == nil {
                primaryContact = try? await CRMService.shared.getContact(id: cid)
            }
        }
    }

    private func primaryContactCard(contact: Contact, phone: String, dealName: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.2)).frame(width: 40, height: 40)
                Image(systemName: "person.fill").foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName).font(.system(size: 14, weight: .bold))
                Text(phone).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            CallButton(
                phone: phone,
                prefillSubject: "Call about \(dealName)",
                onCallInitiated: {
                    composerInitialType = "call"
                    composerInitialSubject = "Call about \(dealName)"
                    loggingActivity = true
                }
            )
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    /// POST an activity bound to this deal. Used by the call composer.
    private func logActivity(type: String, subject: String, description: String) async {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var body: [String: Any] = [
            "type": type,
            "subject": trimmed,
            "description": description,
            "deal_id": dealId,
        ]
        if type != "task" {
            body["completed_at"] = ISO8601DateFormatter().string(from: Date())
            body["status"] = "completed"
        }
        if type == "call", let duration = CallObserver.shared.consumeDuration(), duration > 0 {
            body["duration_seconds"] = duration
        }
        _ = try? await CRMService.shared.createActivity(body)
    }

    /// Auto-log fallback for the cancel-after-dial case.
    private func autoLogCallIfNeeded() async {
        guard let duration = CallObserver.shared.consumeDuration(), duration > 0 else { return }
        let subject = composerInitialSubject.isEmpty ? "Call (auto-logged)" : composerInitialSubject
        let body: [String: Any] = [
            "type": "call",
            "subject": subject,
            "description": "",
            "deal_id": dealId,
            "completed_at": ISO8601DateFormatter().string(from: Date()),
            "status": "completed",
            "duration_seconds": duration,
        ]
        _ = try? await CRMService.shared.createActivity(body)
    }

    private func headerCard(_ d: Deal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(d.name).font(.system(size: 20, weight: .black))
            HStack {
                Image(systemName: "indianrupeesign.circle.fill").foregroundColor(.green)
                Text(formattedAmount(d)).font(.headline).foregroundColor(.green)
                Spacer()
                if let stage = d.stageName {
                    Text(stage.uppercased()).font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.15)).foregroundColor(.indigo).cornerRadius(4)
                }
            }
            if let close = d.expectedCloseDate?.prefix(10) {
                Label("Closes \(close)", systemImage: "calendar").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func formattedAmount(_ d: Deal) -> String {
        if (d.currency ?? "INR").uppercased() == "INR" { return CurrencyFormatter.formatINR(d.amount) }
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = d.currency ?? "USD"
        return f.string(from: NSNumber(value: d.amount ?? 0)) ?? "\(d.amount ?? 0)"
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
