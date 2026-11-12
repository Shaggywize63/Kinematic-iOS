import Foundation
import Combine

@MainActor
final class ActivitiesViewModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var typeFilter: String
    @Published var ownerFilter: String = "all"      // user_id or "all"
    @Published var owners: [AssignableUser] = []
    @Published var dateFrom: Date? = nil
    @Published var dateTo: Date? = nil
    // Search-by-lead filter — picking a lead in the filter strip sets
    // these; the backend list endpoint is filtered via .eq('lead_id',…).
    @Published var leadFilterId: String? = nil
    @Published var leadFilterLabel: String? = nil
    // Spark & Ray "Account" filter — activities on that account or on any of its leads (`?account_id=`).
    @Published var accountFilterId: String? = nil
    @Published var accountFilterLabel: String? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Set when a Mark complete / Reopen PATCH fails (the server's own message,
    /// e.g. the caller may not edit that activity). Shown by an alert in
    /// `ActivitiesView`; kept separate from `errorMessage`, which that screen
    /// does not surface.
    @Published var completionError: String?
    /// Shown in a "Saved" alert after logging an activity WITH a follow-up ("Activity logged + follow-up
    /// scheduled").
    @Published var successMessage: String?
    /// Shown in a "Couldn't save" alert when the follow-up could not be created after the activity itself was
    /// (the activity stays logged).
    @Published var saveError: String?

    private let api = CRMService.shared
    private let location = CRMLocationStore.shared
    private var cancellables = Set<AnyCancellable>()

    init(initialFilter: String = "all") {
        self.typeFilter = initialFilter
        // Re-fetch when the global city/state scope changes (mirrors leads).
        location.$state.combineLatest(location.$city)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
    }

    var filtered: [Activity] {
        typeFilter == "all" ? activities : activities.filter { ($0.type ?? "") == typeFilter }
    }

    // Full ISO8601 timestamp — yyyy-MM-dd let PostgREST treat the `to`
    // boundary as midnight-UTC, dropping every row created during the
    // picked day. With a timezone-aware timestamp the rep's "today"
    // covers their full local day.
    private static let isoTimestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withTimeZone]
        return f
    }()

    func loadOwners() async {
        owners = await api.listAssignableUsers()
    }

    /// Pick (or, with nil, clear) the Account filter and reload.
    func setAccountFilter(_ account: CRMAccount?) async {
        accountFilterId = account?.id
        accountFilterLabel = account?.name
        await refresh()
    }

    /// Pick (or, with nil, clear) the User filter and reload. `ownerFilter` stays "all" when cleared.
    func setUserFilter(_ userId: String?) async {
        ownerFilter = (userId ?? "").isEmpty ? "all" : (userId ?? "all")
        await refresh()
    }

    /// The name shown on the User chip: the picked person, else "User".
    var userFilterTitle: String {
        guard ownerFilter != "all" else { return "User" }
        return owners.first { $0.id == ownerFilter }?.displayName ?? "User"
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            activities = try await api.listActivities(
                leadId: leadFilterId,
                ownerId: ActivityQuery.ownerParam(ownerFilter),
                accountId: accountFilterId,
                city: location.city,
                state: location.state,
                from: dateFrom.map { Self.isoTimestamp.string(from: $0) },
                to: dateTo.map { Self.isoTimestamp.string(from: $0) }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func log(
        type: String,
        subject: String,
        description: String,
        dealId: String?,
        leadId: String?,
        imageUrl: String? = nil,
        completedAt: Date? = nil,
        customFields: [String: Any] = [:],
        followUpAt: Date? = nil
    ) async {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else { return }
        do {
            var body: [String: Any] = ["type": type, "subject": trimmedSubject]
            let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDesc.isEmpty { body["description"] = trimmedDesc }
            if let dealId { body["deal_id"] = dealId }
            if let leadId { body["lead_id"] = leadId }
            if let imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
            if type != "task" {
                let stamp = completedAt ?? Date()
                body["completed_at"] = ISO8601DateFormatter().string(from: stamp)
                body["status"] = "completed"
            } else if let due = completedAt {
                body["due_at"] = ISO8601DateFormatter().string(from: due)
            }
            // Admin-defined activity custom fields (Dealer lookup, Visit
            // kind, …). Omit the key entirely when empty so a tenant with
            // none configured never posts `custom_fields: {}`.
            if !customFields.isEmpty { body["custom_fields"] = customFields }
            let a = try await api.createActivity(body)
            activities.insert(a, at: 0)
            // Both an Activity (done) date and a Scheduled (due) date: a second, PLANNED activity shares
            // everything but the dates (never the photo or outcome). A task already is a due date.
            if let due = followUpAt, type != "task" {
                await createFollowUp(shared: body, due: due)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The planned half of "log + schedule": POST it after the completed activity exists. A failure here leaves
    /// the logged activity in place and reports the reason (no second attempt that could duplicate it).
    private func createFollowUp(shared: [String: Any], due: Date, spark: SparkActivityExtras? = nil) async {
        let entry = ActivityLogEntry(kind: .planned, date: due)
        let body = ActivityLogPlan.body(for: entry, shared: shared)
        do {
            let created: Activity
            if let spark {
                created = try await api.createActivity(body, spark: ActivityLogPlan.extras(spark, for: .planned))
            } else {
                created = try await api.createActivity(body)
            }
            activities.insert(created, at: 0)
            successMessage = ActivityLogPlan.loggedAndScheduledMessage
        } catch {
            saveError = "The activity was logged, but the follow-up could not be scheduled: \(error.localizedDescription)"
        }
    }

    /// Schedule a FUTURE activity (a reminder) rather than logging a completed
    /// one. Persists `status: "open"` + `due_at`, which is exactly what the
    /// backend `dispatch-activity-reminders` cron scans for — so the rep (the
    /// creator/owner) gets a push + in-app reminder as the due time approaches.
    /// Distinct from `log`, which stamps `completed`/`completed_at` for
    /// after-the-fact records that never remind.
    func schedule(
        type: String,
        subject: String,
        description: String,
        dealId: String?,
        leadId: String?,
        imageUrl: String? = nil,
        remindAt: Date,
        customFields: [String: Any] = [:]
    ) async {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else { return }
        do {
            var body: [String: Any] = [
                "type": type,
                "subject": trimmedSubject,
                // Open so the reminder cron picks it up (a scheduled activity is
                // not a completed one). due_at drives the reminder window.
                "status": "open",
                "due_at": ISO8601DateFormatter().string(from: remindAt),
            ]
            let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDesc.isEmpty { body["description"] = trimmedDesc }
            if let dealId { body["deal_id"] = dealId }
            if let leadId { body["lead_id"] = leadId }
            if let imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
            if !customFields.isEmpty { body["custom_fields"] = customFields }
            let a = try await api.createActivity(body)
            activities.insert(a, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// PATCH an existing activity from the tap-to-edit row. Updates
    /// the local cache in place so the list reflects the change
    /// without a full refresh round-trip. Same body shape as `log`.
    func update(
        id: String,
        type: String,
        subject: String,
        description: String,
        imageUrl: String? = nil,
        completedAt: Date? = nil,
        customFields: [String: Any] = [:],
        assignment: [String: Any] = [:],
        linkPatch: [String: Any] = [:]
    ) async {
        // Shared with the account detail's edit path. Only touched custom fields are sent (the backend merges
        // them over the stored blob); a changed assignee (`assigned_to`) only for admins / managers.
        guard let body = ActivityEditBody.patch(
            type: type, subject: subject, description: description, imageUrl: imageUrl,
            completedAt: completedAt, customFields: customFields, assignment: assignment,
            canChangeAssignee: RecordOwnerRules.currentUserCanChange,
            linkPatch: linkPatch
        ) else { return }
        do {
            let updated = try await api.updateActivity(id: id, body: body)
            if let idx = activities.firstIndex(where: { $0.id == id }) {
                activities[idx] = updated.keepingCompany(of: activities[idx])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Spark & Ray (throwing — the composer shows the server's message inline)

    /// Create an activity from the composer's result, including the Spark extras
    /// (assignees / product interested / form serial). Throws so a bad form serial
    /// (HTTP 400) stays on the sheet next to the field instead of being swallowed.
    /// With `followUpAt` (log mode, not a task) it also creates the PLANNED follow-up due then, without the
    /// outcome; a failure of that second request is reported through `saveError` instead of throwing, so the
    /// composer is not left open for a retry that would log the first activity twice.
    func createSpark(_ result: ActivityComposeResult, scheduled: Bool, followUpAt: Date? = nil) async throws {
        let links: [String: String] = result.leadId.map { ["lead_id": $0] } ?? [:]
        let body = SparkActivityBody.createBody(result, scheduled: scheduled, links: links)
        let created = try await api.createActivity(body, spark: result.extras)
        activities.insert(created, at: 0)
        if let due = followUpAt, !scheduled, result.type != "task" {
            await createFollowUp(shared: body, due: due, spark: result.extras)
        }
    }

    /// PATCH an existing activity from the edit sheet, sending only the Spark extras that changed.
    func updateSpark(existing: Activity, _ result: ActivityComposeResult) async throws {
        // Only an admin / manager can change who it is assigned to; for anyone else the existing assignees
        // stay whatever the form held. Removing every assignee sends `assignee_ids: []` (clears the activity).
        let parts = ActivityEditBody.sparkPatch(
            existing: existing, result: result,
            canChangeAssignees: RecordOwnerRules.currentUserCanChange
        )
        let updated = try await api.updateActivity(
            id: existing.id, body: parts.body, spark: parts.extras, previous: parts.previous
        )
        if let idx = activities.firstIndex(where: { $0.id == existing.id }) {
            activities[idx] = updated.keepingCompany(of: activities[idx])
        }
    }

    /// "Mark complete" (`completed == true`) / "Reopen" (`false`) from the
    /// activity card. PATCHes status + completed_at, then flips that row's
    /// completion state in place from the response — the list keeps the row's
    /// lead / contact / deal names, which the PATCH response doesn't carry — so
    /// the card updates without a refetch. On failure the row is left as it was
    /// and the server's message is surfaced via `completionError`.
    func setCompleted(_ activity: Activity, completed: Bool) async {
        do {
            let updated = try await api.setActivityCompleted(id: activity.id, completed: completed)
            activities.applyCompletion(updated)
        } catch {
            completionError = error.localizedDescription
        }
    }

    /// Delete an activity from the timeline. Confirmed via an alert
    /// in the view so this can't fire on an accidental long-press.
    func delete(id: String) async {
        do {
            try await api.deleteActivity(id: id)
            activities.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
