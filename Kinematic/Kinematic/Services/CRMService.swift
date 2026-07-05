//
//  CRMService.swift
//  Kinematic CRM
//
//  URLSession client for /api/v1/crm/*. Same auth/header conventions as
//  PlanogramService and DistributionAPI: bearer Session.sharedToken plus
//  X-Org-Id header. Uses APIEnvelope<T> for response decoding (matches the
//  backend's `{ success, data, error, message }` shape).
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum CRMServiceError: LocalizedError {
    case missingAuth
    case badResponse(Int)
    case decodeFailed(String)
    case server(String)
    /// Server error that also carries the HTTP status, so callers can branch
    /// on the code (e.g. KINI's 403 v2→v1 fallback) while still surfacing the
    /// backend message. Behaves like `.server` for display purposes.
    case serverStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAuth:               return "Please sign in again."
        case .badResponse(let s):        return "Server returned status \(s)."
        case .decodeFailed(let m):       return "Could not read server response: \(m)"
        case .server(let msg):           return msg
        case .serverStatus(_, let msg):  return msg
        }
    }
}

final class CRMService {
    static let shared = CRMService()

    private let baseHost: URL = URL(string: "https://api.kinematicapp.com")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Leads
    func listLeads(status: String? = nil, search: String? = nil, city: String? = nil, state: String? = nil,
                   from: String? = nil, to: String? = nil,
                   scoreGrade: String? = nil, scoreGte: Int? = nil,
                   lifecycle: String? = nil, isConverted: Bool? = nil,
                   limit: Int? = nil) async throws -> [Lead] {
        var q: [String: String] = [:]
        if let status { q["status"] = status }
        if let search { q["q"] = search }
        if let city { q["city"] = city }
        if let state { q["state"] = state }
        if let from { q["from"] = from }
        if let to { q["to"] = to }
        if let scoreGrade { q["score_grade"] = scoreGrade }
        if let scoreGte { q["score_gte"] = String(scoreGte) }
        if let lifecycle { q["lifecycle_stage"] = lifecycle }
        if let isConverted { q["is_converted"] = isConverted ? "true" : "false" }
        if let limit { q["limit"] = String(limit) }
        return try await get("/api/v1/crm/leads", query: q)
    }
    func getLead(id: String) async throws -> Lead { try await get("/api/v1/crm/leads/\(id)") }
    /// Lightweight geo points for the map — every geo-tagged lead (up to
    /// 5000), bypassing the 200-row list cap. Decodes into Lead (the geo
    /// payload is a subset of Lead's fields). Honours the city/state scope.
    /// Also drives the More → Nearest Leads view, which sorts by haversine
    /// distance on-device.
    /// Home aggregator — composes today's target + near-to-close leads
    /// + top-3 next actions (with rules-based reasoning) + today's
    /// activity stats + productivity tips into a single payload. One
    /// round-trip per Home tab focus.
    func crmHome() async throws -> HomePayload {
        try await get("/api/v1/crm/home")
    }

    func listLeadsGeo(city: String? = nil, state: String? = nil) async throws -> [Lead] {
        var q: [String: String] = [:]
        if let city, !city.isEmpty { q["city"] = city }
        if let state, !state.isEmpty { q["state"] = state }
        return try await get("/api/v1/crm/leads/geo", query: q)
    }
    /// Outcome of an offline-aware lead create.
    enum CreateLeadOutcome {
        case success(Lead)
        case queued(localId: String)
        case error(message: String)
    }

    /**
     * Offline-aware lead create. Tries the network first. On
     * URLError.notConnectedToInternet / .timedOut / .cannotConnectToHost
     * or a 5xx server transient, persists the payload via
     * OfflineLeadQueue and returns `.queued`. On permanent 4xx
     * (validation / auth), returns `.error` so the form can surface
     * the message and let the rep fix the input.
     */
    func createLeadOfflineAware(body: [String: Any], clientId: String?) async -> CreateLeadOutcome {
        do {
            let lead: Lead = try await postJSON("/api/v1/crm/leads", body: body)
            return .success(lead)
        } catch let err as URLError where [.notConnectedToInternet, .timedOut, .cannotConnectToHost, .networkConnectionLost, .dataNotAllowed].contains(err.code) {
            let id = OfflineLeadQueue.shared.enqueue(payload: body, clientId: clientId, lastError: err.localizedDescription)
            return .queued(localId: id)
        } catch CRMServiceError.badResponse(let code) where [408, 429, 500, 502, 503, 504].contains(code) {
            let id = OfflineLeadQueue.shared.enqueue(payload: body, clientId: clientId, lastError: "HTTP \(code)")
            return .queued(localId: id)
        } catch {
            return .error(message: error.localizedDescription)
        }
    }

    /// Direct path kept for callers that bypass the offline queue (and
    /// for the queue's own replay function, which adds the idempotency
    /// header so the server doesn't double-insert).
    func createLead(_ body: [String: Any]) async throws -> Lead {
        try await postJSON("/api/v1/crm/leads", body: body)
    }

