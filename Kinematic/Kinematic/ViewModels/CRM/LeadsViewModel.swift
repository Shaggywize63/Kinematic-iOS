import Foundation

@MainActor
final class LeadsViewModel: ObservableObject {
    @Published var leads: [Lead] = []
    @Published var search: String = ""
    @Published var statusFilter: String = "all"
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

    var filtered: [Lead] {
        leads.filter { lead in
            (statusFilter == "all" || (lead.status ?? "") == statusFilter) &&
            (search.isEmpty || lead.displayName.lowercased().contains(search.lowercased())
             || (lead.company ?? "").lowercased().contains(search.lowercased()))
        }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            leads = try await api.listLeads(
                status: statusFilter == "all" ? nil : statusFilter,
                search: search.isEmpty ? nil : search
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(firstName: String, lastName: String, email: String, company: String, phone: String, source: String) async {
        do {
            let body: [String: Any] = [
                "first_name": firstName,
                "last_name":  lastName,
                "email":      email,
                "company":    company,
                "phone":      phone,
                "source":     source,
                "status":     "new"
            ]
            let lead = try await api.createLead(body)
            leads.insert(lead, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
