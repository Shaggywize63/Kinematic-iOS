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
}
