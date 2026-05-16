import Foundation
import Combine

/// Drives `LeadDetailView`. Mirrors the web `crm/leads/[id]/page.tsx`
/// surface: AI score, activities, convert (with options), assign, deactivate,
/// delete, plus the converted-to references and related deals.
@MainActor
final class LeadDetailViewModel: ObservableObject {
    @Published var lead: Lead?
    @Published var score: LeadScore?
    @Published var activities: [Activity] = []
    @Published var relatedDeals: [Deal] = []
    @Published var convertedContact: Contact?
    @Published var convertedAccount: CRMAccount?
    @Published var convertedDeal: Deal?
    /// Next Best Action for the lead's converted deal. Lead-scoped NBA
    /// doesn't exist server-side (the backend endpoint is per-deal), so
    /// we surface the converted deal's NBA on the lead detail when one
    /// is available. Mirrors how the web lead page hosts the card.
    @Published var nextBestAction: NextBestAction?
    @Published var nbaBusy = false
    @Published var products: [Product] = []
    @Published var assignableUsers: [AssignableUser] = []
    @Published var isLoading = false
    @Published var aiBusy = false
    @Published var convertBusy = false
    @Published var assignBusy = false
    @Published var deactivateBusy = false
    @Published var deleteBusy = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    /// Non-nil after a successful delete so the view can pop itself.
    @Published var dismissAfterDelete = false

    private let api = CRMService.shared
    let leadId: String

    init(leadId: String) { self.leadId = leadId }