    /// Replay-only entry point used by OfflineLeadQueue. Adds the
    /// Idempotency-Key header so the server returns the original
    /// response if the queued POST already landed once.
    func createLeadDirect(body: [String: Any], idempotencyKey: String, clientId: String?) async throws -> Lead {
        let data = body.isEmpty
            ? Data("{}".utf8)
            : try JSONSerialization.data(withJSONObject: body, options: [])
        var req = try makeRequest(path: "/api/v1/crm/leads", method: "POST", body: data)
        req.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        if let cid = clientId, !cid.isEmpty { req.setValue(cid, forHTTPHeaderField: "X-Client-Id") }
        return try await perform(req)
    }

    /// Generic authenticated mutation runner used by OfflineMutationQueue
    /// to replay any (method, path, body) tuple captured offline. Returns
    /// the HTTP status code so the queue can decide transient-vs-fatal,
    /// without forcing the queue to know how to decode every endpoint's
    /// response shape. Throws on transport failure (queue treats as
    /// transient — retry on next path-satisfied callback).
    func sendRawMutation(method: String, path: String, body: [String: Any], idempotencyKey: String, clientId: String?) async throws -> Int {
        let data = body.isEmpty
            ? Data("{}".utf8)
            : try JSONSerialization.data(withJSONObject: body, options: [])
        var req = try makeRequest(path: path, method: method, body: data)
        req.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        if let cid = clientId, !cid.isEmpty { req.setValue(cid, forHTTPHeaderField: "X-Client-Id") }
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode ?? 0
    }
    func updateLead(id: String, body: [String: Any]) async throws -> Lead {
        try await sendJSON("/api/v1/crm/leads/\(id)", method: "PATCH", body: body)
    }
    func deleteLead(id: String) async throws {
        let _: EmptyAck = try await delete("/api/v1/crm/leads/\(id)")
    }
    func scoreLead(id: String) async throws -> LeadScore {
        try await postJSON("/api/v1/crm/leads/\(id)/score", body: [:])
    }
    func leadScoreHistory(id: String) async throws -> [LeadScoreHistoryEntry] {
        try await get("/api/v1/crm/leads/\(id)/score-history")
    }
    func leadActivities(id: String) async throws -> [Activity] {
        try await get("/api/v1/crm/leads/\(id)/activities")
    }
    /// Backend exposes `/leads/{id}/deals` to fetch every deal linked to a
    /// lead (the converted deal plus any later opportunities seeded from
    /// it). Mirrors `crmLeads.deals(id)` in the web client.
    func leadDeals(id: String) async throws -> [Deal] {
        try await get("/api/v1/crm/leads/\(id)/deals")
    }
    func convertLead(id: String, body: [String: Any]) async throws -> Lead {
        try await postJSON("/api/v1/crm/leads/\(id)/convert", body: body)
    }

    /// Backend `/users` endpoint is gated by admin/supervisor/hr roles. Client-
    /// role users (CRM-only deployments) will get a 403; we treat that as an
    /// empty list so the assign button hides quietly instead of erroring.
    func listAssignableUsers() async -> [AssignableUser] {
        do {
            let list: [AssignableUser] = try await get("/api/v1/users")
            return list
        } catch {
            return []
        }
    }

    /// Lead sources for the leads-list source filter. Mirrors the web
    /// `crmLeadSources.list()` (`GET /api/v1/crm/lead-sources`). Best-effort —
    /// returns empty on any error so the filter just shows no options.
    func listLeadSources() async -> [CRMLeadSource] {
        (try? await get("/api/v1/crm/lead-sources")) ?? []
    }

    /// Per-tenant CRM settings — business_type + the free-form `config`
    /// blob the web Settings → Custom Fields page writes
    /// (field_overrides, etc.). Best-effort; returns nil on any error so
    /// the lead form falls back to its built-in defaults.
    struct CRMSettingsRaw: Codable {
        let business_type: String?
        let config: AnyJSON?
    }
    func getCRMSettings() async -> CRMSettingsRaw? {
        try? await get("/api/v1/crm/settings")
    }

    // MARK: Contacts
    func listContacts(search: String? = nil) async throws -> [Contact] {
        var q: [String: String] = [:]
        if let search { q["q"] = search }
        return try await get("/api/v1/crm/contacts", query: q)
    }
    func getContact(id: String) async throws -> Contact { try await get("/api/v1/crm/contacts/\(id)") }
    func createContact(_ body: [String: Any]) async throws -> Contact {
        try await postJSON("/api/v1/crm/contacts", body: body)
    }
    func updateContact(id: String, body: [String: Any]) async throws -> Contact {
        try await sendJSON("/api/v1/crm/contacts/\(id)", method: "PATCH", body: body)
    }
    func contactDeals(id: String) async throws -> [Deal] {
        try await get("/api/v1/crm/contacts/\(id)/deals")
    }
    func contactActivities(id: String) async throws -> [Activity] {
        try await get("/api/v1/crm/contacts/\(id)/activities")
    }

