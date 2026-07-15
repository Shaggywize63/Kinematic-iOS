import SwiftUI
import UIKit

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
    /// Linked account loaded lazily from `Deal.accountId` — the deal row
    /// only carries the id, so we hydrate the name for the Linked section.
    @State private var linkedAccount: CRMAccount?
    @State private var loggingActivity = false
    @State private var composerInitialType: String = "call"
    @State private var composerInitialSubject: String = ""
    /// Set after a tap-to-call POSTs the minimal call row. Composer save
    /// PATCHes this id; cancel leaves the minimal record on the timeline.
    @State private var pendingCallActivityId: String?
    @State private var closingDeal = false
    @State private var reopening = false
    @State private var reopenError: String?
    /// Lead-share card state. The deal page shares the LINKED lead's
    /// branded card (name / number / photo / owner / dealer / brand /
    /// block) — the same image the lead detail screen produces — so a rep
    /// can send it on WhatsApp without hopping back to the lead.
    @State private var shareBusy = false
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false
    @State private var shareError: String?
    /// Bumped after a successful stage move or a freshly-logged activity
    /// so DealHistorySection re-fetches without needing the whole detail
    /// screen to reload.
    @State private var historyRefreshTick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let d = initialDeal {
                    // Compact stage strip sits above everything — reps land
                    // on this screen looking for "what's the status, what
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
                    summarySection(d)
                    actionsRow(d)
                    linkedSection(d)
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
                // Share the linked lead's card (WhatsApp-ready image). Only
                // shown when the deal has a lead to share.
                if let lid = initialDeal?.leadId, !lid.isEmpty {
                    Button { shareLinkedLead(lid) } label: {
                        if shareBusy {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .tint(Brand.red)
                    .disabled(shareBusy)
                    .accessibilityLabel("Share lead")
                }
            }
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
        // System share sheet for the rendered lead card image.
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                LeadShareActivitySheet(items: [img])
            }
        }
        .alert("Share failed",
               isPresented: .init(get: { shareError != nil },
                                  set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(shareError ?? "") }
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
            if let aid = initialDeal?.accountId, linkedAccount == nil {
                linkedAccount = try? await CRMService.shared.getAccount(id: aid)
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

    // MARK: - Section scaffolding (shared card + row helpers)

    /// Card wrapper for every re-segmented section — eyebrow header
    /// (icon + tracked caps in Brand.red) over the content, matching
    /// DealHistorySection so the whole page reads as one system.
    private func sectionCard<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(Brand.red)
                Text(title)
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .foregroundColor(Brand.red)
                Spacer()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    /// Shared label/value row — fixed-width eyebrow label column so every
    /// section's values align down one vertical edge.
    private func detailRow(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(valueColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// detailRow variant for navigable rows — value renders in Brand.red
    /// with a trailing chevron; wrap it in a NavigationLink.
    private func linkRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Brand.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Share

    /// Fetch the linked lead and render its branded share card, then open
    /// the system share sheet. Mirrors the lead detail screen's share so
    /// the same image is reachable from the deal a rep is working.
    private func shareLinkedLead(_ leadId: String) {
        guard !shareBusy else { return }
        shareBusy = true
        Task { @MainActor in
            defer { shareBusy = false }
            guard let lead = try? await CRMService.shared.getLead(id: leadId),
                  let image = await LeadShareCardBuilder.makeImage(for: lead) else {
                shareError = "Could not build the share image. Please try again."
                return
            }
            shareImage = image
            showShareSheet = true
        }
    }

    // MARK: - Summary section

    /// Amount + weight hero numbers, the won-of/partial-close line, then
    /// aligned rows for status / probability / close dates.
    private func summarySection(_ d: Deal) -> some View {
        let kg = derivedWeightKg(d)
        let cf = customFieldsMap(d)
        let original = doubleValue(cf["original_amount"])
        let status = (d.status ?? "open").lowercased()
        return sectionCard("SUMMARY", icon: "doc.plaintext") {
            VStack(alignment: .leading, spacing: 12) {
                Text(d.name).font(.system(size: 18, weight: .black))
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AMOUNT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(0.8)
                        Text(formattedAmount(d))
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundColor(.primary)
                            // Keep the ₹ figure on a single line — shrink to
                            // fit rather than wrapping "₹1,06,976" onto two.
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
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
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    Spacer()
                }
                // Partial close — backend stamps original_amount on the won
                // deal when it closed for less than the full value.
                if let original {
                    Text("Won \(CurrencyFormatter.formatINR(d.amount)) of \(CurrencyFormatter.formatINR(original))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Status", statusDisplay(status), valueColor: statusColor(status))
                    if status == "lost", let reason = d.lostReason, !reason.isEmpty {
                        detailRow("Lost reason", reason)
                    }
                    if let stage = d.stageName, !stage.isEmpty {
                        detailRow("Stage", stage)
                    }
                    if let prob = probabilityDisplay(d) {
                        detailRow("Probability", prob)
                    }
                    if let close = d.expectedCloseDate?.prefix(10) {
                        detailRow("Expected close", String(close))
                    }
                    if let closed = d.actualCloseDate?.prefix(10) {
                        detailRow("Closed on", String(closed))
                    }
                }
            }
        }
    }

    private func statusDisplay(_ status: String) -> String {
        switch status {
        case "won": return "Won"
        case "lost": return "Lost"
        default: return "Open"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "won": return .green
        case "lost": return .red
        default: return .primary
        }
    }

    /// Stage probability formatted as a percentage. Tolerates both 0–1
    /// fractions and 0–100 values since the column has carried both.
    private func probabilityDisplay(_ d: Deal) -> String? {
        guard let p = d.probability, p >= 0 else { return nil }
        let pct = p <= 1 ? p * 100 : p
        return "\(Int(pct.rounded()))%"
    }

    // MARK: - Actions row (Close / Re-open + Add Activity)

    /// One compact bar under the summary: lifecycle action (Close deal for
    /// open deals, Re-open for closed ones) beside the Add Activity
    /// quick-log capsule.
    @ViewBuilder
    private func actionsRow(_ d: Deal) -> some View {
        let status = (d.status ?? "open").lowercased()
        HStack(spacing: 10) {
            if status == "won" || status == "lost" {
                reopenButton
            } else {
                closeDealButton
            }
            addActivityButton
        }
    }

    private var closeDealButton: some View {
        Button { closingDeal = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                Text("Close deal").font(.system(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.green))
            .foregroundColor(.white)
        }
    }

    private var addActivityButton: some View {
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
            .padding(.vertical, 10)
            .foregroundColor(.white)
            .background(Capsule().fill(Brand.red))
            .shadow(color: Brand.red.opacity(0.30), radius: 6, x: 0, y: 2)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: loggingActivity)
    }

    // MARK: - Linked section

    /// Everything this deal points at — source lead, dealer, primary
    /// contact (with tap-to-call), account, and partial-close siblings
    /// (parent deal / balance deal).
    @ViewBuilder
    private func linkedSection(_ d: Deal) -> some View {
        let cf = customFieldsMap(d)
        let balanceOf = stringValue(cf["balance_of"])
        let balanceDealId = stringValue(cf["balance_deal_id"])
        let hasLead = d.leadName?.isEmpty == false
        let hasDealer = d.dealerName?.isEmpty == false
        if hasLead || hasDealer || primaryContact != nil || linkedAccount != nil
            || balanceOf != nil || balanceDealId != nil {
            sectionCard("LINKED", icon: "link") {
                VStack(alignment: .leading, spacing: 10) {
                    if let leadName = d.leadName, !leadName.isEmpty {
                        let phone = (d.leadPhone?.isEmpty == false) ? d.leadPhone : nil
                        detailRow("Source lead", phone.map { "\(leadName) · \($0)" } ?? leadName)
                    }
                    if let dealer = d.dealerName, !dealer.isEmpty {
                        detailRow("Dealer", dealer)
                    }
                    if let contact = primaryContact {
                        contactRow(contact, dealName: d.name)
                    }
                    if let account = linkedAccount {
                        NavigationLink(destination: AccountDetailView(account: account)) {
                            linkRow("Account", account.name)
                        }
                        .buttonStyle(.plain)
                    }
                    // This deal is the remainder of a partial close.
                    if let parentId = balanceOf {
                        NavigationLink(destination: DealDetailView(dealId: parentId)) {
                            linkRow("Balance of", "Balance of an earlier deal")
                        }
                        .buttonStyle(.plain)
                    }
                    // This deal was partially closed and spawned a balance deal.
                    if let balanceId = balanceDealId {
                        NavigationLink(destination: DealDetailView(dealId: balanceId)) {
                            linkRow("Balance deal", "Open deal for the remainder")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Contact row with the tap-to-call affordance the old standalone
    /// contact card provided — CallButton POSTs the minimal call row and
    /// opens the composer prefilled, exactly as before.
    private func contactRow(_ contact: Contact, dealName: String) -> some View {
        let phone = (contact.phone ?? contact.mobile).flatMap { $0.isEmpty ? nil : $0 }
        return HStack(alignment: .center, spacing: 10) {
            Text("CONTACT")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                if let phone {
                    Text(phone).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let phone {
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
        }
    }

    // MARK: - Custom-field value helpers

    private func customFieldsMap(_ d: Deal) -> [String: Any] {
        (d.customFields ?? [:]).compactMapValues { $0.raw?.any }
    }

    private func doubleValue(_ v: Any?) -> Double? {
        if let n = v as? Double { return n }
        if let n = v as? Int { return Double(n) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private func stringValue(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        return nil
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

    /// Re-opening is a plain PATCH status:"open"; closing routes through
    /// the dedicated /win and /lose endpoints (see DealCloseView) so the
    /// backend writes a crm_deal_history row.
    private var reopenButton: some View {
        Button { Task { await reopenDeal() } } label: {
            HStack(spacing: 8) {
                if reopening { ProgressView().controlSize(.small) }
                else { Image(systemName: "arrow.uturn.backward") }
                Text(reopening ? "Re-opening…" : "Re-open deal")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary, lineWidth: 1))
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

    /// Total weight (kg) for the deal — prefers custom_fields.volume_kg,
    /// falls back to recomputing from product_lines so deals saved before
    /// the volume mirror landed still surface a number.
    private func derivedWeightKg(_ d: Deal) -> Double {
        let cf = customFieldsMap(d)
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
