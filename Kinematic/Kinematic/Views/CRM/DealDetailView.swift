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
    /// Bumped after a successful stage move or a freshly-logged activity
    /// so DealHistorySection re-fetches without needing the whole detail
    /// screen to reload.
    @State private var historyRefreshTick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let d = initialDeal {
                    // Stage stepper sits above everything — reps land on
                    // this screen looking for "what's the status, what
                    // changes next?" so it deserves first paint priority.
                    if !stages.isEmpty {
                        DealStageProgress(
                            deal: Binding(
                                get: { initialDeal ?? d },
                                set: { initialDeal = $0 }
                            ),
                            stages: stages,
                            onStageChanged: { historyRefreshTick &+= 1 }
                        )
                    }
                    headerCard(d)
                    closeActions(d)
                    quickActionsRow(d)
                    if let contact = primaryContact, let phone = contact.phone ?? contact.mobile, !phone.isEmpty {
                        primaryContactCard(contact: contact, phone: phone, dealName: d.name)
                    }
                    // Win Probability + Next Best Action are manager-tier
                    // surfaces. Champion FEs work the floor and don't act on
                    // these AI signals — matches the web gate on the deal
                    // page (`!isConsumerChampion`).
                    if !ClientFeatures.isConsumerChampion {
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
                    }
                    DealProductsCard(dealId: dealId)
                    CustomFieldsDetailCard(entity: "deal", customFields: initialDeal?.customFields)
                    if !ClientFeatures.isConsumerChampion {
                        if let nba = nextAction {
                            NextBestActionCard(action: nba) {
                                // Wire "Schedule it" → activity composer prefilled
                                // from the NBA recommendation. Maps the NBA action
                                // verb to an activity type, drops the displayable
                                // label as the subject, and presents the same
                                // composer the in-deal quick actions use so the
                                // saved row lands on the deal timeline.
                                composerInitialType = activityTypeFor(nba.action)
                                composerInitialSubject = NextBestActionCard.displayAction(nba.action)
                                loggingActivity = true
                            }
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
                    }
                    DealHistorySection(dealId: dealId, refreshTick: historyRefreshTick)
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
                DealCloseView(deal: d) { updated in
                    initialDeal = updated
                    historyRefreshTick &+= 1
                }
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
            ) { type, subject, description, imageUrl, when, _, customFields in
                await logActivity(
                    type: type, subject: subject, description: description,
                    imageUrl: imageUrl, completedAt: when,
                    customFields: customFields
                )
                historyRefreshTick &+= 1
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
        // Tell KINI which record is on screen so the chat answers in context.
        .onAppear {
            KiniContextHolder.shared.set(
                screen: "deal_detail",
                recordType: "deal",
                recordId: dealId
            )
        }
    }

    // MARK: - Quick action row (Add Activity + future buttons)

    /// Compact action bar that sits between the close controls and the
    /// AI/insight stack. The "+ Add Activity" button mirrors the web
    /// dashboard's quick-log composer on the deal detail page.
    @ViewBuilder
    private func quickActionsRow(_ d: Deal) -> some View {
        HStack(spacing: 8) {
            Button {
                composerInitialType = "note"
                composerInitialSubject = ""
                pendingCallActivityId = nil
                loggingActivity = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Add Activity")
                        .font(.system(size: 13, weight: .black))
                        .tracking(0.3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundColor(.white)
                .background(Capsule().fill(Brand.red))
                .shadow(color: Brand.red.opacity(0.30), radius: 6, x: 0, y: 2)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: loggingActivity)
            Spacer()
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

    private func logActivity(type: String, subject: String, description: String, imageUrl: String?, completedAt: Date, customFields: [String: Any] = [:]) async {
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
            // Backend PATCH merges custom_fields over the stored blob.
            if !customFields.isEmpty { patch["custom_fields"] = customFields }
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
        // Admin-defined activity custom fields; omitted when empty.
        if !customFields.isEmpty { body["custom_fields"] = customFields }
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
            historyRefreshTick &+= 1
        } catch {
            reopenError = error.localizedDescription
        }
    }

    private func headerCard(_ d: Deal) -> some View {
        // Hero card — Amount + Weight as the two dominant numbers, then
        // stage / close date below. Mirrors the web deal-detail hero so
        // reps see the ₹ and the tonnage at a glance.
        let kg = derivedWeightKg(d)
        return VStack(alignment: .leading, spacing: 12) {
            Text(d.name).font(.system(size: 20, weight: .black))
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AMOUNT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.8)
                    Text(formattedAmount(d))
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.primary)
                }
                if kg > 0 {
                    Divider().frame(height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WEIGHT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(0.8)
                        Text(formatKg(kg))
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundColor(.primary)
                    }
                }
                Spacer()
            }
            HStack {
                if let stage = d.stageName {
                    Text(stage.uppercased()).font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Brand.red.opacity(0.15)).foregroundColor(Brand.red).cornerRadius(4)
                }
                if let close = d.expectedCloseDate?.prefix(10) {
                    Label("Closes \(close)", systemImage: "calendar").font(.caption).foregroundColor(.secondary)
                }
            }
            // Server-stamped context — dealer label + the lead this deal
            // was converted from. Both are display-only enrichments on
            // GET /deals/:id; absent for deals without them.
            if hasSummaryRows(d) {
                VStack(alignment: .leading, spacing: 6) {
                    if let dealer = d.dealerName, !dealer.isEmpty {
                        summaryRow("DEALER", dealer)
                    }
                    if let leadName = d.leadName, !leadName.isEmpty {
                        let phone = (d.leadPhone?.isEmpty == false) ? d.leadPhone : nil
                        summaryRow("SOURCE LEAD", phone.map { "\(leadName) · \($0)" } ?? leadName)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func hasSummaryRows(_ d: Deal) -> Bool {
        (d.dealerName?.isEmpty == false) || (d.leadName?.isEmpty == false)
    }

    /// Compact labelled row inside the hero card (label column matches the
    /// AMOUNT / WEIGHT eyebrow style above).
    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Total weight (kg) for the deal — prefers custom_fields.volume_kg,
    /// falls back to recomputing from product_lines so deals saved before
    /// the volume mirror landed still surface a number.
    private func derivedWeightKg(_ d: Deal) -> Double {
        let cf: [String: Any] = (d.customFields ?? [:]).compactMapValues { $0.raw?.any }
        if let v = cf["volume_kg"] as? Double, v > 0 { return v }
        if let v = cf["volume_kg"] as? Int, v > 0 { return Double(v) }
        guard let lines = cf["product_lines"] as? [[String: Any]] else { return 0 }
        var total = 0.0
        for l in lines {
            let qty: Double = {
                if let n = l["quantity"] as? Double { return n }
                if let n = l["quantity"] as? Int { return Double(n) }
                if let s = l["quantity"] as? String { return Double(s) ?? 0 }
                return 0
            }()
            guard qty > 0 else { continue }
            let unit = (l["measuring_unit"] as? String)?.lowercased() ?? ""
            total += qty * (unit == "tonne" ? 1000 : 1)
        }
        return total
    }

    /// Compact kg / t formatter — kg under a tonne, tonnes otherwise.
    private func formatKg(_ kg: Double) -> String {
        if kg < 1000 {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
            return "\(f.string(from: NSNumber(value: kg)) ?? "0") kg"
        }
        let tons = kg / 1000
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = tons < 10 ? 2 : 1
        return "\(f.string(from: NSNumber(value: tons)) ?? "0") t"
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

    /// Map a NextBestAction action verb to the activity type the composer
    /// understands. Anything not in the segmented picker (send_proposal,
    /// nurture, follow_up, …) gets logged as a task so the rep still
    /// captures the commitment on the timeline.
    private func activityTypeFor(_ nbaAction: String) -> String {
        switch nbaAction.lowercased() {
        case "call":    return "call"
        case "email":   return "email"
        case "meeting": return "meeting"
        case "note":    return "note"
        default:        return "task"
        }
    }
}
