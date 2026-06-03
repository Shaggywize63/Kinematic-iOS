import SwiftUI

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
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
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

    init(leadId: String) {
        _vm = StateObject(wrappedValue: LeadDetailViewModel(leadId: leadId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let lead = vm.lead {
                    headerCard(lead: lead)
                    lifecycleSection(lead: lead)
                    actionsBar(lead: lead)
                    if vm.isConverted { convertedToCard }
                    if let nba = vm.nextBestAction { nextBestActionSection(nba: nba) }
                    LeadScoreBoostCard(
                        lead: lead,
                        isTata: ClientFeatures.isTataTiscon,
                        busy: vm.qualifyBusy,
                        onEdit: { editing = true },
                        onQualify: { Task { await vm.qualify() } }
                    )
                    if lead.isB2c == true { b2cProfileCard(lead: lead) }
                    if lead.latitude != nil || lead.longitude != nil { locationCard(lead: lead) }
                    if let score = vm.score { scoreCard(score: score) }
                    if !vm.relatedDeals.isEmpty { relatedDealsCard }
                    recordCard(lead: lead)
                    activitiesSection
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
                if vm.lead != nil {
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
                                dealProductId: opts.dealProductId
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
                initialSubject: composerInitialSubject
            ) { type, subject, description, imageUrl, when in
                await vm.logActivity(
                    type: type, subject: subject, description: description,
                    imageUrl: imageUrl, completedAtOverride: when
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
        .task { await vm.load() }
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
            convertedBanner(lead: lead)
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

    // MARK: - Action bar (Convert / Assign / Deactivate / Delete)

    private func actionsBar(lead: Lead) -> some View {
        // Wrap on small phones with a flexible LazyVGrid-style layout.
        FlexibleHStack(spacing: 10) {
            if !vm.isConverted && !vm.isDisqualified {
                primaryAction("Convert", icon: "arrow.triangle.branch", busy: vm.convertBusy) {
                    converting = true
                }
            }
            secondaryAction("AI Score", icon: "sparkles", busy: vm.aiBusy) {
                Task { await vm.runAIScore() }
            }
            if !vm.assignableUsers.isEmpty {
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
            Text(nba.action)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(uiColor: .label))
            if let r = nba.rationale, !r.isEmpty {
                Text(r).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Brand.red.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.red.opacity(0.25), lineWidth: 1))
        )
    }

    // MARK: - B2C profile

    private func b2cProfileCard(lead: Lead) -> some View {
        Card(title: "CUSTOMER PROFILE") {
            VStack(alignment: .leading, spacing: 6) {
                if let dob = lead.dateOfBirth { profileRow("Date of Birth", value: dob) }
                if let g = lead.gender { profileRow("Gender", value: g.replacingOccurrences(of: "_", with: " ").capitalized) }
                if let pcm = lead.preferredContactMethod { profileRow("Preferred Channel", value: pcm.capitalized) }
                if let addr = lead.fullAddress { profileRow("Address", value: addr) }
                profileRow("Marketing Consent", value: (lead.marketingConsent ?? false) ? "Yes" : "No")
                profileRow("WhatsApp Consent", value: (lead.whatsappConsent ?? false) ? "Yes" : "No")
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

    private func recordCard(lead: Lead) -> some View {
        Card(title: "RECORD") {
            VStack(alignment: .leading, spacing: 6) {
                profileRow("Lead ID", value: lead.id)
                if let owner = lead.ownerName, !owner.isEmpty { profileRow("Owner", value: owner) }
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
