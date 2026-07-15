import SwiftUI
import UIKit

/// Lead detail screen. Mirrors the web `crm/leads/[id]/page.tsx` surface:
///   - Header actions: Edit · Convert (full options sheet) · Assign · Deactivate · Delete
///   - Lifecycle banner: Mark Unqualified / Mark Lost (open statuses) ·
///     Disqualified / Converted banner with Re-open (closed statuses)
///   - Profile card (B2B/B2C aware)
///   - Converted-To links (contact/account/deal) once a lead converts
///   - Related Deals
///   - AI Score (+ rescore action)
///   - Activity timeline
///   - WhatsApp shortcut
///
/// Visual style: single accent — `Brand.red`. No more purple / blue / green
/// per-card themes; every highlight, badge, icon and active button is red.
struct LeadDetailView: View {
    @StateObject var vm: LeadDetailViewModel
    /// Admin field-overrides for built-in lead columns. The detail
    /// view used to render DOB / Gender / Preferred Channel
    /// unconditionally — so even after the admin hid those fields on
    /// the web console, mobile reps still saw the columns on every
    /// lead detail screen. Loading the same model the create/edit
    /// forms use lets us gate the rendered rows.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
    @State private var updateText = ""
    /// Voice dictation for the Recent Updates composer. Reuses the same
    /// on-device SFSpeechRecognizer wrapper KINI chat uses — partial
    /// transcripts stream straight into `updateText`, so a rep can log a
    /// field note hands-free (works offline; the post itself queues).
    @StateObject private var voiceRecognizer = KiniVoiceRecognizer()
    @State private var showNbaHow = false
    @State private var converting = false
    @State private var showAssignSheet = false
    @State private var confirmDeactivate = false
    @State private var confirmDelete = false
    /// Lifecycle-step-2 sheet. Driven by both header buttons (Mark
    /// Unqualified / Mark Lost) — the `disqualifyDefault` carries which
    /// outcome to pre-select on the sheet.
    @State private var disqualifying = false
    @State private var disqualifyDefault: LeadDisqualifyView.Outcome = .unqualified
    /// Activity composer presentation. Driven by both the "+ Log" button
    /// in the ACTIVITY section header and the tap-to-call flow on the
    /// phone field. Prefill state lets the call path open the composer
    /// with type=call + subject="Call with <Name>" already populated.
    @State private var loggingActivity = false
    @State private var composerInitialType: String = "call"
    @State private var composerInitialSubject: String = ""
    /// Extra prefill carried into the composer by the ✨ Suggest chips —
    /// the drafted body and, for tasks, a due date. Reset on the manual
    /// "+ Log" / tap-to-call paths so those stay blank.
    @State private var composerInitialDescription: String = ""
    @State private var composerInitialWhen: Date? = nil
    /// KINI's inline read of the current draft Update. Populated by the
    /// ✨ Suggest button; cleared on dismiss or after the rep edits/sends.
    @State private var updateSuggestion: UpdateSuggestion? = nil
    @State private var suggesting = false
    @State private var suggestError: String? = nil
    /// Inline edit state for a Recent Updates row. `editingUpdateId` is the
    /// id of the row currently in edit mode (nil = none); `editingUpdateText`
    /// holds the in-flight draft. Author-only — gated on `update.authorId`.
    @State private var editingUpdateId: String? = nil
    @State private var editingUpdateText = ""
    /// Id of the update pending delete confirmation (nil = no dialog).
    @State private var pendingDeleteUpdateId: String? = nil
    /// Lead share card — rendered on demand when the rep taps the Share
    /// toolbar button, then handed to a UIActivityViewController so
    /// WhatsApp / Messages appear in the sheet.
    @State private var shareBusy = false
    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet = false

    // MARK: Conversation Intelligence (Record call)
    // Whole feature is gated on `ClientFeatures.hasConversationIntel`
    // (the `crm_conversation_intel` module) — Tata-only today, replicable.
    /// Presents the consent → record → analyse sheet.
    @State private var recording = false
    /// Cached summary rows for the collapsible Conversations section.
    @State private var conversations: [ConversationSummary] = []
    @State private var conversationsExpanded = true
    /// True while a completed card is being expanded into its full record.
    @State private var openingConversation = false
    /// Non-nil drives the insight drill-in sheet (`.sheet(item:)`).
    @State private var conversationDetail: ConversationDetail? = nil

    init(leadId: String) {
        _vm = StateObject(wrappedValue: LeadDetailViewModel(leadId: leadId))
    }

    /// Edit RBAC — only the rep who created this lead may edit it
    /// (plus system-tier CRM admins). Owner / assigned grants read
    /// access but not edit. Mirrors the backend PATCH gate.
    private func canEditLead(_ lead: Lead) -> Bool {
        let sysRole = (Session.currentUser?.role ?? "").lowercased()
        if ["super_admin", "admin", "sub_admin"].contains(sysRole) { return true }
        guard let me = Session.currentUser?.id, let creator = lead.createdBy else { return false }
        return creator == me
    }

    /// True for system-tier CRM admins — they may delete any rep's update
    /// (the backend DELETE allows author-or-admin). Same role set the lead
    /// edit gate uses.
    private var isCRMAdmin: Bool {
        let sysRole = (Session.currentUser?.role ?? "").lowercased()
        return ["super_admin", "admin", "sub_admin"].contains(sysRole)
    }

    /// Only the rep who wrote the note may edit it (mirrors the author-only
    /// backend PATCH). Pending offline rows (`pending-…` ids) and rows with
    /// no author are never editable.
    private func canEditUpdate(_ u: LeadUpdate) -> Bool {
        guard let me = Session.currentUser?.id, let author = u.authorId else { return false }
        return author == me && !u.id.hasPrefix("pending-")
    }

