// OutletPickerLogic — what the outlet picker shows for a row, how a typed query narrows rows, and what "Book Order"
// opens for the outlet picked, as pure functions so they are unit-tested (see KinematicTests/OutletPickerLogicTests).
// Mirrors the Android `OutletPicker` helpers.
//
// The server does the real search (`GET /salesman/outlets?search=&limit=` — name / code, today's route-plan outlets
// first). The local filter only narrows the PREVIOUS answer while the next one is still on its way, so typing feels
// instant; the answer for the current query is always shown as the server sent it.

import Foundation

enum OutletPickerLogic {

    /// Page size asked of the server (it caps at 100).
    static let pageSize = 50

    static let offlineMessage = "No connection — connect to the internet to search outlets."

    static func failedMessage(_ reason: String) -> String { "Could not load outlets. " + reason }

    static func emptyMessage(forQuery raw: String) -> String {
        if let query = normalizedQuery(raw) { return "No outlets match \"\(query)\"." }
        return "No outlets available."
    }

    // MARK: - A row

    /// The outlet's name, else its code, else its id.
    static func displayName(_ outlet: SalesmanOutlet) -> String {
        if let name = DistributionQueuePolicy.nonBlank(outlet.name) { return name }
        if let code = DistributionQueuePolicy.nonBlank(outlet.code) { return code }
        return outlet.id
    }

    /// "CODE · City" — whichever of the two the server sent; empty when neither.
    static func subtitle(_ outlet: SalesmanOutlet) -> String {
        var parts: [String] = []
        if let code = DistributionQueuePolicy.nonBlank(outlet.code) { parts.append(code) }
        if let city = DistributionQueuePolicy.nonBlank(outlet.city) { parts.append(city) }
        return parts.joined(separator: " · ")
    }

    /// The second line of a row: the subtitle and the distributor's name; empty when there is neither.
    static func detailLine(_ outlet: SalesmanOutlet) -> String {
        var parts: [String] = []
        let sub = subtitle(outlet)
        if !sub.isEmpty { parts.append(sub) }
        if let distributor = DistributionQueuePolicy.nonBlank(outlet.distributorName) { parts.append(distributor) }
        return parts.joined(separator: " · ")
    }

    /// "₹12,500 due" when the outlet owes at least a rupee; nil otherwise (including an unknown balance).
    static func dueLabel(_ outlet: SalesmanOutlet) -> String? {
        guard let balance = outlet.outstandingBalance, balance.isFinite, balance.rounded() >= 1 else { return nil }
        return DistributionMoney.rupees(balance, decimals: false) + " due"
    }

    // MARK: - What Book Order opens

    /// What the order cart needs for the outlet picked: the outlet, its name (blank → the code → none) and its
    /// distributor (blank → none; the server then resolves it from the outlet).
    struct OrderTarget: Equatable {
        let outletId: String
        let outletName: String?
        let distributorId: String?
    }

    static func orderTarget(for outlet: SalesmanOutlet) -> OrderTarget {
        OrderTarget(outletId: outlet.id,
                    outletName: DistributionQueuePolicy.nonBlank(outlet.name) ?? DistributionQueuePolicy.nonBlank(outlet.code),
                    distributorId: DistributionQueuePolicy.nonBlank(outlet.distributorId))
    }

    // MARK: - The query

    /// The query as it goes to the server: trimmed, nil when blank.
    static func normalizedQuery(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Does `outlet` match the typed text (name, code, city or distributor; case and accents ignored)? A blank
    /// query matches everything.
    static func matches(_ outlet: SalesmanOutlet, query raw: String) -> Bool {
        guard let query = normalizedQuery(raw) else { return true }
        let fields: [String?] = [outlet.name, outlet.code, outlet.city, outlet.distributorName]
        return fields.contains { (field: String?) -> Bool in
            guard let field = field else { return false }
            return field.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static func filter(_ outlets: [SalesmanOutlet], query raw: String) -> [SalesmanOutlet] {
        if normalizedQuery(raw) == nil { return outlets }
        return outlets.filter { (outlet: SalesmanOutlet) -> Bool in matches(outlet, query: raw) }
    }

    /// The rows to show: the server's answer when it is for the current query; while that answer is still on its
    /// way, the previous answer narrowed locally. `resultsQuery` is the normalized query the held rows were fetched
    /// for (nil = the empty query).
    static func displayed(results: [SalesmanOutlet], resultsQuery: String?, currentQuery: String) -> [SalesmanOutlet] {
        if normalizedQuery(currentQuery) == resultsQuery { return results }
        return filter(results, query: currentQuery)
    }
}