    // MARK: Accounts
    func listAccounts(search: String? = nil) async throws -> [CRMAccount] {
        var q: [String: String] = [:]
        if let search { q["q"] = search }
        return try await get("/api/v1/crm/accounts", query: q)
    }
    func getAccount(id: String) async throws -> CRMAccount { try await get("/api/v1/crm/accounts/\(id)") }
    func createAccount(_ body: [String: Any]) async throws -> CRMAccount {
        try await postJSON("/api/v1/crm/accounts", body: body)
    }
    func accountContacts(id: String) async throws -> [Contact] {
        try await get("/api/v1/crm/accounts/\(id)/contacts")
    }
    func accountDeals(id: String) async throws -> [Deal] {
        try await get("/api/v1/crm/accounts/\(id)/deals")
    }
    func accountActivities(id: String) async throws -> [Activity] {
        try await get("/api/v1/crm/accounts/\(id)/activities")
    }

    // MARK: Deals
    func listDeals(pipelineId: String? = nil, status: String? = nil, from: String? = nil, to: String? = nil) async throws -> [Deal] {
        var q: [String: String] = [:]
        if let pipelineId { q["pipeline_id"] = pipelineId }
        if let status { q["status"] = status }
        if let from { q["from"] = from }
        if let to { q["to"] = to }
        return try await get("/api/v1/crm/deals", query: q)
    }
    func getDeal(id: String) async throws -> Deal { try await get("/api/v1/crm/deals/\(id)") }
    func createDeal(_ body: [String: Any]) async throws -> Deal {
        try await postJSON("/api/v1/crm/deals", body: body)
    }
    func moveDealStage(id: String, stageId: String) async throws -> Deal {
        try await postJSON("/api/v1/crm/deals/\(id)/move-stage", body: ["stage_id": stageId])
    }
    func winDeal(id: String, amount: Double? = nil, reason: String? = nil) async throws -> Deal {
        var body: [String: Any] = [:]
        if let amount { body["amount"] = amount }
        if let reason, !reason.isEmpty { body["reason"] = reason }
        return try await postJSON("/api/v1/crm/deals/\(id)/win", body: body)
    }
    func loseDeal(id: String, reason: String) async throws -> Deal {
        try await postJSON("/api/v1/crm/deals/\(id)/lose", body: ["reason": reason])
    }
    func setWinProbability(id: String, probability: Double) async throws -> Deal {
        try await postJSON("/api/v1/crm/deals/\(id)/win-probability", body: ["probability": probability])
    }
    func setNextAction(id: String, label: String, dueAt: String?) async throws -> Deal {
        var body: [String: Any] = ["label": label]
        if let dueAt { body["due_at"] = dueAt }
        return try await postJSON("/api/v1/crm/deals/\(id)/next-action", body: body)
    }
    /// Audit trail for a deal — stage transitions, amount edits, and
    /// create/update events. Returns up to 50 rows (newest first) so the
    /// History section on DealDetailView stays responsive even on
    /// long-lived deals.
    func dealHistory(dealId: String) async throws -> [DealHistoryEvent] {
        try await get("/api/v1/crm/deals/\(dealId)/history")
    }

    // MARK: Pipelines / Stages
    func listPipelines() async throws -> [Pipeline] { try await get("/api/v1/crm/pipelines") }
    func listStages(pipelineId: String) async throws -> [Stage] {
        try await get("/api/v1/crm/stages", query: ["pipeline_id": pipelineId])
    }

    // MARK: Activities / Notes / Tasks
    /// Upcoming/overdue activities for the NotificationBell.
    /// `from`/`to` are ISO-8601 timestamps; defaults match dashboard (±7 days).
    func activitiesCalendar(from: String? = nil, to: String? = nil) async throws -> [Activity] {
        var q: [String: String] = [:]
        if let from { q["from"] = from }
        if let to { q["to"] = to }
        return try await get("/api/v1/crm/activities/calendar", query: q)
    }

    func listActivities(dealId: String? = nil, leadId: String? = nil, ownerId: String? = nil, city: String? = nil, state: String? = nil, from: String? = nil, to: String? = nil) async throws -> [Activity] {
        var q: [String: String] = [:]
        if let dealId { q["deal_id"] = dealId }
        if let leadId { q["lead_id"] = leadId }
        if let ownerId, !ownerId.isEmpty { q["owner_id"] = ownerId }
        if let city, !city.isEmpty { q["city"] = city }
        if let state, !state.isEmpty { q["state"] = state }
        if let from, !from.isEmpty { q["from"] = from }
        if let to, !to.isEmpty { q["to"] = to }
        return try await get("/api/v1/crm/activities", query: q)
    }
    func createActivity(_ body: [String: Any]) async throws -> Activity {
        try await postJSON("/api/v1/crm/activities", body: body)
    }
    /// Update an existing activity (used by the auto-log-then-edit path on
    /// the call button: tap dials + creates a minimal activity, composer
    /// opens to optionally add notes/duration, save PATCHes the same row).
    func updateActivity(id: String, body: [String: Any]) async throws -> Activity {
        try await sendJSON("/api/v1/crm/activities/\(id)", method: "PATCH", body: body)
    }
    /// Soft-delete an activity. Used by the long-press → Delete flow
    /// on the activities timeline. Backend handles the deleted_at
    /// stamp; we just need to remove the row from the local cache
    /// after the call returns.
    func deleteActivity(id: String) async throws {
        let _: EmptyAck = try await delete("/api/v1/crm/activities/\(id)")
    }
    func listNotes(leadId: String? = nil, dealId: String? = nil) async throws -> [CRMNote] {
        var q: [String: String] = [:]
        if let leadId { q["lead_id"] = leadId }
        if let dealId { q["deal_id"] = dealId }
        return try await get("/api/v1/crm/notes", query: q)
    }
    func createNote(_ body: [String: Any]) async throws -> CRMNote {
        try await postJSON("/api/v1/crm/notes", body: body)
    }
    func listTasks(status: String? = nil) async throws -> [CRMTask] {
        var q: [String: String] = [:]
        if let status { q["status"] = status }
        return try await get("/api/v1/crm/tasks", query: q)
    }
    func createTask(_ body: [String: Any]) async throws -> CRMTask {
        try await postJSON("/api/v1/crm/tasks", body: body)
    }
    func completeTask(id: String) async throws -> CRMTask {
        try await sendJSON("/api/v1/crm/tasks/\(id)", method: "PATCH", body: ["status": "done"])
    }
    /// Flip a task between done and open. Backend stamps completed_at when
    /// status flips to 'done'.
    func setTaskStatus(id: String, status: String) async throws -> CRMTask {
        try await sendJSON("/api/v1/crm/tasks/\(id)", method: "PATCH", body: ["status": status])
    }

