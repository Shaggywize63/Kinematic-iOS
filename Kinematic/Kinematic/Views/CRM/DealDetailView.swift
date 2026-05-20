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
    /// detail can offer tap-to-call without a separate navigation hop.
    @State private var primaryContact: Contact?
    @State private var loggingActivity = false
    @State private var composerInitialType: String = "call"
    @State private var composerInitialSubject: String = ""
    /// Set after a tap-to-call POSTs the minimal call row. Composer save
    /// PATCHes this id; cancel leaves the minimal record on the timeline.
    @State private var pendingCallActivityId: String?
    @State private var closingDeal = false
    @State private var reopening = false
    @State private var reopenError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let d = initialDeal {
                    headerCard(d)
                    closeActions(d)
                    if let contact = primaryContact, let phone = contact.phone ?? contact.mobile, !phone.isEmpty {
                        primaryContactCard(contact: contact, phone: phone, dealName: d.name)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        if let wp = winProb {
                            WinProbabilityGauge(
                                probability: wp.probability,
                                label: wp.band?.uppercased(),
                                reasoning: wp.reasoning,
                                breakdown: wp.breakdown
                            )
                            .frame(maxWidth: .infinity)
                        } else {
                            VStack(spacing: 6) {
                                Text("Powered by KINI AI")
                                    .font(.system(size: 9, weight: .black))
                                    .tracking(1)
                                    .foregroundColor(Brand.red)
                                Text("Win probability").font(.caption).foregroundColor(.gray)
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
                            .background(Brand.red).foregroundColor(.white).cornerRadius(10)
                        }
                    }
                    DealHistorySection(dealId: dealId)
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
        .sheet(isPresented: $closingDeal) {
            if let d = initialDeal {
                DealCloseView(deal: d) { updated in initialDeal = updated }
            }
        }
        .alert("Re-open failed",
               isPresented: .init(get: { reopenError != nil },
                                  set: { if !$0 { reopenError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(reopenError ?? "") }
        .sheet(
            isPresented: $loggingActivity,
            onDismiss: { Task { await autoLogCallIfNeeded() } }
        ) {
            ActivityComposeView(
                initialType: composerInitialType,
                initialSubject: composerInitialSubject
            ) { type, subject, description, imageUrl, when in
                await logActivity(
                    type: type, subject: subject, description: description,
                    imageUrl: imageUrl, completedAt: when
                )
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
                Circle().fill(Brand.red.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "person.fill").foregroundColor(Brand.red)
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
                    let subject = "Call about \(dealName)"
                    composerInitialType = "call"
                    composerInitialSubject = subject
                    Task { await startCallActivity(subject: subject) }
                    loggingActivity = true
                }
            )
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: - Activity logging

    private func startCallActivity(subject: String) async {
        let body: [String: Any] = [
            "type": "call",
            "subject": subject,
            "deal_id": dealId,
            "completed_at": ISO8601DateFormatter().string(from: Date()),
            "status": "completed",
        ]
        if let created = try? await CRMService.shared.createActivity(body) {
            pendingCallActivityId = created.id
        }
    }

    private func logActivity(type: String, subject: String, description: String, imageUrl: String?, completedAt: Date) async {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if type == "call", let id = pendingCallActivityId {
            var patch: [String: Any] = ["subject": trimmed]
            let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDesc.isEmpty { patch["description"] = trimmedDesc }
            if let imageUrl, !imageUrl.isEmpty { patch["image_url"] = imageUrl }
            patch["completed_at"] = ISO8601DateFormatter().string(from: completedAt)
            if let duration = CallObserver.shared.consumeDuration(), duration > 0 {
                patch["duration_seconds"] = duration
            }
            _ = try? await CRMService.shared.updateActivity(id: id, body: patch)
            pendingCallActivityId = nil
            return
        }
        var body: [String: Any] = [
            "type": type,
            "subject": trimmed,
            "deal_id": dealId,
        ]
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDesc.isEmpty { body["description"] = trimmedDesc }
        if let imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
        if type != "task" {
            body["completed_at"] = ISO8601DateFormatter().string(from: completedAt)
            body["status"] = "completed"
        } else {
            body["due_at"] = ISO8601DateFormatter().string(from: completedAt)
        }
        if type == "call", let duration = CallObserver.shared.consumeDuration(), duration > 0 {
            body["duration_seconds"] = duration
        }
        _ = try? await CRMService.shared.createActivity(body)
    }

    private func autoLogCallIfNeeded() async {
        guard let id = pendingCallActivityId else { return }
        defer { pendingCallActivityId = nil }
        guard let duration = CallObserver.shared.consumeDuration(), duration > 0 else { return }
        _ = try? await CRMService.shared.updateActivity(id: id, body: ["duration_seconds": duration])
    }

    // MARK: - Close / re-open

    /// Status banner + close/re-open controls. Closing routes through the
    /// dedicated /win and /lose endpoints (see DealCloseView) so the
    /// backend writes a crm_deal_history row; re-opening is a plain PATCH
    /// status:"open" because we don't need a separate audit endpoint for it.
    @ViewBuilder
    private func closeActions(_ d: Deal) -> some View {
        let status = (d.status ?? "open").lowercased()
        switch status {
        case "won":
            statusBanner(text: "Closed as WON", system: "checkmark.seal.fill", color: .green)
            reopenButton
        case "lost":
            VStack(alignment: .leading, spacing: 6) {
                statusBanner(text: "Closed as LOST", system: "xmark.seal.fill", color: .red)
                if let reason = d.lostReason, !reason.isEmpty {
                    Text("Reason: \(reason)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            reopenButton
        default:
            Button { closingDeal = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "flag.checkered")
                    Text("Close deal").font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.green))
                .foregroundColor(.white)
            }
        }
    }

    private func statusBanner(text: String, system: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system)
            Text(text).font(.system(size: 13, weight: .black)).tracking(0.5)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundColor(color)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.4), lineWidth: 1))
    }

    private var reopenButton: some View {
        Button { Task { await reopenDeal() } } label: {
            HStack(spacing: 8) {
                if reopening { ProgressView().controlSize(.small) }
                else { Image(systemName: "arrow.uturn.backward") }
                Text(reopening ? "Re-opening…" : "Re-open deal")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary, lineWidth: 1))
        }
        .foregroundColor(.primary)
        .disabled(reopening)
    }

    private func reopenDeal() async {
        guard let id = initialDeal?.id else { return }
        reopening = true
        defer { reopening = false }
        do {
            let updated = try await CRMService.shared.patchDeal(id: id, body: ["status": "open"])
            initialDeal = updated
        } catch {
            reopenError = error.localizedDescription
        }
    }

    private func headerCard(_ d: Deal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(d.name).font(.system(size: 20, weight: .black))
            HStack {
                Image(systemName: "indianrupeesign.circle.fill").foregroundColor(Brand.red)
                Text(formattedAmount(d)).font(.headline).foregroundColor(Brand.red)
                Spacer()
                if let stage = d.stageName {
                    Text(stage.uppercased()).font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Brand.red.opacity(0.15)).foregroundColor(Brand.red).cornerRadius(4)
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
        // Kinematic is INR-only — always render ₹ regardless of the
        // currency stamp on the row (legacy data sometimes carries "USD"
        // from imports and we never want $ to appear in-app).
        CurrencyFormatter.formatINR(d.amount)
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
