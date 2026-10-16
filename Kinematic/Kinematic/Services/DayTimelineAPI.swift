// DayTimelineAPI — thin async wrapper over GET /api/v1/attendance/daily-report (and /team) for the Timeline screen
// (module `timeline`). Mirrors ExpensesAPI: a dedicated client, the server's own message on a failure, client scoping by
// the authenticated user (JWT). The replies are read by DayTimelineParser (forgiving: envelope or bare payload).

import Foundation

enum DayTimelineAPIError: Error, LocalizedError {
    case http(Int, String?)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .http(let status, let message): return DayTimelineAPI.message(serverMessage: message, status: status)
        case .unreadable:                    return "The timeline could not be read. Try again."
        }
    }
}

struct DayTimelineAPI {
    static let shared = DayTimelineAPI()
    private let baseURL = "https://api.kinematicapp.com/api/v1"

    /// What to show: the server's own words (written for the user, e.g. "You can only view your own travel report"),
    /// else a plain line per status.
    static func message(serverMessage: String?, status: Int) -> String {
        if let m = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { return m }
        switch status {
        case 401: return "Your session has expired — sign in again."
        case 403: return "You don't have permission to view this."
        case 404: return "That person could not be found."
        case 500...599: return "The server had a problem. Try again in a moment."
        default: return "Request failed (\(status))"
        }
    }

    /// `?date=…&user_id=…` (either may be absent); "" when both are. Internal so a test can pin it.
    static func query(date: String?, userId: String?) -> String {
        var items: [URLQueryItem] = []
        if let d = date, !d.isEmpty { items.append(URLQueryItem(name: "date", value: d)) }
        if let u = userId, !u.isEmpty { items.append(URLQueryItem(name: "user_id", value: u)) }
        if items.isEmpty { return "" }
        var comps = URLComponents()
        comps.queryItems = items
        guard let q = comps.percentEncodedQuery, !q.isEmpty else { return "" }
        return "?" + q
    }

    /// Internal (not private) only so a test can pin the cache policy of the request it builds.
    func makeRequest(_ path: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw DayTimelineAPIError.unreadable }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        // Always ask the server: a day changes as the person moves, and the shared URL cache keys an entry by URL alone
        // (not by who is signed in).
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 30
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        if let proj = Session.project, !proj.isEmpty { req.setValue(proj, forHTTPHeaderField: "X-Kinematic-Project") }
        if let orgId = Session.currentUser?.orgId { req.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        return req
    }

    private func get(_ path: String) async throws -> AnyJSON? {
        let req = try makeRequest(path)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            throw DayTimelineAPIError.http(status, ExpenseErrors.serverMessage(in: data))
        }
        return try? JSONDecoder().decode(AnyJSON.self, from: data)
    }

    /// One person's day. `date` = `yyyy-MM-dd` (India day; nil = today on the server); `userId` = a teammate (manager
    /// roles only — a rep gets 403), nil = the caller.
    func dailyReport(date: String?, userId: String?) async throws -> DayReportData {
        let json = try await get("/attendance/daily-report" + DayTimelineAPI.query(date: date, userId: userId))
        guard let report = DayTimelineParser.dailyReport(from: json) else { throw DayTimelineAPIError.unreadable }
        return report
    }

    /// The people with a shift on `date` (supervisor and above).
    func team(date: String?) async throws -> [TeamDayRow] {
        let json = try await get("/attendance/daily-report/team" + DayTimelineAPI.query(date: date, userId: nil))
        guard let rows = DayTimelineParser.teamReport(from: json) else { throw DayTimelineAPIError.unreadable }
        return rows
    }
}