    // MARK: Email
    func listEmailTemplates() async throws -> [EmailTemplate] {
        try await get("/api/v1/crm/email-templates")
    }
    func sendEmail(_ body: [String: Any]) async throws -> EmailLog {
        try await postJSON("/api/v1/crm/emails", body: body)
    }
    func listEmails(leadId: String? = nil, dealId: String? = nil) async throws -> [EmailLog] {
        var q: [String: String] = [:]
        if let leadId { q["lead_id"] = leadId }
        if let dealId { q["deal_id"] = dealId }
        return try await get("/api/v1/crm/emails", query: q)
    }

    // MARK: Assignment / Territories / Custom Fields (read-mostly)
    func listAssignmentRules() async throws -> [AssignmentRule] {
        try await get("/api/v1/crm/assignment-rules")
    }

    // MARK: Import
    func importPreview(rows: [[String: Any]], entity: String) async throws -> [String: AnyCodable] {
        try await postJSON("/api/v1/crm/import/preview", body: ["entity": entity, "rows": rows])
    }
    func importCommit(jobId: String) async throws -> [String: AnyCodable] {
        try await postJSON("/api/v1/crm/import/commit", body: ["job_id": jobId])
    }
    func importJob(id: String) async throws -> [String: AnyCodable] {
        try await get("/api/v1/crm/import/jobs/\(id)")
    }

    // MARK: Multi-tenant client picker (org-level admins only)
    /// Lists the clients an org-level admin can scope into, mirroring the web
    /// `GET /api/v1/misc/clients` used by `ClientSelect`. Client-pinned users
    /// never call this — their scope is fixed by the JWT `client_id` claim.
    func listClients() async throws -> [CRMClientOption] {
        try await get("/api/v1/misc/clients")
    }

    // MARK: Targets
    /// The signed-in FE's daily lead target + today's achievement. Best-effort —
    /// returns nil when no target is set or the call fails.
    func myTarget() async -> CRMTarget? {
        try? await get("/api/v1/crm/targets/me")
    }

    /// Manager: org hierarchy tiers (Consumer Champion, Area Sales Officer, …).
    func listHierarchyLevels() async -> [CRMHierarchyLevel] {
        (try? await get("/api/v1/crm/targets/levels")) ?? []
    }
    /// Manager: currently configured per-level targets + fallback default.
    func listTargetsAdmin() async -> CRMTargetsAdmin? {
        try? await get("/api/v1/crm/targets")
    }
    /// Manager: set the daily target for everyone at a hierarchy level.
    @discardableResult
    func setLevelTarget(levelId: String, value: Int) async -> Bool {
        struct Ack: Codable { let id: String? }
        let r: Ack? = try? await sendJSON("/api/v1/crm/targets", method: "PUT",
                                          body: ["hierarchy_level_id": levelId, "target_value": value])
        return r != nil
    }

    /// Active custom-field definitions for all entities (best-effort).
    /// The form filters by entity + the caller's org role.
    func listCustomFields() async -> [CRMCustomFieldDef] {
        (try? await get("/api/v1/crm/custom-fields")) ?? []
    }
    /// Searches an admin-configured lookup target table. Used by the
    /// lookup-typed custom field picker so every target — not just
    /// crm_products — populates a real dropdown. `filter` should be a
    /// JSON-encoded list of clauses (`[{ field, op, value }]`) the admin
    /// attached to the field def.
    func lookupSearch(target: String, q: String? = nil, filter: String? = nil) async -> [CRMLookupOption] {
        var qs: [String: String] = ["target": target]
        if let q, !q.isEmpty { qs["q"] = q }
        if let filter, !filter.isEmpty { qs["filter"] = filter }
        return (try? await get("/api/v1/crm/lookup/search", query: qs)) ?? []
    }
    /// Google Places address autocomplete via the backend proxy. Empty on
    /// failure / no key configured server-side.
    func placesAutocomplete(_ q: String) async -> [CRMPlacePrediction] {
        (try? await get("/api/v1/crm/places/autocomplete", query: ["q": q])) ?? []
    }
    /// Resolve a picked place id to address parts + coordinates.
    func placeDetails(_ placeId: String) async -> CRMPlaceDetail? {
        try? await get("/api/v1/crm/places/details", query: ["place_id": placeId])
    }

