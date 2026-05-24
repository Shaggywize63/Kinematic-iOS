import SwiftUI

struct LeadDetailView: View {
    @StateObject var vm: LeadDetailViewModel
    // Observe reachability so the score-card refresh button auto-enables
    // when the device comes back online — without this the button stays
    // greyed out until some other state change re-renders the view.
    @ObservedObject private var reachability = NetworkReachability.shared
    @State private var editing = false
    @State private var loggingActivity = false
    @State private var showingWonSheet = false
    @State private var wonReason: String = ""
    /// Drives the multi-product convert sheet. Replaces the old single-tap
    /// `vm.convert()` flow so reps can attach line items (gated to Tata).
    @State private var showingConvertSheet = false
    /// When the convert sheet finishes successfully and the response carries
    /// a deal id, we stash it here and the body picks it up via a hidden
    /// NavigationLink so the user lands on the brand-new deal screen.
    @State private var pushDealId: String?
    @State private var convertSuccessMessage: String?
    /// Prefill values for the activity composer. Reset to defaults
    /// whenever the user opens the composer manually; overridden when the
    /// CallButton presents the sheet after a tap-to-call.
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
                    if lead.isWon { wonBanner(lead: lead) }
                    if lead.isB2c == true { b2cProfileCard(lead: lead) }
                    // Score card always renders — either with cached values
                    // + a refresh button, or an empty Compute Now state.
                    scoreCard()
                    aiActions(lead: lead)
                    activitiesSection
                } else if vm.isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    Text("Lead not found.").foregroundColor(.gray)
                }
            }
            .padding()
        }
        .navigationTitle("Lead")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.lead != nil { Button("Edit") { editing = true } }
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
        .sheet(
            isPresented: $loggingActivity,
            onDismiss: {
                let prefill = composerInitialSubject
                Task { await vm.autoLogCallIfNeeded(prefillSubject: prefill) }
            }
        ) {
            ActivityComposeView(
                initialType: composerInitialType,
                initialSubject: composerInitialSubject
            ) { type, subject, description in
                await vm.logActivity(type: type, subject: subject, description: description)
            }
        }
        .sheet(isPresented: $showingWonSheet) {
            wonSheet
        }
        .sheet(isPresented: $showingConvertSheet) {
            if let lead = vm.lead {
                LeadConvertView(lead: lead) { updated, dealId in
                    vm.lead = updated
                    Task { await vm.load() }
                    convertSuccessMessage = "Lead converted."
                    if let dealId, !dealId.isEmpty {
                        // Defer the navigation push by one runloop tick —
                        // the sheet is still dismissing and SwiftUI gets
                        // grumpy about routing state changes mid-transition.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            pushDealId = dealId
                        }
                    }
                }
            }
        }
        // Hidden navigation hop so we can push DealDetailView once the
        // sheet returns a deal id. navigationDestination(item:) is the
        // modern replacement for the deprecated isActive-binding link.
        .navigationDestination(item: $pushDealId) { dealId in
            DealDetailView(dealId: dealId)
        }
        .alert("Convert success", isPresented: .init(
            get: { convertSuccessMessage != nil },
            set: { if !$0 { convertSuccessMessage = nil } }
        )) {
            Button("OK", role: .cancel) { convertSuccessMessage = nil }
        } message: {
            Text(convertSuccessMessage ?? "")
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task { await vm.load() }
    }

    private func headerCard(lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lead.displayName).font(.system(size: 22, weight: .black))
                Spacer()
                if lead.isB2c == true { badge("B2C", color: .purple) } else { badge("B2B", color: .blue) }
                if lead.isWon { badge("WON", color: .green) }
                ScoreBadge(score: lead.score ?? 0)
            }
            if lead.isB2c != true, let c = lead.company { Text(c).foregroundColor(.secondary) }
            HStack(spacing: 12) {
                if let e = lead.email { Label(e, systemImage: "envelope.fill").font(.caption).foregroundColor(.blue) }
                if let p = lead.phone { Label(p, systemImage: "phone.fill").font(.caption).foregroundColor(.green) }
            }
            if let phone = lead.phone, !phone.isEmpty {
                let prefill = "Hi \(lead.firstName ?? lead.displayName.split(separator: " ").first.map(String.init) ?? "there"), "
                HStack(spacing: 8) {
                    CallButton(
                        phone: phone,
                        prefillSubject: "Call with \(lead.displayName)",
                        onCallInitiated: {
                            composerInitialType = "call"
                            composerInitialSubject = "Call with \(lead.displayName)"
                            loggingActivity = true
                        },
                        compact: false
                    )
                    if WhatsAppHelper.canOpen(phone: phone) {
                        WhatsAppButton(phone: phone, prefillText: prefill, compact: false)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }

    /// Banner shown at the top of the detail card when the lead has been
    /// closed as won. Mirrors the dashboard's green callout so the same
    /// lead read consistently across web and mobile.
    private func wonBanner(lead: Lead) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill").foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lead Won!").font(.system(size: 14, weight: .heavy)).foregroundColor(.green)
                if let reason = lead.wonReason, !reason.isEmpty {
                    Text(reason).font(.system(size: 12)).foregroundColor(.green.opacity(0.85))
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.12)))
    }

    private func b2cProfileCard(lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CUSTOMER PROFILE").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 6) {
                if let dob = lead.dateOfBirth { profileRow("Date of Birth", value: dob) }
                if let g = lead.gender { profileRow("Gender", value: g.replacingOccurrences(of: "_", with: " ").capitalized) }
                if let pcm = lead.preferredContactMethod { profileRow("Preferred Channel", value: pcm.capitalized) }
                if let addr = lead.fullAddress { profileRow("Address", value: addr) }
                profileRow("Marketing Consent", value: (lead.marketingConsent ?? false) ? "Yes" : "No")
                profileRow("WhatsApp Consent", value: (lead.whatsappConsent ?? false) ? "Yes" : "No")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.purple.opacity(0.06)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.purple.opacity(0.18), lineWidth: 1)))
    }

    private func profileRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundColor(.gray).frame(width: 130, alignment: .leading)
            Text(value).font(.system(size: 13)).foregroundColor(.primary)
            Spacer()
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .heavy)).padding(.horizontal, 6).padding(.vertical, 2).background(color).foregroundColor(.white).cornerRadius(4)
    }

    /// Lead-score card with a cache-first, refresh-on-demand contract. The
    /// view-model hydrates `vm.score` from disk on appear; the live recompute
    /// endpoint is only hit when the rep taps the refresh icon (warm cache)
    /// or the Compute Now button (cold cache). The refresh icon disables
    /// itself when offline and spins while the API call is in flight.
    @ViewBuilder
    private func scoreCard() -> some View {
        if let score = vm.score {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("AI SCORE").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(.purple)
                    Spacer()
                    refreshButton(busy: vm.aiBusy) { Task { await vm.runAIScore() } }
                }
                HStack {
                    Text("\(Int(score.score))").font(.system(size: 36, weight: .black)).foregroundColor(.purple)
                    if let band = score.band {
                        Text(band.uppercased()).font(.caption2).bold().padding(.horizontal, 8).padding(.vertical, 2).background(Color.purple.opacity(0.15)).foregroundColor(.purple).cornerRadius(4)
                    }
                }
                if let breakdown = score.breakdown {
                    ForEach(breakdown) { b in
                        HStack { Text(b.factor).font(.caption); Spacer(); Text("+\(Int(b.points))").font(.caption).foregroundColor(.green) }
                    }
                }
                if let fetched = vm.scoreFetchedAt {
                    Text("Last computed \(Self.relTimeFmt.localizedString(for: fetched, relativeTo: Date()))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.purple.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.purple.opacity(0.25), lineWidth: 1)))
        } else {
            // Empty / cold-cache state — no score has ever been computed (or
            // logout wiped the cache). Compute Now is disabled offline so
            // we don't queue a synchronous AI call that's guaranteed to fail.
            VStack(alignment: .leading, spacing: 10) {
                Text("AI SCORE").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(.purple)
                Text(reachability.isOnline ? "No score yet." : "Connect to compute.")
                    .font(.caption).foregroundColor(.secondary)
                Button { Task { await vm.runAIScore() } } label: {
                    HStack {
                        if vm.aiBusy { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                        Text("Compute now")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(reachability.isOnline ? Color.purple : Color.gray)
                    .foregroundColor(.white).cornerRadius(10)
                }
                .disabled(!reachability.isOnline || vm.aiBusy)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.purple.opacity(0.06)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.purple.opacity(0.18), lineWidth: 1)))
        }
    }

    /// Compact refresh icon shown in the card header when a cached value
    /// exists. Mirrors the convention from CRM list screens: spinner while
    /// in-flight, dimmed/disabled when offline. Reads reactivity-aware
    /// `reachability.isOnline` so the button auto-enables on reconnect.
    @ViewBuilder
    private func refreshButton(busy: Bool, action: @escaping () -> Void) -> some View {
        let online = reachability.isOnline
        Button(action: action) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(online ? .purple : .gray)
            }
        }
        .disabled(busy || !online)
    }

    private static let relTimeFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private func aiActions(lead: Lead) -> some View {
        // AI Score moved into the score card itself (refresh icon when
        // cached, Compute Now button when cold) — no need to duplicate it
        // here. Convert + Mark Won stay because they're not AI-driven.
        HStack(spacing: 10) {
            // Hide Convert + Mark as Won once the lead is closed — these are
            // open-lead actions only.
            if !lead.isWon && lead.status != "converted" {
                Button { showingConvertSheet = true } label: {
                    HStack { Image(systemName: "arrow.triangle.branch"); Text("Convert") }
                        .font(.system(size: 13, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 10).background(Color.green).foregroundColor(.white).cornerRadius(10)
                }
                Button {
                    wonReason = ""
                    showingWonSheet = true
                } label: {
                    HStack { Image(systemName: "trophy.fill"); Text("Mark Won") }
                        .font(.system(size: 13, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 10).background(Color.green.opacity(0.2)).foregroundColor(.green).cornerRadius(10)
                }
            }
            Spacer()
        }
    }

    /// Bottom sheet to capture the optional win reason before flipping the
    /// lead to Won. Empty reason is accepted — the backend treats null as
    /// "unspecified" and the green banner still renders.
    private var wonSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Win reason")) {
                    TextField("e.g. Best price, fastest delivery", text: $wonReason, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Mark as Won")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingWonSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await vm.markAsWon(reason: wonReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : wonReason)
                            showingWonSheet = false
                        }
                    } label: {
                        if vm.wonBusy { ProgressView() } else { Text("Save").bold() }
                    }
                    .disabled(vm.wonBusy)
                }
            }
        }
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ACTIVITY").font(.system(size: 11, weight: .black)).tracking(1).foregroundColor(.gray)
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
            }
            // Filter out task-type rows here too — they live on TasksView.
            let visible = vm.activities.filter { ($0.type ?? "").lowercased() != "task" }
            if visible.isEmpty { Text("No activity logged.").font(.caption).foregroundColor(.gray) }
            else { ForEach(visible) { a in ActivityTimelineItem(activity: a) } }
        }
    }
}