    /// Author or admin may delete (mirrors the backend). Pending offline
    /// rows are never deletable through this path.
    private func canDeleteUpdate(_ u: LeadUpdate) -> Bool {
        guard !u.id.hasPrefix("pending-") else { return false }
        if isCRMAdmin { return true }
        guard let me = Session.currentUser?.id, let author = u.authorId else { return false }
        return author == me
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let lead = vm.lead {
                    headerCard(lead: lead)
                    lifecycleSection(lead: lead)
                    actionsBar(lead: lead)
                    // Products the rep captured on the lead form — read-only
                    // mirror of the multi-row picker so the basket is
                    // visible without entering edit mode.
                    LeadProductsCard(lead: lead)
                    CustomFieldsDetailCard(entity: "lead", customFields: lead.customFields)
                    nbaContainer
                    // Lead-score breakdown + Boost-score suggestions are
                    // hidden for Consumer Champion FEs (manager-tier
                    // surfaces) AND for the entire Tata Tiscon tenant —
                    // their flow doesn't use the AI score-boost loop.
                    if !ClientFeatures.isConsumerChampion && !ClientFeatures.isTataTiscon {
                        LeadScoreBoostCard(
                            lead: lead,
                            isTata: ClientFeatures.isTataTiscon,
                            busy: vm.qualifyBusy,
                            onEdit: canEditLead(lead) ? { editing = true } : {},
                            onQualify: { Task { await vm.qualify() } }
                        )
                    }
                    alternateNumbersCard(lead: lead)
                    if lead.isB2c == true { b2cProfileCard(lead: lead) }
                    if lead.latitude != nil || lead.longitude != nil { locationCard(lead: lead) }
                    if !ClientFeatures.isConsumerChampion, let score = vm.score { scoreCard(score: score) }
                    if !vm.relatedDeals.isEmpty { relatedDealsCard }
                    recentUpdatesSection
                    recordCard(lead: lead)
                    activitiesSection
                    conversationsSection
                } else if vm.isLoading {
                    ProgressView().tint(Brand.red).padding(.top, 40).frame(maxWidth: .infinity)
                } else {
                    Text("Lead not found.").foregroundColor(.secondary).padding(.top, 40)
                }
            }
            .padding(16)
        }
        .navigationTitle("Lead")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Share — renders the branded lead card image and opens
                // the system share sheet (WhatsApp included). Read-only,
                // so no edit RBAC gate.
                if let l = vm.lead {
                    Button { shareLead(l) } label: {
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
                // Edit RBAC — only the rep who CREATED this lead may
                // edit it (plus system-tier CRM admins). Mirrors the
                // backend PATCH /leads/:id gate so reps aren't promised
                // an affordance the server will then 403.
                if let l = vm.lead, canEditLead(l) {
                    Button("Edit") { editing = true }.tint(Brand.red)
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let lead = vm.lead {
                LeadEditView(lead: lead) { updated in
                    vm.lead = updated
                    Task { await vm.load() }
                }
            }
        }
        .sheet(isPresented: $converting) {
            if let lead = vm.lead {
                LeadConvertOptionsView(
                    lead: lead,
                    products: vm.products,
                    busy: $vm.convertBusy,
                    onLoadProducts: { Task { await vm.loadProductsIfNeeded() } },
                    onConvert: { opts in
                        Task {
                            await vm.convert(
                                createAccount: opts.createAccount,
                                createDeal: opts.createDeal,
                                dealName: opts.dealName,
                                dealAmount: opts.dealAmount,
                                dealVolumeKg: nil,
                                dealProductId: opts.dealProductId,
                                dealProductLines: opts.dealProductLines
                            )
                            if vm.errorMessage == nil { converting = false }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $disqualifying) {
            if let lead = vm.lead {
                LeadDisqualifyView(
                    lead: lead,
                    defaultOutcome: disqualifyDefault,
                    onDisqualified: { updated in vm.applyDisqualified(updated) }
                )
            }
        }
        .sheet(isPresented: $showAssignSheet) {
            assignSheet
        }
        // System share sheet for the rendered lead card image.
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                LeadShareActivitySheet(items: [img])
            }
        }
        // Record-call flow (consent → record → analyse). Refreshes the
        // Conversations list once a recording finishes processing.
        .sheet(isPresented: $recording) {
            RecordCallView(leadId: vm.leadId) {
                Task { await loadConversations() }
            }
        }
        // Drill-in from a completed conversation card → full insights.
        .sheet(item: $conversationDetail) { detail in
            ConversationDetailSheet(detail: detail)
        }
        .sheet(
            isPresented: $loggingActivity,
            onDismiss: {
                // The composer dismissed without an explicit save (rep hit
                // Cancel or swiped down). For a tap-to-call flow, the
                // minimal activity was already POSTed when the rep tapped
                // dial — we just need to flush any captured duration onto
                // it. For manual "+ Log" dismissals there's no pending row
                // so this is a no-op.
                Task { await vm.finalizePendingCall() }
            }
        ) {
            ActivityComposeView(
                initialType: composerInitialType,
                initialSubject: composerInitialSubject,
                initialDescription: composerInitialDescription,
                initialWhen: composerInitialWhen
            ) { type, subject, description, imageUrl, when, _, customFields in
                await vm.logActivity(
                    type: type, subject: subject, description: description,
                    imageUrl: imageUrl, completedAtOverride: when,
                    customFields: customFields
                )
            }
        }
        .confirmationDialog(
            "Mark this lead as unqualified?",
            isPresented: $confirmDeactivate,
            titleVisibility: .visible
        ) {
            Button("Deactivate", role: .destructive) { Task { await vm.deactivate() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this lead? This cannot be undone.",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await vm.delete() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this update? This cannot be undone.",
            isPresented: Binding(
                get: { pendingDeleteUpdateId != nil },
                set: { if !$0 { pendingDeleteUpdateId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteUpdateId {
                    pendingDeleteUpdateId = nil
                    Task { await vm.deleteUpdate(updateId: id) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteUpdateId = nil }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.clearMessages() } }
        )) {
            Button("OK", role: .cancel) { vm.clearMessages() }
        } message: { Text(vm.errorMessage ?? "") }
        .onChange(of: vm.dismissAfterDelete) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        // Dim + spinner while a completed conversation card is being opened.
        .overlay {
            if openingConversation {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView().tint(Brand.red).scaleEffect(1.2)
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
                }
            }
        }
        .task { await vm.load() }
        .task { await fieldOverrides.load() }
        .task { await loadConversations() }
        // Tell KINI which record is on screen so the chat answers in context.
        .onAppear {
            KiniContextHolder.shared.set(
                screen: "lead_detail",
                recordType: "lead",
                recordId: vm.leadId
            )
        }
    }

    // MARK: - Header

    private func headerCard(lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lead.displayName).font(.system(size: 22, weight: .black))
                Spacer()
                badge(lead.isB2c == true ? "B2C" : "B2B")
                ScoreBadge(score: lead.score ?? 0)
            }
            if lead.isB2c != true, let c = lead.company, !c.isEmpty {
                Text(c).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                if let e = lead.email, !e.isEmpty {
                    Label(e, systemImage: "envelope.fill")
                        .font(.caption).foregroundColor(Brand.red)
                }
                if let p = lead.phone, !p.isEmpty {
                    Label(p, systemImage: "phone.fill")
                        .font(.caption).foregroundColor(Brand.red)
                }
            }
            if let phone = lead.phone, !phone.isEmpty {
                let firstName = lead.firstName ?? lead.displayName.split(separator: " ").first.map(String.init) ?? "there"
                let prefill = "Hi \(firstName), "
                HStack(spacing: 8) {
                    CallButton(
                        phone: phone,
                        prefillSubject: "Call with \(lead.displayName)",
                        onCallInitiated: {
                            let subject = "Call with \(lead.displayName)"
                            composerInitialType = "call"
                            composerInitialSubject = subject
                            composerInitialDescription = ""
                            composerInitialWhen = nil
                            // POST the minimal call activity *immediately* so
                            // the rep sees the call land on the timeline the
                            // moment they hit dial. The composer that opens
                            // a moment later is an edit surface — saving
                            // PATCHes this same row instead of duplicating.
                            Task { _ = await vm.startCallActivity(prefillSubject: subject) }
                            loggingActivity = true
                        },
                        compact: false
                    )
                    if WhatsAppHelper.canOpen(phone: phone) {
                        WhatsAppButton(phone: phone, prefillText: prefill, compact: false)
                    }
                }
            }
            if let status = lead.status {
                Text(status.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusBackground(for: status))
                    .foregroundColor(statusForeground(for: status))
                    .cornerRadius(6)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: - Lifecycle section (step 2: disqualify + reopen)

    /// Status-aware control bar that mirrors the dashboard's lead
    /// lifecycle gestures. Renders one of three shapes:
    ///   * open statuses (new / working / nurturing / qualified) -> two
    ///     prominent buttons (Mark Unqualified, Mark Lost) that present
    ///     `LeadDisqualifyView` with the right outcome preset.
    ///   * unqualified / lost -> grey banner with the captured
    ///     `disqualified_at` + `lost_reason`, plus a "Re-open Lead" button.
    ///   * converted -> green banner with `converted_at` and (if the deal
    ///     resolves) a NavigationLink to it. Includes a "Re-open Lead"
    ///     button so the rep can roll back a mis-conversion.
    @ViewBuilder
    private func lifecycleSection(lead: Lead) -> some View {
        let status = (lead.status ?? "").lowercased()
        switch status {
        case "unqualified", "lost":
            disqualifiedBanner(lead: lead, status: status)
        case "converted":
            // Converted banner intentionally hidden — the lead has already
            // crossed to its account/contact/deal and the user wanted the
            // green callout removed.
            EmptyView()
        default:
            disqualifyButtonsRow()
        }
    }

    private func disqualifyButtonsRow() -> some View {
        HStack(spacing: 10) {
            Button {
                disqualifyDefault = .unqualified
                disqualifying = true
            } label: {
                Label("Mark Unqualified", systemImage: "pause.circle")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.yellow.opacity(0.18))
                    .foregroundColor(Color.yellow.opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.45), lineWidth: 1))
                    .cornerRadius(10)
            }
            Button {
                disqualifyDefault = .lost
                disqualifying = true
            } label: {
                Label("Mark Lost", systemImage: "xmark.circle")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Brand.red.opacity(0.12))
                    .foregroundColor(Brand.red)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.red.opacity(0.45), lineWidth: 1))
                    .cornerRadius(10)
            }
        }
    }

    private func disqualifiedBanner(lead: Lead, status: String) -> some View {
        // Lost = red tint, unqualified = neutral grey — matches dashboard.
        let isLost = status == "lost"
        let tint: Color = isLost ? Brand.red : Color.gray
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isLost ? "xmark.octagon.fill" : "pause.circle.fill")
                    .foregroundColor(tint)
                Text(isLost ? "CLOSED AS LOST" : "DISQUALIFIED")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .foregroundColor(tint)
                Spacer()
            }
            if let when = lead.disqualifiedAt {
                Text("Closed \(formatDate(when))")
                    .font(.caption).foregroundColor(.secondary)
            }
            if let reason = lead.lostReason, !reason.isEmpty {
                Text("Reason: \(reason)")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
            }
            reopenButton()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tint.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.35), lineWidth: 1))
        )
    }

    private func convertedBanner(lead: Lead) -> some View {
        // Green = success state; using a hard-coded hex so it doesn't
        // collide with Brand.red even when a future theme rotates it.
        let green = Color(red: 0.06, green: 0.62, blue: 0.40)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundColor(green)
                Text("CONVERTED")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .foregroundColor(green)
                Spacer()
            }
            if let when = lead.convertedAt {
                Text("Converted \(formatDate(when))")
                    .font(.caption).foregroundColor(.secondary)
            }
            if let deal = vm.convertedDeal {
                NavigationLink {
                    DealDetailView(dealId: deal.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up.fill").foregroundColor(green)
                        Text(deal.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(green.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(green.opacity(0.30), lineWidth: 1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            reopenButton()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(green.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(green.opacity(0.35), lineWidth: 1))
        )
    }

    private func reopenButton() -> some View {
        Button {
            Task { await vm.reopen() }
        } label: {
            HStack(spacing: 6) {
                if vm.reopenBusy { ProgressView().tint(.white).scaleEffect(0.8) }
                else { Image(systemName: "arrow.uturn.backward.circle.fill") }
                Text(vm.reopenBusy ? "Re-opening…" : "Re-open Lead")
            }
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Brand.red)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(vm.reopenBusy)
    }

    /// ISO-8601 to a short user-facing string. Falls back to the raw
    /// timestamp if parsing fails so we never render a blank banner.
    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }

    // MARK: - Share card

    /// Render the branded lead card (LeadShareCard, 1080×1350) and present
    /// the system share sheet with the image. Resolution + render happen
    /// off the button tap so the toolbar shows a spinner while lookups /
    /// the photo fetch are in flight.
    private func shareLead(_ lead: Lead) {
        guard !shareBusy else { return }
        shareBusy = true
        Task { @MainActor in
            let image = await LeadShareCardBuilder.makeImage(for: lead)
            shareBusy = false
            if let image {
                shareImage = image
                showShareSheet = true
            } else {
                vm.errorMessage = "Could not build the share image. Please try again."
            }
        }
    }

    // MARK: - Action bar (Convert / Assign / Deactivate / Delete)

    private func actionsBar(lead: Lead) -> some View {
        // Wrap on small phones with a flexible LazyVGrid-style layout.
        FlexibleHStack(spacing: 10) {
            if !vm.isConverted && !vm.isDisqualified {
                primaryAction("Convert", icon: "arrow.triangle.branch", busy: vm.convertBusy) {
                    // Every tenant goes through the Convert options sheet. Tata
                    // captures the Products of Interest basket there now (moved
                    // off the lead form); the sheet holds create-account at
                    // false so their flow stays deal-only.
                    converting = true
                }
            }
            // AI Score is a Champion-hidden manager affordance — mirrors
            // the score-card gating above.
            if !ClientFeatures.isConsumerChampion {
                secondaryAction("AI Score", icon: "sparkles", busy: vm.aiBusy) {
                    Task { await vm.runAIScore() }
                }
            }
            // Record call — only when the Conversation Intelligence module is
            // enabled for this org (opt-in; hidden for everyone else) AND the
            // tenant isn't SRS TATA Steel, whose slimmed build excludes it.
            if ClientFeatures.showsConversationIntel {
                secondaryAction("Record call", icon: "mic.fill", busy: false) {
                    recording = true
                }
            }
            // Reps with data_scope='own' (e.g. Consumer Champion) can only
            // see leads they own — reassigning would hide the record from
            // them, so suppress the affordance.
            if !vm.assignableUsers.isEmpty && ClientFeatures.canReassignLeads {
                secondaryAction("Assign", icon: "person.badge.plus", busy: vm.assignBusy) {
                    showAssignSheet = true
                }
            }
            destructiveAction("Delete", icon: "trash", busy: vm.deleteBusy) {
                confirmDelete = true
            }
        }
    }

    private func primaryAction(_ title: String, icon: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(.white).scaleEffect(0.8) }
                else { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Brand.red)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(busy)
    }

    private func secondaryAction(_ title: String, icon: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(Brand.red).scaleEffect(0.8) }
                else { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundColor(Brand.red)
            .background(Brand.red.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.red.opacity(0.30), lineWidth: 1))
            .cornerRadius(10)
        }
        .disabled(busy)
    }

    private func destructiveAction(_ title: String, icon: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(Brand.red).scaleEffect(0.8) }
                else { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundColor(Brand.red)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.red.opacity(0.6), lineWidth: 1))
            .cornerRadius(10)
        }
        .disabled(busy)
    }

    // MARK: - Converted-To card

    private var convertedToCard: some View {
        Card(title: "CONVERTED TO") {
            FlexibleHStack(spacing: 8) {
                // Each chip used to be a static label — tapping it did
                // nothing. Now each one wraps a NavigationLink so reps
                // jump straight into the contact / account / deal
                // detail screen. The VM eagerly loads each linked
                // object after a conversion, so the navigation target
                // is ready by the time the user lands here.
                if let contact = vm.convertedContact {
                    NavigationLink(destination: ContactDetailView(contact: contact)) {
                        chipLink(label: "Contact", subtitle: contact.displayName, icon: "person.crop.circle.fill")
                    }
                    .buttonStyle(.plain)
                } else if vm.lead?.convertedContactId != nil {
                    // Conversion just happened and the VM hasn't hydrated yet —
                    // show the chip as a hint without a tap target.
                    chipLink(label: "Contact", subtitle: nil, icon: "person.crop.circle.fill")
                }
                if let account = vm.convertedAccount {
                    NavigationLink(destination: AccountDetailView(account: account)) {
                        chipLink(label: "Account", subtitle: account.name, icon: "building.2.fill")
                    }
                    .buttonStyle(.plain)
                } else if vm.lead?.convertedAccountId != nil {
                    chipLink(label: "Account", subtitle: nil, icon: "building.2.fill")
                }
                if let deal = vm.convertedDeal {
                    NavigationLink(destination: DealDetailView(dealId: deal.id, initialDeal: deal)) {
                        chipLink(label: "Deal", subtitle: deal.name, icon: "square.stack.3d.up.fill")
                    }
                    .buttonStyle(.plain)
                } else if vm.lead?.convertedDealId != nil {
                    chipLink(label: "Deal", subtitle: nil, icon: "square.stack.3d.up.fill")
                }
            }
        }
    }

    private func chipLink(label: String, subtitle: String?, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(Brand.red)
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased()).font(.system(size: 9, weight: .black)).tracking(0.6).foregroundColor(.secondary)
                Text(subtitle ?? "Open").font(.system(size: 13, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(Brand.red.opacity(0.6))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Brand.red.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.red.opacity(0.20), lineWidth: 1))
        .cornerRadius(8)
    }

    // MARK: - Next Best Action

    /// NBA card on the lead detail. Sourced from the lead-scoped NBA endpoint
    /// so it works for every lead (converted or not). Auto-loads on open; the
    /// refresh button re-runs the inference.
    /// Always-present NBA slot: shows a loading card while the recommendation
    /// is computing, then the real card. Keeps the lead detail from looking
    /// like it has no action card during the (sometimes slow) AI call.
    @ViewBuilder private var nbaContainer: some View {
        if let nba = vm.nextBestAction {
            nextBestActionSection(nba: nba)
                .sheet(isPresented: $showNbaHow) { NbaHowSheet(nba: nba) }
        } else if vm.nbaLoading {
            HStack(spacing: 10) {
                ProgressView().tint(Brand.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT BEST ACTION")
                        .font(.system(size: 11, weight: .black)).tracking(0.8).foregroundColor(Brand.red)
                    Text("Computing the best next move…").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(Brand.red.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.red.opacity(0.2), lineWidth: 1))
            )
        } else {
            // Not auto-loaded — each NBA call is a billed AI hit, so the rep
            // taps to compute it on demand.
            Button { Task { await vm.loadNBA() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundColor(Brand.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT BEST ACTION")
                            .font(.system(size: 11, weight: .black)).tracking(0.8).foregroundColor(Brand.red)
                        Text("Tap to get the AI-recommended next move")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16).fill(Brand.red.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.red.opacity(0.2), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func nextBestActionSection(nba: NextBestAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundColor(Brand.red)
                    Text("NEXT BEST ACTION")
                        .font(.system(size: 11, weight: .black))
                        .tracking(0.8)
                        .foregroundColor(Brand.red)
                }
                Spacer()
                if nba.methodology != nil {
                    Button { showNbaHow = true } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "questionmark.circle")
                            Text("How")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Brand.red)
                    }
                }
                Button {
                    Task { await vm.refreshNextBestAction() }
                } label: {
                    HStack(spacing: 4) {
                        if vm.nbaBusy {
                            ProgressView().tint(Brand.red).scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Brand.red)
                }
                .disabled(vm.nbaBusy)
            }
            Text(nbaActionLabel(nba.action))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(uiColor: .label))
            if let r = nba.reason ?? nba.rationale, !r.isEmpty {
                Text(r).font(.caption).foregroundColor(.secondary)
            }
            // Actionable CTAs (web parity): make the suggestion one tap to act.
            HStack(spacing: 8) {
                if nba.action.lowercased() == "qualify" {
                    Button {
                        Task { await vm.qualify() }
                    } label: {
                        Label("Mark Qualified", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Brand.red).foregroundColor(.white).clipShape(Capsule())
                    }
                    .disabled(vm.qualifyBusy)
                } else {
                    Button {
                        Task {
                            await vm.logActivity(
                                type: nbaActivityType(nba.action),
                                subject: "Next best action: \(nbaActionLabel(nba.action))",
                                description: nba.reason ?? nba.rationale ?? ""
                            )
                        }
                    } label: {
                        Label("Log it now", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Brand.red).foregroundColor(.white).clipShape(Capsule())
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Brand.red.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.red.opacity(0.25), lineWidth: 1))
        )
    }

    // MARK: - Alternate numbers (read-only)

    /// Read-only list of the lead's `alternate_mobiles`. Shown for both
    /// B2B and B2C leads whenever the list is non-empty AND the admin
    /// hasn't hidden the field on the web console — same override gate the
    /// create / edit forms honour.
    @ViewBuilder
    private func alternateNumbersCard(lead: Lead) -> some View {
        let alts = (lead.alternateMobiles ?? []).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let isB2C = lead.isB2c == true
        if !alts.isEmpty && !fieldOverrides.isHidden("alternate_mobiles", isB2C: isB2C) {
            Card(title: fieldOverrides.labelFor("alternate_mobiles", defaultLabel: "Alternate Number", isB2C: isB2C).uppercased()) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(alts.enumerated()), id: \.offset) { _, num in
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.caption).foregroundColor(Brand.red)
                            Text(num).font(.system(size: 13)).foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - B2C profile

    private func b2cProfileCard(lead: Lead) -> some View {
        // Gate every row on the admin's field-overrides — when a
        // field is hidden in the web console, the corresponding row
        // on mobile drops too. Without this, hidden DOB / Gender /
        // Preferred Channel were still visible on every lead detail.
        let showDOB = !fieldOverrides.isHidden("date_of_birth", isB2C: true)
        let showGender = !fieldOverrides.isHidden("gender", isB2C: true)
        let showChannel = !fieldOverrides.isHidden("preferred_contact_method", isB2C: true)
        let showMarketing = !fieldOverrides.isHidden("marketing_consent", isB2C: true)
        let showWhatsapp = !fieldOverrides.isHidden("whatsapp_consent", isB2C: true)
        let anyRow = showDOB || showGender || showChannel || showMarketing || showWhatsapp || (lead.fullAddress != nil)
        return Group {
            if anyRow {
                Card(title: "CUSTOMER PROFILE") {
                    VStack(alignment: .leading, spacing: 6) {
                        if showDOB, let dob = lead.dateOfBirth { profileRow(fieldOverrides.labelFor("date_of_birth", defaultLabel: "Date of Birth", isB2C: true), value: dob) }
                        if showGender, let g = lead.gender { profileRow(fieldOverrides.labelFor("gender", defaultLabel: "Gender", isB2C: true), value: g.replacingOccurrences(of: "_", with: " ").capitalized) }
                        if showChannel, let pcm = lead.preferredContactMethod { profileRow(fieldOverrides.labelFor("preferred_contact_method", defaultLabel: "Preferred Channel", isB2C: true), value: pcm.capitalized) }
                        if let addr = lead.fullAddress { profileRow("Address", value: addr) }
                        if showMarketing { profileRow(fieldOverrides.labelFor("marketing_consent", defaultLabel: "Marketing Consent", isB2C: true), value: (lead.marketingConsent ?? false) ? "Yes" : "No") }
                        if showWhatsapp { profileRow(fieldOverrides.labelFor("whatsapp_consent", defaultLabel: "WhatsApp Consent", isB2C: true), value: (lead.whatsappConsent ?? false) ? "Yes" : "No") }
                    }
                }
            }
        }
    }

    // MARK: - Location (geo coordinates)

    private func locationCard(lead: Lead) -> some View {
        Card(title: "LOCATION") {
            VStack(alignment: .leading, spacing: 6) {
                if let lat = lead.latitude { profileRow("Latitude", value: String(format: "%.6f", lat)) }
                if let lon = lead.longitude { profileRow("Longitude", value: String(format: "%.6f", lon)) }
                if let lat = lead.latitude, let lon = lead.longitude,
                   let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(lat),\(lon)") {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "map.fill")
                            Text("Open in Maps")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Brand.red)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Record (id / owner / timestamps)

    /// Humanised NBA action label (the payload sends raw verbs like "call").
    private func nbaActionLabel(_ a: String) -> String {
        switch a.lowercased() {
        case "call": return "Call the lead"
        case "meeting": return "Schedule a meeting"
        case "qualify": return "Qualify the lead"
        case "nurture": return "Nurture the lead"
        case "disqualify": return "Review / disqualify"
        default: return a.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Map an NBA action to the activity type logged by "Log it now".
    private func nbaActivityType(_ a: String) -> String {
        switch a.lowercased() {
        case "call": return "call"
        case "meeting": return "meeting"
        default: return "note"
        }
    }

    // MARK: - Recent Updates (web parity: append-only notes timeline)

    private var recentUpdatesSection: some View {
        Card(title: "RECENT UPDATES") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Add an update…", text: $updateText, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                    // 🎤 Dictate — tap to talk, tap again to stop. Partial
                    // transcripts stream straight into the draft so the rep
                    // can log a field note without typing.
                    Button {
                        if voiceRecognizer.isListening {
                            voiceRecognizer.stop()
                        } else {
                            voiceRecognizer.start { transcript in updateText = transcript }
                        }
                    } label: {
                        Image(systemName: voiceRecognizer.isListening ? "mic.fill" : "mic")
                            .imageScale(.large)
                            .foregroundColor(voiceRecognizer.isListening ? Brand.red : .secondary)
                    }
                    .disabled(vm.postingUpdate)
                    Button {
                        voiceRecognizer.stop()
                        let t = updateText
                        updateText = ""
                        // The draft is being posted — KINI's read of it no
                        // longer applies, so drop any stale suggestion.
                        updateSuggestion = nil
                        Task { await vm.addUpdate(t) }
                    } label: {
                        if vm.postingUpdate {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill").foregroundColor(Brand.red)
                        }
                    }
                    .disabled(vm.postingUpdate || updateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let voiceErr = voiceRecognizer.permissionError {
                    Text(voiceErr).font(.caption2).foregroundColor(.secondary)
                }
                // ✨ Suggest — ask KINI to read the latest *submitted* update and
                // propose the next CRM action. Only shown once at least one
                // update has been logged (never on the live draft). Uses the
                // lightweight /ai/suggest-from-update helper so it never touches
                // the monthly KINI chat quota.
                if !vm.updates.isEmpty {
                    HStack {
                        Button {
                            Task { await runSuggest() }
                        } label: {
                            HStack(spacing: 6) {
                                if suggesting {
                                    ProgressView().tint(Brand.red).scaleEffect(0.8)
                                    Text("Thinking…")
                                } else {
                                    Text("✨")
                                    Text("Suggest")
                                }
                            }
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundColor(Brand.red)
                            .background(Brand.red.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.red.opacity(0.30), lineWidth: 1))
                            .cornerRadius(10)
                        }
                        .disabled(suggesting)
                        Spacer()
                    }
                }
                if let err = suggestError {
                    Text(err).font(.caption).foregroundColor(.secondary)
                }
                if let s = updateSuggestion {
                    suggestionPanel(s)
                }
                if vm.updates.isEmpty {
                    Text("No updates yet.").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(vm.updates) { u in
                        updateRow(u)
                        Divider()
                    }
                }
            }
        }
    }

    /// A single Recent Updates row. Renders inline-editable when the rep
    /// tapped Edit on it (author-only); otherwise shows the note with a
    /// context menu carrying Edit / Delete for rows the rep may modify.
    @ViewBuilder
    private func updateRow(_ u: LeadUpdate) -> some View {
        if editingUpdateId == u.id {
            updateEditor(u)
        } else {
            let editable = canEditUpdate(u)
            let deletable = canDeleteUpdate(u)
            VStack(alignment: .leading, spacing: 2) {
                Text(u.body).font(.system(size: 13)).foregroundColor(.primary)
                HStack(spacing: 6) {
                    if let who = u.authorName, !who.isEmpty {
                        Text(who).font(.caption2).foregroundColor(.secondary)
                    }
                    if let when = u.createdAt {
                        Text(formatDate(when)).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .contextMenu {
                if editable {
                    Button {
                        editingUpdateText = u.body
                        editingUpdateId = u.id
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
                if deletable {
                    Button(role: .destructive) {
                        pendingDeleteUpdateId = u.id
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// Inline editor swapped in for the row being edited. Seeded with the
    /// current body; Save calls the VM (author-only PATCH), Cancel restores
    /// the read-only row.
    @ViewBuilder
    private func updateEditor(_ u: LeadUpdate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Update…", text: $editingUpdateText, axis: .vertical)
                .lineLimit(1...6)
                .font(.system(size: 13))
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") {
                    editingUpdateId = nil
                    editingUpdateText = ""
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                Button("Save") {
                    let text = editingUpdateText
                    let id = u.id
                    editingUpdateId = nil
                    editingUpdateText = ""
                    Task { await vm.editUpdate(updateId: id, body: text) }
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Brand.red)
                .disabled(editingUpdateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - ✨ Suggest (KINI inline read of the draft update)

    /// Ask KINI to read the latest *submitted* Update (newest-first, so
    /// `vm.updates.first`) and propose the next CRM action. Cheap single-shot
    /// helper — does not affect the chat quota.
    private func runSuggest() async {
        let text = (vm.updates.first?.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !suggesting else { return }
        suggesting = true
        suggestError = nil
        updateSuggestion = nil
        defer { suggesting = false }
        do {
            let s = try await CRMService.shared.suggestFromUpdate(leadId: vm.leadId, draft: text)
            if s.isEmpty {
                suggestError = "No suggestion for this update — try adding a bit more detail."
            } else {
                updateSuggestion = s
            }
        } catch {
            suggestError = "Could not get a suggestion. \(error.localizedDescription)"
        }
    }

    /// Panel of suggestion chips. Each chip opens the activity composer
    /// pre-filled — nothing is logged silently; the rep reviews and saves.
    @ViewBuilder
    private func suggestionPanel(_ s: UpdateSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("✨ KINI SUGGESTS")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.6)
                    .foregroundColor(Brand.red)
                Spacer()
                Button {
                    updateSuggestion = nil
                    suggestError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
            }
            FlexibleHStack(spacing: 8) {
                if let a = s.activity {
                    suggestionChip(icon: "list.bullet.rectangle", label: "Log \(a.type.capitalized): \(a.subject)") {
                        presentComposer(
                            type: composerType(for: a.type),
                            subject: a.subject,
                            description: a.body,
                            when: parseISODate(a.dueAt)
                        )
                    }
                }
                if let f = s.followup {
                    suggestionChip(icon: "arrowshape.turn.up.right", label: "Draft \(f.channel.capitalized) follow-up") {
                        presentComposer(
                            type: composerType(for: f.channel),
                            subject: "Follow-up",
                            description: f.message,
                            when: nil
                        )
                    }
                }
                ForEach(Array(s.nextActions.enumerated()), id: \.offset) { _, action in
                    suggestionChip(icon: "checkmark.circle", label: action) {
                        presentComposer(type: "task", subject: action, description: "", when: nil)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Brand.red.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.red.opacity(0.20), lineWidth: 1))
        )
    }

    private func suggestionChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(label).lineLimit(2)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundColor(Brand.red)
            .background(Brand.red.opacity(0.10))
            .overlay(Capsule().stroke(Brand.red.opacity(0.30), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Open the activity composer pre-filled from a suggestion chip.
    private func presentComposer(type: String, subject: String, description: String, when: Date?) {
        composerInitialType = type
        composerInitialSubject = subject
        composerInitialDescription = description
        composerInitialWhen = when
        loggingActivity = true
    }

    /// Map a suggestion's type/channel onto a type the composer's segmented
    /// picker can select. The picker offers meeting/call/email/note/task, so
    /// whatsapp / sms fall back to "note" (the body still carries the draft).
    private func composerType(for raw: String) -> String {
        switch raw.lowercased() {
        case "meeting", "call", "email", "note", "task": return raw.lowercased()
        default: return "note"
        }
    }

    /// Lenient ISO-8601 parse for a suggested `due_at`. Returns nil on any
    /// failure so the composer just defaults to "now".
    private func parseISODate(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private func recordCard(lead: Lead) -> some View {
        Card(title: "RECORD") {
            VStack(alignment: .leading, spacing: 6) {
                // Consumer Champions own everything they create — the
                // Owner row is redundant for them.
                if !ClientFeatures.isConsumerChampion,
                   let owner = lead.ownerName, !owner.isEmpty {
                    profileRow("Owner", value: owner)
                }
                if let created = lead.createdAt { profileRow("Created", value: formatDate(created)) }
                if let updated = lead.updatedAt { profileRow("Updated", value: formatDate(updated)) }
            }
        }
    }

    private func profileRow(_ label: String, value: String) -> some View {
        // Flexible two-column row: the label caps at 130pt (shrinks for short
        // labels) and the value takes the rest and wraps instead of clipping —
        // keeps long values + large Dynamic Type readable on small phones.
        HStack(alignment: .top, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundColor(.secondary)
                .frame(maxWidth: 130, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(value).font(.system(size: 13)).foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Score (red)

    private func scoreCard(score: LeadScore) -> some View {
        Card(title: "AI SCORE") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Int(score.score))").font(.system(size: 36, weight: .black)).foregroundColor(Brand.red)
                    if let band = score.band {
                        Text(band.uppercased())
                            .font(.caption2).bold()
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Brand.red.opacity(0.15))
                            .foregroundColor(Brand.red)
                            .cornerRadius(4)
                    }
                }
                if let breakdown = score.breakdown {
                    ForEach(breakdown) { b in
                        HStack {
                            Text(b.factor).font(.caption)
                            Spacer()
                            Text("+\(Int(b.points))").font(.caption).foregroundColor(Brand.red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Related deals

    private var relatedDealsCard: some View {
        Card(title: "DEALS (\(vm.relatedDeals.count))") {
            VStack(spacing: 8) {
                ForEach(vm.relatedDeals) { d in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                            if let stage = d.stageName, let status = d.status {
                                Text("\(stage) · \(status)").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(CurrencyFormatter.formatINRCompact(d.amount ?? 0))
                            .font(.system(size: 14, weight: .bold)).foregroundColor(Brand.red)
                    }
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .cornerRadius(10)
                }
            }
        }
    }

    // MARK: - Activities

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ACTIVITY")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .foregroundColor(Brand.red)
                Spacer()
                Button(action: {
                    composerInitialType = "call"
                    composerInitialSubject = ""
                    composerInitialDescription = ""
                    composerInitialWhen = nil
                    loggingActivity = true
                }) {
                    Label("Log", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Brand.red)
            }
            if vm.activities.isEmpty {
                Text("No activity logged.").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(vm.activities) { a in
                    ActivityTimelineItem(activity: a)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: - Assign sheet

    private var assignSheet: some View {
        NavigationStack {
            List(vm.assignableUsers) { user in
                Button {
                    Task {
                        await vm.assign(toUser: user)
                        if vm.errorMessage == nil { showAssignSheet = false }
                    }
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.fill").foregroundColor(Brand.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName).foregroundColor(.primary)
                            if let role = user.role {
                                Text(role.capitalized).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("Assign To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { showAssignSheet = false }.tint(Brand.red)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Brand.red)
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private func statusBackground(for status: String) -> Color {
        switch status.lowercased() {
        case "converted": return Brand.red
        case "qualified", "working", "new": return Brand.red.opacity(0.15)
        case "unqualified", "lost": return Color.secondary.opacity(0.18)
        default: return Brand.red.opacity(0.10)
        }
    }

    private func statusForeground(for status: String) -> Color {
        switch status.lowercased() {
        case "converted": return .white
        case "unqualified", "lost": return .secondary
        default: return Brand.red
        }
    }

    // MARK: - Conversations (Record call — module-gated)

    /// Collapsible list of this lead's recorded conversations. Rendered only
    /// when the Conversation Intelligence module is on AND at least one
    /// conversation exists (keeps the screen uncluttered — the Record-call
    /// button in the action bar is the entry point until the first recording).
    @ViewBuilder private var conversationsSection: some View {
        if ClientFeatures.showsConversationIntel && !conversations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { conversationsExpanded.toggle() }
                } label: {
                    HStack {
                        Text("CONVERSATIONS (\(conversations.count))")
                            .font(.system(size: 11, weight: .black))
                            .tracking(0.8)
                            .foregroundColor(Brand.red)
                        Spacer()
                        Image(systemName: conversationsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Brand.red)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if conversationsExpanded {
                    VStack(spacing: 10) {
                        ForEach(conversations) { conv in
                            conversationCard(conv)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
        }
    }

    @ViewBuilder private func conversationCard(_ conv: ConversationSummary) -> some View {
        let status = (conv.status ?? "").lowercased()
        let complete = status == "complete"
        Button {
            openConversation(conv)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "waveform").foregroundColor(Brand.red)
                    Text(conv.createdAt.map(formatDate) ?? "Recording")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    conversationStatusChip(status)
                }
                HStack(spacing: 8) {
                    if let d = conv.durationSeconds, d > 0 {
                        Label(durationLabel(d), systemImage: "clock")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    if let intent = conv.intent, !intent.isEmpty {
                        Text(intent.capitalized).font(.caption2).foregroundColor(.secondary)
                    }
                    if let sentiment = conv.sentiment, !sentiment.isEmpty {
                        Text("· \(sentiment.capitalized)").font(.caption2).foregroundColor(.secondary)
                    }
                }
                if let summary = conv.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if complete {
                    HStack(spacing: 4) {
                        Text("View insights").font(.caption2).fontWeight(.bold).foregroundColor(Brand.red)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundColor(Brand.red)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemBackground)))
        }
        .buttonStyle(.plain)
        .disabled(!complete)
    }

    @ViewBuilder private func conversationStatusChip(_ status: String) -> some View {
        switch status {
        case "complete":
            Text("Complete")
                .font(.caption2).fontWeight(.semibold)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Brand.success.opacity(0.15))
                .foregroundColor(Brand.success)
                .cornerRadius(6)
        case "failed":
            Text("Failed")
                .font(.caption2).fontWeight(.semibold)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Brand.red.opacity(0.15))
                .foregroundColor(Brand.red)
                .cornerRadius(6)
        default:
            // Any non-terminal status (uploaded / transcribing / analyzing /
            // processing / empty). Show a subtle pulsing chip so the rep
            // sees the row is still live after they backgrounded the sheet.
            ProcessingChip()
        }
    }

    private func durationLabel(_ secs: Int) -> String {
        String(format: "%d:%02d", secs / 60, secs % 60)
    }

    /// Load the lead's conversation summaries (no-op when the module is off).
    private func loadConversations() async {
        guard ClientFeatures.showsConversationIntel else { return }
        let list = await KinematicRepository.shared.listLeadConversations(leadId: vm.leadId)
        await MainActor.run { self.conversations = list }
    }

    /// Fetch the full record for a completed card and present the insight sheet.
    private func openConversation(_ conv: ConversationSummary) {
        guard (conv.status ?? "").lowercased() == "complete" else { return }
        openingConversation = true
        Task {
            let detail = await KinematicRepository.shared.getConversation(id: conv.id)
            await MainActor.run {
                openingConversation = false
                conversationDetail = detail
            }
        }
    }
}

// MARK: - Generic card wrapper

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .black))
                .tracking(0.8)
                .foregroundColor(Brand.red)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }
}

// MARK: - Flexible H-stack (wraps onto multiple lines)

/// Simple wrapping H-stack so the actions row doesn't clip on narrow phones.
/// SwiftUI's stock `HStack` would force a single line; the system `Layout`
/// API gives us flowing layout without a third-party dependency.
private struct FlexibleHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width + spacing
                rowHeight = size.height
            } else {
                rowWidth += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Processing chip (pulsing "in-flight" indicator for conversations)

/// Small pulsing "Processing…" tag shown on conversation rows whose backend
/// status is not yet complete/failed. Kept intentionally minimal — a single
/// opacity ease so it reads as live without pulling attention.
private struct ProcessingChip: View {
    @State private var pulse = false

    var body: some View {
        Text("Processing…")
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Brand.info.opacity(0.15))
            .foregroundColor(Brand.info)
            .cornerRadius(6)
            .opacity(pulse ? 0.45 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