    /// The signed-in user's org role id (from /auth/me), used to filter which
    /// custom fields they see. nil when the user has no role / call fails.
    func myOrgRoleId() async -> String? {
        struct Me: Codable { let orgRoleId: String?; enum CodingKeys: String, CodingKey { case orgRoleId = "org_role_id" } }
        let me: Me? = try? await get("/api/v1/auth/me")
        return me?.orgRoleId
    }

    /// Manager: leaderboard for the chosen window (today | week | month).
    func leaderboard(period: String) async -> CRMLeaderboard? {
        try? await get("/api/v1/crm/targets/leaderboard", query: ["period": period])
    }
    /// Manager: the hierarchy role the leaderboard is scoped to (nil = all).
    func getLeaderboardRole() async -> String? {
        struct R: Codable { let roleId: String?; enum CodingKeys: String, CodingKey { case roleId = "role_id" } }
        let r: R? = try? await get("/api/v1/crm/targets/leaderboard-role")
        return r?.roleId
    }
    /// Manager: set the leaderboard's hierarchy role (nil clears it).
    @discardableResult
    func setLeaderboardRole(_ roleId: String?) async -> Bool {
        struct Ack: Codable { let roleId: String?; enum CodingKeys: String, CodingKey { case roleId = "role_id" } }
        let r: Ack? = try? await sendJSON("/api/v1/crm/targets/leaderboard-role", method: "PUT",
                                          body: ["role_id": roleId ?? NSNull()])
        return r != nil
    }

    // MARK: Analytics
    /// Admin-curated activity subject presets. GET is open to every
    /// CRM user so the picker renders on the activity compose screen.
    /// Returns the names only (already sorted by position on the
    /// backend, so "Meeting" lands first).
    func listActivitySubjects() async -> [String] {
        // Codable (Encodable + Decodable) because the project's
        // generic `get<T: Codable>` requires both — even though we
        // only ever decode the response, the constraint enforces it.
        struct SubjectRow: Codable { let name: String; let is_active: Bool? }
        struct Wrap: Codable { let success: Bool?; let data: [SubjectRow]? }
        do {
            let r: Wrap = try await get("/api/v1/crm/activity-subjects")
            return (r.data ?? [])
                .filter { ($0.is_active ?? true) }
                .map(\.name)
        } catch {
            return []
        }
    }

    /// Wire-shape of `/api/v1/crm/analytics/widget-summary`. Kept local
    /// to the service because only the home-screen widget refresh
    /// consumes it; everywhere else uses CRMAnalyticsSummary.
    struct CRMWidgetSummary: Codable {
        let total_leads: Int?
        let total_conversions: Int?
        let conversion_rate: Double?
        let leads_today: Int?
        let leads_week: Int?
        let trend_7d: [Int]?
        let open_deals: Int?
        let won_deals_30d: Int?
        let open_deal_value: Double?
        let refreshed_at: String?
    }

