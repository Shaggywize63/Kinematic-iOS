import SwiftUI

struct DealDetailView: View {
    let dealId: String
    // Observe reachability so the NBA-card refresh button auto-enables
    // when the device comes back online — without this the button stays
    // greyed out until some other state change re-renders the view.
    @ObservedObject private var reachability = NetworkReachability.shared
    @State var initialDeal: Deal?
    @State private var winProb: WinProbability?
    @State private var nextAction: NextBestAction?
    /// Wall-clock time the currently-shown `nextAction` was fetched. Set
    /// from the on-disk cache on appear (no API call) or from a successful
    /// Refresh tap. `nil` keeps the card in its cold/empty state.
    @State private var nbaFetchedAt: Date?
    @State private var aiBusy = false
    @State private var editing = false
    @State private var stages: [Stage] = []
    /// Primary contact loaded lazily from `Deal.contactId` so the deal
    /// header can offer tap-to-call without a separate navigation.
    @State private var primaryContact: Contact?
    @State private var loggingActivity = false
    @State private var composerInitialType: String = "call"
    @State private var composerInitialSubject: String = ""
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
                    nbaSection
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
            ) { type, subject, description in
                await logActivity(type: type, subject: subject, description: description)
            }
        }
        .task {
            // Cache-first NBA hydration. We deliberately do NOT call
            // aiNextBestAction on appear anymore — the rep must tap Refresh
            // to spend an AI roundtrip. Cold cache renders the empty state.
            if let cached = CRMScoreNBACache.shared.loadNBA(dealId: dealId) {
                nextAction = cached.action
                nbaFetchedAt = cached.fetchedAt
            }
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

    /// Next-best-action card. Cache-first: hydrated from
    /// CRMScoreNBACache.loadNBA(dealId:) in `.task` so the card renders the
    /// last computed suggestion without hitting `/api/v1/crm/ai/next-best-action`.
    /// Refresh icon (warm) or Compute Now button (cold) is the only path
    /// that triggers a live AI call. Reads reactivity-aware
    /// `reachability.isOnline` so the button auto-enables on reconnect.
    @ViewBuilder
    private var nbaSection: some View {
        if let nba = nextAction {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    nbaRefreshButton
                }
                NextBestActionCard(action: nba) { }
                if let fetched = nbaFetchedAt {
                    Text("Last computed \(Self.relTimeFmt.localizedString(for: fetched, relativeTo: Date()))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(reachability.isOnline ? "No suggested action yet." : "Connect to compute.")
                    .font(.caption).foregroundColor(.secondary)
                Button { Task { await loadNextAction() } } label: {
                    HStack {
                        if aiBusy { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                        Text("Suggest next action")
                    }
                    .font(.system(size: 13, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(reachability.isOnline ? Color.purple : Color.gray)
                    .foregroundColor(.white).cornerRadius(10)
                }
                .disabled(!reachability.isOnline || aiBusy)
            }
        }
    }

    private var nbaRefreshButton: some View {
        let online = reachability.isOnline
        return Button { Task { await loadNextAction() } } label: {
            if aiBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(online ? .purple : .gray)
            }
        }
        .disabled(aiBusy || !online)
    }

    private static let relTimeFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

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
    /// Explicit user-driven NBA recompute. Called from the card's refresh
    /// icon (warm cache) or Compute Now button (cold cache). Persists the
    /// result so the next detail-screen open is free.
    private func loadNextAction() async {
        aiBusy = true; defer { aiBusy = false }
        if let fresh = try? await CRMService.shared.aiNextBestAction(dealId: dealId) {
            let now = Date()
            nextAction = fresh
            nbaFetchedAt = now
            CRMScoreNBACache.shared.saveNBA(dealId: dealId, action: fresh, fetchedAt: now)
        }
    }
}
