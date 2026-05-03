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

enum CRMServiceError: LocalizedError {
    case missingAuth
    case badResponse(Int)
    case decodeFailed(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAuth:        return "Please sign in again."
        case .badResponse(let s): return "Server returned status \(s)."
        case .decodeFailed(let m):return "Could not read server response: \(m)"
        case .server(let msg):    return msg
        }
    }
}

final class CRMService {
    static let shared = CRMService()

    private let baseHost: URL = URL(string: "https://kinematic-production.up.railway.app")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Leads
    func listLeads(status: String? = nil, search: String? = nil) async throws -> [Lead] {
        var q: [String: String] = [:]
        if let status { q["status"] = status }
        if let search { q["q"] = search }
        return try await get("/api/v1/crm/leads", query: q)
    }
    func getLead(id: String) async throws -> Lead { try await get("/api/v1/crm/leads/\(id)") }
    func createLead(_ body: [String: Any]) async throws -> Lead {
        try await postJSON("/api/v1/crm/leads", body: body)
    }
    func updateLead(id: String, body: [String: Any]) async throws -> Lead {
        try await sendJSON("/api/v1/crm/leads/\(id)", method: "PUT", body: body)
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
    func convertLead(id: String, body: [String: Any]) async throws -> Lead {
        try await postJSON("/api/v1/crm/leads/\(id)/convert", body: body)
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
        try await sendJSON("/api/v1/crm/contacts/\(id)", method: "PUT", body: body)
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

    // MARK: Deals
    func listDeals(pipelineId: String? = nil, status: String? = nil) async throws -> [Deal] {
        var q: [String: String] = [:]
        if let pipelineId { q["pipeline_id"] = pipelineId }
        if let status { q["status"] = status }
        return try await get("/api/v1/crm/deals", query: q)
    }
    func getDeal(id: String) async throws -> Deal { try await get("/api/v1/crm/deals/\(id)") }
    func createDeal(_ body: [String: Any]) async throws -> Deal {
        try await postJSON("/api/v1/crm/deals", body: body)
    }
    func moveDealStage(id: String, stageId: String) async throws -> Deal {
        try await postJSON("/api/v1/crm/deals/\(id)/move-stage", body: ["stage_id": stageId])
    }
    func winDeal(id: String, amount: Double? = nil) async throws -> Deal {
        var body: [String: Any] = [:]
        if let amount { body["amount"] = amount }
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
    func dealHistory(id: String) async throws -> [Activity] {
        try await get("/api/v1/crm/deals/\(id)/history")
    }

    // MARK: Pipelines / Stages
    func listPipelines() async throws -> [Pipeline] { try await get("/api/v1/crm/pipelines") }
    func listStages(pipelineId: String) async throws -> [Stage] {
        try await get("/api/v1/crm/stages", query: ["pipeline_id": pipelineId])
    }

    // MARK: Activities / Notes / Tasks
    func listActivities(dealId: String? = nil, leadId: String? = nil) async throws -> [Activity] {
        var q: [String: String] = [:]
        if let dealId { q["deal_id"] = dealId }
        if let leadId { q["lead_id"] = leadId }
        return try await get("/api/v1/crm/activities", query: q)
    }
    func createActivity(_ body: [String: Any]) async throws -> Activity {
        try await postJSON("/api/v1/crm/activities", body: body)
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
        try await sendJSON("/api/v1/crm/tasks/\(id)", method: "PUT", body: ["status": "done"])
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

    // MARK: Campaigns
    func listCampaigns() async throws -> [Campaign] { try await get("/api/v1/crm/campaigns") }
    func createCampaign(_ body: [String: Any]) async throws -> Campaign {
        try await postJSON("/api/v1/crm/campaigns", body: body)
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

    // MARK: Analytics
    func dashboardSummary() async throws -> AnalyticsSummary {
        try await get("/api/v1/crm/analytics/dashboard-summary")
    }
    func funnel(pipelineId: String? = nil) async throws -> [FunnelStageMetric] {
        var q: [String: String] = [:]
        if let pipelineId { q["pipeline_id"] = pipelineId }
        return try await get("/api/v1/crm/analytics/funnel", query: q)
    }
    func winRate(period: String = "month") async throws -> [WinRateBucket] {
        try await get("/api/v1/crm/analytics/win-rate", query: ["period": period])
    }
    func forecast() async throws -> [ForecastPoint] {
        try await get("/api/v1/crm/analytics/forecast")
    }

    // MARK: AI shortcuts (other than chat — chat lives in AIChatService)
    func aiScoreLead(id: String) async throws -> LeadScore {
        try await postJSON("/api/v1/crm/ai/score-lead/\(id)", body: [:])
    }
    func aiNextBestAction(dealId: String) async throws -> NextBestAction {
        try await postJSON("/api/v1/crm/ai/next-best-action/\(dealId)", body: [:])
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
        var components = URLComponents(url: baseHost.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw CRMServiceError.server("Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let orgId { req.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        req.httpBody = body
        req.timeoutInterval = 30
        return req
    }

    private func perform<T: Codable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CRMServiceError.badResponse(0)
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