    /// Fetch the widget snapshot and push it into the App Group cache
    /// so the WidgetKit timeline provider repaints with fresh data.
    /// Best-effort; silent on failure (the widget falls back to its
    /// previous cached snapshot until the next call lands).
    ///
    /// Writes the JSON payload directly to the App Group UserDefaults
    /// using the same key + schema the widget extension's
    /// KinematicSharedCache.read() consumes. Inlined here (instead of
    /// calling KinematicSharedCache.write from the widget bundle) so
    /// the host target doesn't need shared target membership on that
    /// type — the App Group is the only contract the two ends share.
    func refreshWidgetCache() async {
        guard !Session.sharedToken.isEmpty else { return }
        do {
            let s: CRMWidgetSummary = try await get("/api/v1/crm/analytics/widget-summary")
            let payload: [String: Any] = [
                "total_leads":       s.total_leads ?? 0,
                "total_conversions": s.total_conversions ?? 0,
                "conversion_rate":   s.conversion_rate ?? 0,
                "leads_today":       s.leads_today ?? 0,
                "leads_week":        s.leads_week ?? 0,
                "trend_7d":          s.trend_7d ?? Array(repeating: 0, count: 7),
                "open_deals":        s.open_deals ?? 0,
                "won_deals_30d":     s.won_deals_30d ?? 0,
                "open_deal_value":   s.open_deal_value ?? 0,
                "refreshed_at":      Date().timeIntervalSince1970,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let store = UserDefaults(suiteName: "group.com.shaggywize63.kinematic") else {
                return
            }
            store.set(data, forKey: "kinematic_widget_summary_v1")
            // Force the widget timeline to repaint immediately instead
            // of waiting for the 30-minute refresh policy.
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            // Best-effort — leave the previous cached snapshot in place.
        }
    }

    func dashboardSummary(from: String? = nil, to: String? = nil) async throws -> CRMAnalyticsSummary {
        var q: [String: String] = [:]
        if let from { q["from"] = from }
        if let to { q["to"] = to }
        // Attach the global city picker so the Champion KPI tiles narrow
        // to the picked region — backend's analyticsScope reads ?city=
        // and intersects it with the caller's assigned set.
        if let c = CRMLocationStore.shared.city, !c.isEmpty { q["city"] = c }
        return try await get("/api/v1/crm/analytics/dashboard-summary", query: q)
    }
    func funnel(pipelineId: String? = nil, from: String? = nil, to: String? = nil) async throws -> [FunnelStageMetric] {
        var q: [String: String] = [:]
        if let pipelineId { q["pipeline_id"] = pipelineId }
        if let from { q["from"] = from }
        if let to { q["to"] = to }
        return try await get("/api/v1/crm/analytics/funnel", query: q)
    }
    func winRate(period: String = "month", from: String? = nil, to: String? = nil) async throws -> [WinRateBucket] {
        var q: [String: String] = ["period": period]
        if let from { q["from"] = from }
        if let to { q["to"] = to }
        return try await get("/api/v1/crm/analytics/win-rate", query: q)
    }
    func forecast(from: String? = nil, to: String? = nil) async throws -> [ForecastPoint] {
        var q: [String: String] = [:]
        if let from { q["from"] = from }
        if let to { q["to"] = to }
        return try await get("/api/v1/crm/analytics/forecast", query: q)
    }

    // MARK: AI shortcuts (other than chat — chat lives in AIChatService)
    func aiScoreLead(id: String) async throws -> LeadScore {
        try await postJSON("/api/v1/crm/ai/score-lead/\(id)", body: [:])
    }
    func aiNextBestAction(dealId: String) async throws -> NextBestAction {
        try await postJSON("/api/v1/crm/ai/next-best-action/\(dealId)", body: [:])
    }
    /// Lead-scoped NBA — works for any lead, converted or not. Decodes into the
    /// same NextBestAction model (the lead payload mirrors the deal one:
    /// action / reason / priority / suggested_when / methodology).
    func aiNextBestActionLead(leadId: String) async throws -> NextBestAction {
        try await postJSON("/api/v1/crm/ai/next-best-action/lead/\(leadId)", body: [:])
    }
    func aiWinProbability(dealId: String) async throws -> WinProbability {
        try await postJSON("/api/v1/crm/ai/win-probability/\(dealId)", body: [:])
    }
    func aiDraftReply(leadId: String?, dealId: String?, contextNote: String?) async throws -> AIDraftReplyResponse {
        var body: [String: Any] = [:]
        if let leadId { body["lead_id"] = leadId }
        if let dealId { body["deal_id"] = dealId }
        if let contextNote { body["context"] = contextNote }
        return try await postJSON("/api/v1/crm/ai/draft-reply", body: body)
    }

    // MARK: Internals

    private var authToken: String? {
        let token = Session.sharedToken
        if !token.isEmpty { return token }
        let raw = UserDefaults.standard.string(forKey: "auth_token") ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var orgId: String? { Session.currentUser?.orgId }

    private func get<T: Codable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let req = try makeRequest(path: path, method: "GET", body: nil, query: query)
        return try await perform(req)
    }

    /// Whitelist of API surfaces that honour `?city=` on the backend.
    /// Matches the dashboard's `CITY_AWARE_CRM_PREFIXES` in api.ts so
    /// every report consistently narrows when the picker changes.
    private static func isCityAwareAnalyticsPath(_ path: String) -> Bool {
        return path.hasPrefix("/api/v1/crm/analytics")
            || path.hasPrefix("/api/v1/crm/dashboard")
            || path.hasPrefix("/api/v1/crm/lead-analytics")
            || path.hasPrefix("/api/v1/crm/reports")
            || path == "/api/v1/crm/leaderboard"
            || path.hasPrefix("/api/v1/crm/targets")
    }

    // MARK: - Lead Updates (Recent Updates timeline)

    func listLeadUpdates(leadId: String) async throws -> [LeadUpdate] {
        try await get("/api/v1/crm/leads/\(leadId)/updates", query: ["limit": "50"])
    }

    @discardableResult
    func addLeadUpdate(leadId: String, body: String) async throws -> LeadUpdate {
        try await postJSON("/api/v1/crm/leads/\(leadId)/updates", body: ["body": body])
    }

    /// Edit an existing update's body. Backend is author-only (non-author
    /// gets 403). Returns the refreshed row so the caller can swap it into
    /// the in-memory timeline.
    @discardableResult
    func editLeadUpdate(leadId: String, updateId: String, body: String) async throws -> LeadUpdate {
        try await sendJSON("/api/v1/crm/leads/\(leadId)/updates/\(updateId)", method: "PATCH", body: ["body": body])
    }

    /// Delete an update. Backend allows the author or an admin (else 403).
    /// The `{ deleted: true }` payload is discarded — callers just remove
    /// the row from the local timeline on success.
    func deleteLeadUpdate(leadId: String, updateId: String) async throws {
        let _: EmptyAck = try await delete("/api/v1/crm/leads/\(leadId)/updates/\(updateId)")
    }

    /// ✨ Suggest — asks KINI to read a draft Update and propose the next CRM
    /// action (an activity to log, a follow-up to draft, quick next steps).
    /// Lightweight single-shot helper that does NOT touch the monthly KINI
    /// chat quota. Returns an `UpdateSuggestion` whose three slots may each be
    /// nil/empty when there's nothing useful to suggest.
    func suggestFromUpdate(leadId: String, draft: String) async throws -> UpdateSuggestion {
        try await postJSON(
            "/api/v1/crm/ai/suggest-from-update",
            body: ["lead_id": leadId, "draft": draft]
        )
    }

    // MARK: - Lead Analytics layout (per-user, synced with web)

    struct AnalyticsLayoutWidget: Codable {
        let id: String
        let widget_type: String
        let chart_type: String?
    }
    private struct AnalyticsLayout: Codable { let widgets: [AnalyticsLayoutWidget]? }

    /// The user's saved Lead Analytics widget layout — the same per-user config
    /// the web "customisable Lead Analytics" page writes to. Empty = not yet
    /// customised.
    func getAnalyticsLayout() async throws -> [AnalyticsLayoutWidget] {
        let layout: AnalyticsLayout = try await get("/api/v1/crm/dashboard-layouts/analytics")
        return layout.widgets ?? []
    }

    /// Persist the chosen widgets (by type, in order). Round-trips to web.
    func saveAnalyticsLayout(types: [String]) async {
        let widgets: [[String: Any]] = types.map {
            ["id": "w_\($0)", "widget_type": $0, "chart_type": "bar", "config": [:]]
        }
        struct Ack: Codable { let widgets: [AnalyticsLayoutWidget]? }
        _ = try? await (sendJSON("/api/v1/crm/dashboard-layouts/analytics", method: "PUT",
                                 body: ["widgets": widgets, "layouts": [:]]) as Ack)
    }

    // MARK: - Notifications (in-app center)

    /// Backend notification feed (stagnant leads, deals closing, tasks overdue,
    /// broadcasts). Detailed title/body + a `data` payload for deep-linking.
    func listNotifications(limit: Int = 50) async throws -> [CRMNotification] {
        try await get("/api/v1/notifications", query: ["limit": String(limit)])
    }

    /// Mark a single notification read. Best-effort: the PATCH is sent before
    /// any decode, so a decode mismatch on the (empty) ack doesn't matter.
    func markNotificationRead(id: String) async {
        struct Ack: Codable { let success: Bool? }
        _ = try? await (sendJSON("/api/v1/notifications/\(id)/read", method: "PATCH", body: [:]) as Ack)
    }

    /// Mark every notification read.
    func markAllNotificationsRead() async {
        struct Ack: Codable { let success: Bool? }
        _ = try? await (sendJSON("/api/v1/notifications/read", method: "PATCH", body: [:]) as Ack)
    }

    /// Permanently delete every notification for the signed-in user (the
    /// "Clear all" action empties the list, not just marks read).
    func clearNotifications() async {
        struct Ack: Codable { let success: Bool? }
        _ = try? await (sendJSON("/api/v1/notifications/clear", method: "DELETE", body: [:]) as Ack)
    }

    private func postJSON<T: Codable>(_ path: String, body: [String: Any]) async throws -> T {
        let data = body.isEmpty
            ? Data("{}".utf8)
            : try JSONSerialization.data(withJSONObject: body, options: [])
        let req = try makeRequest(path: path, method: "POST", body: data)
        return try await perform(req)
    }

    private func sendJSON<T: Codable>(_ path: String, method: String, body: [String: Any]) async throws -> T {
        let data = body.isEmpty
            ? Data("{}".utf8)
            : try JSONSerialization.data(withJSONObject: body, options: [])
        let req = try makeRequest(path: path, method: method, body: data)
        return try await perform(req)
    }

    private func delete<T: Codable>(_ path: String) async throws -> T {
        let req = try makeRequest(path: path, method: "DELETE", body: nil)
        return try await perform(req)
    }

    private func makeRequest(path: String, method: String, body: Data?, query: [String: String] = [:]) throws -> URLRequest {
        guard let token = authToken else { throw CRMServiceError.missingAuth }
        // Auto-attach the global CRM city picker to GETs on the
        // analytics / dashboard surfaces so every chart, summary, and
        // report respects the picker the same way it does on web.
        // Callers that already set `city` keep priority (e.g. the
        // generic Reports Hub forwards the spec's explicit city).
        var effectiveQuery = query
        if method == "GET",
           effectiveQuery["city"] == nil,
           let pickedCity = CRMLocationStore.shared.city, !pickedCity.isEmpty,
           Self.isCityAwareAnalyticsPath(path) {
            effectiveQuery["city"] = pickedCity
        }
        var components = URLComponents(url: baseHost.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !effectiveQuery.isEmpty {
            components?.queryItems = effectiveQuery.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw CRMServiceError.server("Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let orgId { req.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        // Org-level admins who picked a client on the dashboard scope every CRM
        // call to that tenant (mirrors the dashboard's X-Client-Id header).
        // Client-pinned users leave this nil → backend uses their JWT claim.
        if let cid = CRMClientScope.selectedClientId(), !cid.isEmpty {
            req.setValue(cid, forHTTPHeaderField: "X-Client-Id")
        }
        // Multi-project routing — target the Supabase project resolved from the
        // user's email at login. Absent for Tata (default) → unchanged.
        if let proj = Session.project, !proj.isEmpty {
            req.setValue(proj, forHTTPHeaderField: "X-Kinematic-Project")
        }
        req.httpBody = body
        req.timeoutInterval = 30
        return req
    }

    /// Page of leads + the server's total count, so the list can show the real
    /// total and load every lead (the API caps each page at 200).
    func listLeadsPage(page: Int, status: String? = nil, search: String? = nil, city: String? = nil, state: String? = nil,
                       from: String? = nil, to: String? = nil, scoreGrade: String? = nil, scoreGte: Int? = nil,
                       lifecycle: String? = nil, isConverted: Bool? = nil, ownerId: String? = nil,
                       sourceId: String? = nil, sort: String? = nil, order: String? = nil) async throws -> (leads: [Lead], total: Int) {
        var q: [String: String] = ["page": String(page), "limit": "200"]
        if let status { q["status"] = status }
        if let search { q["q"] = search }
        if let city { q["city"] = city }
        if let state { q["state"] = state }
        if let from { q["from"] = from }
        if let to { q["to"] = to }
        if let scoreGrade { q["score_grade"] = scoreGrade }
        if let scoreGte { q["score_gte"] = String(scoreGte) }
        if let lifecycle { q["lifecycle_stage"] = lifecycle }
        if let isConverted { q["is_converted"] = isConverted ? "true" : "false" }
        if let ownerId { q["owner_id"] = ownerId }
        if let sourceId { q["source_id"] = sourceId }
        if let sort { q["sort"] = sort }
        if let order { q["order"] = order }
        let req = try makeRequest(path: "/api/v1/crm/leads", method: "GET", body: nil, query: q)
        let data = try await fetchData(req)
        let env = try decoder.decode(APIEnvelope<[Lead]>.self, from: data)
        let rows = env.data ?? []
        return (rows, env.pagination?.total ?? rows.count)
    }

    /// Shared HTTP + 401-refresh-and-replay + error-mapping. Returns the raw
    /// body so callers can decode the full envelope (e.g. to read pagination).
    private func fetchData(_ req: URLRequest, retryAfterRefresh: Bool = true) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CRMServiceError.badResponse(0)
        }
        if http.statusCode == 401, retryAfterRefresh {
            let refreshed = await KinematicRepository.shared.refreshAccessToken()
            if refreshed {
                var retry = req
                retry.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
                return try await fetchData(retry, retryAfterRefresh: false)
            }
        }
        if !(200..<300).contains(http.statusCode) {
            if let env = try? decoder.decode(APIEnvelope<EmptyAck>.self, from: data),
               let msg = env.error ?? env.message {
                throw CRMServiceError.server(msg)
            }
            throw CRMServiceError.badResponse(http.statusCode)
        }
        return data
    }

    private func perform<T: Codable>(_ req: URLRequest, retryAfterRefresh: Bool = true) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CRMServiceError.badResponse(0)
        }
        // 401 → silently refresh the access token and replay once, so the
        // user stays signed in across the ~1h Supabase access-token expiry
        // without ever seeing a re-login prompt. We never auto-logout from
        // here — that only happens when the user explicitly hits Sign Out.
        if http.statusCode == 401, retryAfterRefresh {
            let refreshed = await KinematicRepository.shared.refreshAccessToken()
            if refreshed {
                // Rebuild the request with the freshly-rotated Bearer token.
                var retry = req
                retry.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
                return try await perform(retry, retryAfterRefresh: false)
            }
        }
        if !(200..<300).contains(http.statusCode) {
            if let env = try? decoder.decode(APIEnvelope<EmptyAck>.self, from: data),
               let msg = env.error ?? env.message {
                throw CRMServiceError.server(msg)
            }
            throw CRMServiceError.badResponse(http.statusCode)
        }
        // Try envelope first.
        if let env = try? decoder.decode(APIEnvelope<T>.self, from: data), let payload = env.data {
            return payload
        }
        // Try raw decode.
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CRMServiceError.decodeFailed(String(describing: error))
        }
    }
}

/// Used as a placeholder when we don't care about the response payload.
struct EmptyAck: Codable {}

/// Shared authenticated URLSession call used by every CRM HTTP path
/// (CRMService + its extensions). Handles silent refresh-on-401 once so
/// CRM screens never get kicked out mid-session — mirrors what the main
/// `KinematicRepository.performRequest` does for field-ops endpoints.
enum CRMHTTP {
    static func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            let refreshed = await KinematicRepository.shared.refreshAccessToken()
            if refreshed {
                var retry = req
                retry.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
                return try await URLSession.shared.data(for: retry)
            }
        }
        return (data, response)
    }
}