    var isConverted: Bool {
        (lead?.status?.lowercased() == "converted") || (lead?.convertedAt != nil)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Lead is the only blocking fetch — we need it to know which
            // auxiliary calls to make (convertedDealId etc). Everything
            // else fires in parallel so the screen lands as a single
            // refresh rather than 6 sequential round-trips.
            async let leadTask = api.getLead(id: leadId)
            async let actsTask = api.leadActivities(id: leadId)
            async let dealsTask = api.leadDeals(id: leadId)
            async let assignableTask = api.listAssignableUsers()
            let lead = try await leadTask
            self.lead = lead
            self.activities = (try? await actsTask) ?? []
            self.relatedDeals = (try? await dealsTask) ?? []
            self.assignableUsers = await assignableTask
            // Auxiliary fetches that depend on lead fields (converted IDs)
            // fan out in parallel too.
            await loadAuxiliary(lead: lead)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadAuxiliary(lead: Lead) async {
        // Run every convert-link + NBA call concurrently. Each one is
        // independent, so there's no reason to await them in sequence
        // (the previous implementation was up to 4 sequential round-trips
        // — visible as a "spinner stays for ages" on slower connections).
        let contact = Task<Contact?, Never> {
            guard let cid = lead.convertedContactId else { return nil }
            return try? await api.getContact(id: cid)
        }
        let account = Task<CRMAccount?, Never> {
            guard let aid = lead.convertedAccountId else { return nil }
            return try? await api.getAccount(id: aid)
        }
        let deal = Task<Deal?, Never> {
            guard let did = lead.convertedDealId else { return nil }
            return try? await api.getDeal(id: did)
        }
        let nba = Task<NextBestAction?, Never> {
            guard let did = lead.convertedDealId else { return nil }
            return try? await api.aiNextBestAction(dealId: did)
        }
        convertedContact = await contact.value
        convertedAccount = await account.value
        convertedDeal = await deal.value
        nextBestAction = await nba.value
    }

    /// Manual refresh of the converted-deal's NBA. Only meaningful when the
    /// lead has been converted; no-op otherwise. Used by the "Refresh" button
    /// on the lead detail's NBA card.
    func refreshNextBestAction() async {
        guard let did = lead?.convertedDealId else { return }
        nbaBusy = true
        defer { nbaBusy = false }
        nextBestAction = try? await api.aiNextBestAction(dealId: did)
    }

    func loadProductsIfNeeded() async {
        guard products.isEmpty else { return }
        products = (try? await api.listProducts()) ?? []
    }

    // MARK: - AI

    func runAIScore() async {
        aiBusy = true
        defer { aiBusy = false }
        do { score = try await api.aiScoreLead(id: leadId) }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Lifecycle actions

    /// Web parity: convert payload mirrors `LeadConvertModal.tsx`.
    /// Pass `nil` for any field to omit it; the backend derives defaults.
    func convert(
        createAccount: Bool,
        createDeal: Bool,
        dealName: String?,
        dealAmount: Double?,
        dealVolumeKg: Double?,
        dealProductId: String?
    ) async {
        convertBusy = true
        defer { convertBusy = false }
        var body: [String: Any] = [
            "create_account": createAccount,
            "create_deal": createDeal,
        ]
        if let dealName, !dealName.isEmpty { body["deal_name"] = dealName }
        if let dealAmount { body["deal_amount"] = dealAmount }
        if let dealVolumeKg { body["deal_volume_kg"] = dealVolumeKg }
        if let dealProductId, !dealProductId.isEmpty { body["deal_product_id"] = dealProductId }

        do {
            let updated = try await api.convertLead(id: leadId, body: body)
            self.lead = updated
            successMessage = "Lead converted"
            await loadAuxiliary(lead: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assign(toUser user: AssignableUser) async {
        assignBusy = true
        defer { assignBusy = false }
        do {
            let updated = try await api.updateLead(id: leadId, body: ["owner_id": user.id])
            self.lead = updated
            successMessage = "Assigned to \(user.displayName)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deactivate() async {
        guard lead?.status?.lowercased() != "converted" else {
            errorMessage = "Cannot deactivate a converted lead"
            return
        }
        deactivateBusy = true
        defer { deactivateBusy = false }
        do {
            let updated = try await api.updateLead(id: leadId, body: ["status": "unqualified"])
            self.lead = updated
            successMessage = "Lead deactivated"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete() async {
        deleteBusy = true
        defer { deleteBusy = false }
        do {
            try await api.deleteLead(id: leadId)
            dismissAfterDelete = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    // MARK: - Activity logging (from "+ Log" + tap-to-call)

    /// ID of the activity created by the most recent tap-to-call. When the
    /// composer sheet that opens after the dial gets saved, we PATCH this
    /// row instead of creating a duplicate.
    @Published var pendingCallActivityId: String?

    /// Log a new activity bound to this lead. Non-task kinds are marked
    /// completed at save time so they show up in the timeline immediately.
    /// Defensive: optional fields (description, image, duration) are only
    /// included when they actually carry data so the backend zod validator
    /// never sees empty-string-vs-null ambiguity.
    ///
    /// `completedAtOverride` lets the manual composer's "When" picker stamp
    /// a custom time (defaults to "now" when nil).
    func logActivity(
        type: String,
        subject: String,
        description: String,
        imageUrl: String? = nil,
        completedAtOverride: Date? = nil
    ) async {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else { return }

        // If this composer dismissal is a save-after-tap-to-call, PATCH the
        // pre-created activity rather than POSTing a new one.
        if type == "call", let id = pendingCallActivityId {
            await patchPendingCall(id: id, subject: trimmedSubject, description: description, imageUrl: imageUrl, completedAtOverride: completedAtOverride)
            return
        }

        var body: [String: Any] = [
            "type": type,
            "subject": trimmedSubject,
            "lead_id": leadId,
        ]
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDesc.isEmpty { body["description"] = trimmedDesc }
        if let imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
        if type != "task" {
            let now = (completedAtOverride ?? Date())
            body["completed_at"] = ISO8601DateFormatter().string(from: now)
            body["status"] = "completed"
        }
        if type == "call", let duration = CallObserver.shared.consumeDuration(), duration > 0 {
            body["duration_seconds"] = duration
        }
        do {
            let created = try await api.createActivity(body)
            activities.insert(created, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Tap-to-call entry point. POSTs a minimal call activity immediately
    /// (subject + completed_at=now) so the rep sees the call on the timeline
    /// the moment they hit dial. The composer that opens after is an EDIT
    /// surface for this row — saving PATCHes it; cancelling leaves the
    /// minimal record intact.
    func startCallActivity(prefillSubject: String) async -> String? {
        let subject = prefillSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Call from CRM" : prefillSubject
        let body: [String: Any] = [
            "type": "call",
            "subject": subject,
            "lead_id": leadId,
            "completed_at": ISO8601DateFormatter().string(from: Date()),
            "status": "completed",
        ]
        do {
            let created = try await api.createActivity(body)
            activities.insert(created, at: 0)
            pendingCallActivityId = created.id
            return created.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// PATCH the auto-created call activity with notes / duration / time
    /// the rep added in the composer.
    private func patchPendingCall(
        id: String,
        subject: String,
        description: String,
        imageUrl: String?,
        completedAtOverride: Date?
    ) async {
        var body: [String: Any] = ["subject": subject]
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDesc.isEmpty { body["description"] = trimmedDesc }
        if let imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
        if let completedAtOverride {
            body["completed_at"] = ISO8601DateFormatter().string(from: completedAtOverride)
        }
        if let duration = CallObserver.shared.consumeDuration(), duration > 0 {
            body["duration_seconds"] = duration
        }
        do {
            let updated = try await api.updateActivity(id: id, body: body)
            if let i = activities.firstIndex(where: { $0.id == id }) {
                activities[i] = updated
            }
        } catch {
            // Swallow — the minimal version is still on the timeline.
            // Surfacing an error here would confuse the rep into thinking
            // the call didn't get logged.
        }
        pendingCallActivityId = nil
    }

    /// Called when the composer sheet dismisses without an explicit save.
    /// If there's a pending call activity and the CallObserver captured a
    /// duration, flush it onto the minimal record so reports stay accurate.
    /// Pocket-dials / no-answers leave the activity as-is.
    func finalizePendingCall() async {
        guard let id = pendingCallActivityId else { return }
        defer { pendingCallActivityId = nil }
        guard let duration = CallObserver.shared.consumeDuration(), duration > 0 else { return }
        if let updated = try? await api.updateActivity(id: id, body: ["duration_seconds": duration]),
           let i = activities.firstIndex(where: { $0.id == id }) {
            activities[i] = updated
        }
    }
}
