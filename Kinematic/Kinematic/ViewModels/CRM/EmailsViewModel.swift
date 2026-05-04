import Foundation
import Combine

@MainActor
final class EmailsViewModel: ObservableObject {
    @Published var emails: [EmailLog] = []
    @Published var templates: [EmailTemplate] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let e = api.listEmails()
            async let t = api.listEmailTemplates()
            emails    = (try? await e) ?? []
            templates = (try? await t) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(to: String, subject: String, body: String, templateId: String?) async {
        do {
            var payload: [String: Any] = [
                "to_address": to, "subject": subject, "body": body
            ]
            if let templateId { payload["template_id"] = templateId }
            let log = try await api.sendEmail(payload)
            emails.insert(log, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
