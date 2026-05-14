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
            // Lead + its activities load eagerly. Related entities (deals,
            // converted-to) and assignable users load opportunistically so a
            // slow /users call (403 for client-role users) never blocks the
            // main lead render.
            async let leadTask = api.getLead(id: leadId)
            async let actsTask = api.leadActivities(id: leadId)
            let lead = try await leadTask
            self.lead = lead
            self.activities = (try? await actsTask) ?? []
            await loadAuxiliary(lead: lead)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadAuxiliary(lead: Lead) async {
        // Convert links — best-effort, each independently.
        if let cid = lead.convertedContactId {
            convertedContact = try? await api.getContact(id: cid)
        }
        if let aid = lead.convertedAccountId {
            convertedAccount = try? await api.getAccount(id: aid)
        }
        if let did = lead.convertedDealId {
            convertedDeal = try? await api.getDeal(id: did)
        }
        // Related deals — backend has a dedicated `/leads/{id}/deals` route
        // that returns every deal linked to this lead.
        relatedDeals = (try? await api.leadDeals(id: lead.id)) ?? []
        // Assignable users — silent 403 → empty.
        assignableUsers = await api.listAssignableUsers()
        // Next Best Action for the converted deal, if any. Backend NBA
        // is deal-scoped; we mirror the web behaviour by surfacing it on
        // the lead detail when the lead has a converted deal.
        if let did = lead.convertedDealId {
            nextBestAction = try? await api.aiNextBestAction(dealId: did)
        } else {
            nextBestAction = nil
        }
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

    /// Log a new activity bound to this lead. Non-task kinds are marked
    /// completed at save time so they show up in the timeline immediately.
    /// If a tap-to-call was the trigger and the call connected, the
    /// captured duration is included on the activity so reports can split
    /// "real conversations" from "no-answers".
    func logActivity(type: String, subject: String, description: String, imageUrl: String? = nil) async {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else { return }
        var body: [String: Any] = [
            "type": type,
            "subject": trimmedSubject,
            "description": description,
            "lead_id": leadId,
        ]
        if let imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
        if type != "task" {
            let now = ISO8601DateFormatter().string(from: Date())
            body["completed_at"] = now
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

    /// Auto-log fallback: called when the rep dialed via the Call button
    /// but dismissed the composer without saving. We only fire if the
    /// CallObserver recorded a connected call (>0s) so a pocket-dial /
    /// no-answer doesn't pollute the timeline.
    func autoLogCallIfNeeded(prefillSubject: String) async {
        guard let duration = CallObserver.shared.consumeDuration(), duration > 0 else { return }
        let subject = prefillSubject.isEmpty ? "Call (auto-logged)" : prefillSubject
        let body: [String: Any] = [
            "type": "call",
            "subject": subject,
            "description": "",
            "lead_id": leadId,
            "completed_at": ISO8601DateFormatter().string(from: Date()),
            "status": "completed",
            "duration_seconds": duration,
        ]
        if let created = try? await api.createActivity(body) {
            activities.insert(created, at: 0)
        }
    }
}
