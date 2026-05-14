import Foundation
import Combine

@MainActor
final class LeadDetailViewModel: ObservableObject {
    @Published var lead: Lead?
    @Published var score: LeadScore?
    @Published var activities: [Activity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var aiBusy = false

    private let api = CRMService.shared
    let leadId: String

    init(leadId: String) { self.leadId = leadId }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let leadTask = api.getLead(id: leadId)
            async let actsTask = api.leadActivities(id: leadId)
            self.lead = try await leadTask
            self.activities = (try? await actsTask) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runAIScore() async {
        aiBusy = true
        defer { aiBusy = false }
        do {
            score = try await api.aiScoreLead(id: leadId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func convert() async {
        do {
            let updated = try await api.convertLead(id: leadId, body: ["create_account": true, "create_deal": true])
            self.lead = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Log a new activity bound to this lead. Non-task kinds are marked
    /// completed at save time so they show up in the timeline immediately.
    /// If a tap-to-call was the trigger and the call connected, the
    /// captured duration is included on the activity so reports can split
    /// "real conversations" from "no-answers".
    func logActivity(type: String, subject: String, description: String) async {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else { return }
        var body: [String: Any] = [
            "type": type,
            "subject": trimmedSubject,
            "description": description,
            "lead_id": leadId,
        ]
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
