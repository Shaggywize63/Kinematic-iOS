import Foundation
import Combine

@MainActor
final class LeadDetailViewModel: ObservableObject {
    @Published var lead: Lead?
    @Published var score: LeadScore?
    /// Wall-clock time the currently-shown `score` was fetched from the
    /// server. Drives the "Last computed Xh ago" subtitle on the score card.
    /// `nil` when the cache is empty — UI then shows a Compute Now button.
    @Published var scoreFetchedAt: Date?
    @Published var activities: [Activity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var aiBusy = false
    @Published var wonBusy = false

    private let api = CRMService.shared
    let leadId: String

    init(leadId: String) { self.leadId = leadId }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // Hydrate score from disk FIRST so the card renders without waiting
        // on the lead/activities round-trip and without firing the score
        // recompute endpoint. Recompute now requires an explicit Refresh tap.
        hydrateCachedScore()
        do {
            async let leadTask = api.getLead(id: leadId)
            async let actsTask = api.leadActivities(id: leadId)
            self.lead = try await leadTask
            self.activities = (try? await actsTask) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Pull the most recent cached score for this lead off disk and push it
    /// into @Published state. Safe to call repeatedly — a missing cache is
    /// treated as "no score yet" and the UI shows the Compute Now empty
    /// state. Called from `load()` on appear.
    func hydrateCachedScore() {
        guard let cached = CRMScoreNBACache.shared.loadScore(leadId: leadId) else { return }
        self.score = cached.score
        self.scoreFetchedAt = cached.fetchedAt
    }

    /// Explicit recompute path. Triggered by the Compute Now / Refresh
    /// affordances on the score card — never on .task / .onAppear. Persists
    /// the freshly-computed score so subsequent visits read it from disk.
    func runAIScore() async {
        aiBusy = true
        defer { aiBusy = false }
        do {
            let fresh = try await api.aiScoreLead(id: leadId)
            let now = Date()
            score = fresh
            scoreFetchedAt = now
            CRMScoreNBACache.shared.saveScore(leadId: leadId, score: fresh, fetchedAt: now)
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

    /// Mark this lead as won via PATCH /leads/:id — distinct from /convert,
    /// which spawns Account+Contact+Deal. The lightweight Won path stamps
    /// status=converted + lifecycle_stage=customer + won_reason so the lead
    /// detail screen can render the green WON banner without creating a
    /// downstream deal record.
    func markAsWon(reason: String?) async {
        wonBusy = true
        defer { wonBusy = false }
        var body: [String: Any] = [
            "status": "converted",
            "lifecycle_stage": "customer",
        ]
        if let reason, !reason.isEmpty { body["won_reason"] = reason }
        do {
            let updated = try await api.patchLead(id: leadId, body: body)
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
