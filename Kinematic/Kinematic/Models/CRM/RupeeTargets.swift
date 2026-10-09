// RupeeTargets — Sales / Collection rupee targets: the wire types for /api/v1/crm/targets/{types,progress,entries}
// and every decision the screens make, as plain functions so they are unit-tested
// (see KinematicTests/RupeeTargetsTests). The views only render what these decide.
//
// This is separate from the lead-COUNT targets (CRMTarget / TargetsAdminView / the leaderboard), which it
// leaves alone. It is opt-in per client by data: if GET /crm/targets/types answers [] or fails, nothing in the
// app changes.
//
// Responses are wrapped { success, data }. Numbers are decoded leniently (a number or a numeric string),
// because a sum that crosses a database numeric column can arrive either way.

import Foundation

// MARK: - Wire types

/// One configured target type — `GET /crm/targets/types` → `data.types`.
struct RupeeTargetType: Codable, Hashable, Identifiable {
    /// "sales" | "collection" (the key an entry is logged against).
    let key: String
    /// The client's own name for it.
    let label: String
    let metric: String?
    let period: String?
    let unit: String?

    var id: String { key }

    private enum CodingKeys: String, CodingKey { case key, label, metric, period, unit }

    init(key: String, label: String, metric: String? = nil, period: String? = nil, unit: String? = nil) {
        self.key = key; self.label = label; self.metric = metric; self.period = period; self.unit = unit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = try c.decode(String.self, forKey: .key)
        self.key = key
        let l = ((try? c.decodeIfPresent(String.self, forKey: .label)) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        label = l.isEmpty ? RupeeTargets.defaultLabel(for: key) : l
        metric = (try? c.decodeIfPresent(String.self, forKey: .metric)) ?? nil
        period = (try? c.decodeIfPresent(String.self, forKey: .period)) ?? nil
        unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? nil
    }
}

/// `data` of GET /crm/targets/types: `{ types: [...] }`. One unreadable entry is skipped, never the whole list.
struct RupeeTargetTypesPayload: Codable, Hashable {
    let types: [RupeeTargetType]

    private enum CodingKeys: String, CodingKey { case types }
    private struct Lossy: Decodable {
        let value: RupeeTargetType?
        init(from decoder: Decoder) throws { value = try? RupeeTargetType(from: decoder) }
    }

    init(types: [RupeeTargetType]) { self.types = types }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let raw = try? c.decodeIfPresent([Lossy].self, forKey: .types) {
            types = raw.compactMap { $0.value }
        } else {
            types = []
        }
    }
}

/// One type's standing for the current month.
struct RupeeTargetProgressRow: Codable, Hashable, Identifiable {
    let key: String
    let label: String
    /// nil = no target set.
    let target: Double?
    let achieved: Double
    /// The server's own percentage. Not used for display: the app works the percentage out from
    /// achieved ÷ target so the bar and the number can never disagree.
    let pct: Double?
    let source: String?

    var id: String { key }

    private enum CodingKeys: String, CodingKey { case key, label, target, achieved, pct, source }

    init(key: String, label: String, target: Double?, achieved: Double, pct: Double? = nil, source: String? = nil) {
        self.key = key; self.label = label; self.target = target; self.achieved = achieved; self.pct = pct; self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = try c.decode(String.self, forKey: .key)
        self.key = key
        let l = ((try? c.decodeIfPresent(String.self, forKey: .label)) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        label = l.isEmpty ? RupeeTargets.defaultLabel(for: key) : l
        target = c.rupeeDouble(.target)
        achieved = c.rupeeDouble(.achieved) ?? 0
        pct = c.rupeeDouble(.pct)
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil
    }
}

/// `data` of GET /crm/targets/progress — the caller's own current month (IST).
struct RupeeTargetProgress: Codable, Hashable {
    /// "YYYY-MM-DD"
    let periodStart: String?
    let periodEnd: String?
    let types: [RupeeTargetProgressRow]

    private enum CodingKeys: String, CodingKey { case periodStart = "period_start", periodEnd = "period_end", types }
    private struct Lossy: Decodable {
        let value: RupeeTargetProgressRow?
        init(from decoder: Decoder) throws { value = try? RupeeTargetProgressRow(from: decoder) }
    }

    init(periodStart: String?, periodEnd: String?, types: [RupeeTargetProgressRow]) {
        self.periodStart = periodStart; self.periodEnd = periodEnd; self.types = types
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        periodStart = (try? c.decodeIfPresent(String.self, forKey: .periodStart)) ?? nil
        periodEnd = (try? c.decodeIfPresent(String.self, forKey: .periodEnd)) ?? nil
        let raw = (try? c.decodeIfPresent([Lossy].self, forKey: .types)) ?? nil
        types = (raw ?? []).compactMap { $0.value }
    }
}

/// One logged sale / collection.
struct RupeeTargetEntry: Codable, Hashable, Identifiable {
    let id: String
    let kind: String
    let amount: Double
    /// "YYYY-MM-DD"
    let entryDate: String?
    let leadId: String?
    let leadName: String?
    let note: String?
    let userId: String?
    let userName: String?
    /// ISO timestamp — the 24-hour delete window runs from here.
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, kind, amount, note
        case entryDate = "entry_date", leadId = "lead_id", leadName = "lead_name"
        case userId = "user_id", userName = "user_name", createdAt = "created_at"
    }

    init(id: String, kind: String, amount: Double, entryDate: String? = nil, leadId: String? = nil, leadName: String? = nil,
         note: String? = nil, userId: String? = nil, userName: String? = nil, createdAt: String? = nil) {
        self.id = id; self.kind = kind; self.amount = amount; self.entryDate = entryDate; self.leadId = leadId
        self.leadName = leadName; self.note = note; self.userId = userId; self.userName = userName; self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = ((try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil) ?? ""
        amount = c.rupeeDouble(.amount) ?? 0
        entryDate = (try? c.decodeIfPresent(String.self, forKey: .entryDate)) ?? nil
        leadId = (try? c.decodeIfPresent(String.self, forKey: .leadId)) ?? nil
        leadName = (try? c.decodeIfPresent(String.self, forKey: .leadName)) ?? nil
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? nil
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? nil
        userName = (try? c.decodeIfPresent(String.self, forKey: .userName)) ?? nil
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? nil
    }
}

private extension KeyedDecodingContainer {
    /// A number, or a numeric string; nil for null / absent / anything else.
    func rupeeDouble(_ key: Key) -> Double? {
        if let d = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil { return d }
        if let s = (try? decodeIfPresent(String.self, forKey: key)) ?? nil { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}

// MARK: - Logic

enum RupeeTargets {
    /// The most one entry may be for.
    static let maxAmount: Double = 1_000_000_000
    static let maxNoteLength = 500
    /// An entry can be deleted by its owner for this long after it was logged (the server enforces it too).
    static let deleteWindow: TimeInterval = 24 * 3600

    // MARK: Names

    static func defaultLabel(for key: String) -> String {
        switch key {
        case "sales":      return "Sales"
        case "collection": return "Collection"
        default:
            let t = key.replacingOccurrences(of: "_", with: " ")
            return t.prefix(1).uppercased() + t.dropFirst()
        }
    }

    /// "Log sale" / "Log collection"; any other type the server adds reads "Log <its label>".
    static func logButtonTitle(key: String, label: String) -> String {
        switch key {
        case "sales":      return "Log sale"
        case "collection": return "Log collection"
        default:           return "Log " + label.lowercased()
        }
    }

    /// The short confirmation after an entry is saved.
    static func confirmation(forKey key: String, label: String) -> String {
        switch key {
        case "sales":      return "Sale logged"
        case "collection": return "Collection logged"
        default:           return label + " logged"
        }
    }

    // MARK: Progress

    static func hasTarget(_ target: Double?) -> Bool {
        guard let t = target else { return false }
        return t.isFinite && t > 0
    }

    /// How full the bar is: achieved ÷ target, held between 0 and 1 (a month that beat its target shows a full
    /// bar, not an overflowing one). 0 when there is no target.
    static func barFraction(achieved: Double, target: Double?) -> Double {
        guard let t = target, hasTarget(t), achieved.isFinite else { return 0 }
        return min(max(achieved / t, 0), 1)
    }

    /// The TRUE percentage of the target reached — it can exceed 100. Nil when no target is set. A figure just
    /// short of the target never rounds up to "100%", so the label and the green "done" state agree.
    static func percent(achieved: Double, target: Double?) -> Int? {
        guard let t = target, hasTarget(t), achieved.isFinite else { return nil }
        let raw = min(max(achieved, 0) / t * 100, 1_000_000_000)    // keeps the Int conversion safe
        if raw >= 100 { return Int(raw.rounded()) }
        return min(99, Int(raw.rounded()))
    }

    static func isComplete(achieved: Double, target: Double?) -> Bool {
        guard let t = target, hasTarget(t), achieved.isFinite else { return false }
        return achieved >= t
    }

    /// One line of the card, ready to draw.
    struct CardRow: Equatable, Identifiable {
        let key: String
        let label: String
        let target: Double?
        let achieved: Double
        /// False when the progress could not be fetched: the label still shows, the numbers do not.
        let hasProgress: Bool
        var id: String { key }

        var barFraction: Double { hasProgress ? RupeeTargets.barFraction(achieved: achieved, target: target) : 0 }
        var percent: Int? { hasProgress ? RupeeTargets.percent(achieved: achieved, target: target) : nil }
        var isComplete: Bool { hasProgress && RupeeTargets.isComplete(achieved: achieved, target: target) }
        var showsBar: Bool { hasProgress && RupeeTargets.hasTarget(target) }

        /// Right-hand figure: "42%", "No target set", or "—" while the progress is unavailable.
        var trailingText: String {
            guard hasProgress else { return "—" }
            if let p = percent { return "\(p)%" }
            return "No target set"
        }

        /// Under the bar: "₹1,25,000 of ₹5,00,000", "₹1,25,000 so far", or a note that it is unavailable.
        var detailText: String {
            guard hasProgress else { return "Progress unavailable right now" }
            if RupeeTargets.hasTarget(target), let t = target {
                return "\(RupeeTargets.inr(achieved)) of \(RupeeTargets.inr(t))"
            }
            return "\(RupeeTargets.inr(achieved)) so far"
        }
    }

    /// The rows of the card: one per CONFIGURED type, in the server's order, named by the server. A type the
    /// progress answer does not mention shows zero with no target.
    static func cardRows(types: [RupeeTargetType], progress: RupeeTargetProgress?) -> [CardRow] {
        types.map { t in
            let p = progress?.types.first { $0.key == t.key }
            let name = (p?.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return CardRow(key: t.key,
                           label: name.isEmpty ? t.label : name,
                           target: p?.target,
                           achieved: p?.achieved ?? 0,
                           hasProgress: progress != nil)
        }
    }

    /// The card exists only for a client that configured at least one type, and only where the home screen
    /// has not been told to hide it (`home.my_targets == false`).
    static func cardVisible(types: [RupeeTargetType], homeVisible: Bool) -> Bool {
        homeVisible && !types.isEmpty
    }

    // MARK: Dates

    private static let dayIn: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let monthOut: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "MMMM yyyy"; return f
    }()

    /// "2026-10-01" → "October 2026"; nil if it is not a date.
    static func monthTitle(periodStart: String?) -> String? {
        guard let s = periodStart, s.count >= 10, let d = dayIn.date(from: String(s.prefix(10))) else { return nil }
        return monthOut.string(from: d)
    }

    /// An ISO-8601 timestamp as the database sends it: with or without fractional seconds (Postgres sends
    /// microseconds, which `ISO8601DateFormatter` won't take as they are), with "Z", "+00:00" or a bare "+00" offset, with a space
    /// instead of the "T", or with no offset at all (taken as UTC). Nil for anything else — including a bare date.
    static func parseTimestamp(_ raw: String?) -> Date? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), s.count > 10 else { return nil }
        if !s.contains("T"), let space = s.range(of: " ") { s.replaceSubrange(space, with: "T") }
        guard let tIdx = s.firstIndex(of: "T") else { return nil }
        let datePart = String(s[..<tIdx])
        var timePart = String(s[s.index(after: tIdx)...])

        // Exactly three fractional digits (the formatter is picky): cut microseconds, pad ".5".
        if let dot = timePart.firstIndex(of: ".") {
            let after = timePart.index(after: dot)
            var end = after
            while end < timePart.endIndex, timePart[end].isASCII, timePart[end].isNumber { end = timePart.index(after: end) }
            let digits = String(timePart[after..<end])
            if digits.count != 3 {
                timePart = String(timePart[..<after]) + String((digits + "000").prefix(3)) + String(timePart[end...])
            }
        }
        // An offset: none → UTC; a bare "+05" → "+05:00".
        if !(timePart.contains("Z") || timePart.contains("+") || timePart.contains("-")) {
            timePart += "Z"
        } else {
            let chars = Array(timePart)
            if chars.count >= 3, chars[chars.count - 3] == "+" || chars[chars.count - 3] == "-",
               chars[chars.count - 2].isNumber, chars[chars.count - 1].isNumber {
                timePart += ":00"
            }
        }
        let normal = datePart + "T" + timePart

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: normal) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: normal)
    }

    /// May this entry be deleted now? Only the person who logged it, and only within 24 hours of logging it
    /// (the server decides in the end and answers 403 otherwise). An entry whose time cannot be read is not offered.
    static func canDelete(createdAt: String?, entryUserId: String?, currentUserId: String?, now: Date) -> Bool {
        if let owner = entryUserId, !owner.isEmpty, let me = currentUserId, !me.isEmpty, owner != me { return false }
        guard let created = parseTimestamp(createdAt) else { return false }
        return now.timeIntervalSince(created) < deleteWindow
    }

    // MARK: Money

    private static let rupees: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        return f
    }()
    private static let rupeesAndPaise: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// "₹1,25,000" — Indian grouping; paise ("₹1,250.50") only when there are some.
    static func inr(_ value: Double) -> String {
        guard value.isFinite else { return "₹0" }
        let cents = (abs(value) * 100).rounded()
        let wholeRupees = cents.truncatingRemainder(dividingBy: 100) == 0
        let f = wholeRupees ? rupees : rupeesAndPaise
        let body = f.string(from: NSNumber(value: cents / 100)) ?? String(Int(cents / 100))
        return (value < 0 && cents > 0 ? "-" : "") + "₹" + body
    }

    // MARK: The amount field

    enum AmountCheck: Equatable {
        case ok(Double)
        case empty
        case notANumber
        case notPositive
        case tooManyDecimals
        case tooLarge
    }

    /// Reads what was typed into the amount field: a number above zero, at most 2 decimal places, at most
    /// ₹1,00,00,00,000. A ₹ sign, spaces and thousands commas are tolerated; a single comma followed by one or
    /// two digits is a decimal comma ("12,50"). The value is returned rounded to the paisa.
    static func parseAmount(_ raw: String) -> AmountCheck {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "₹", with: "")
            .replacingOccurrences(of: " ", with: "")
        if t.isEmpty { return .empty }
        if t.contains(".") {
            t = t.replacingOccurrences(of: ",", with: "")
        } else if t.filter({ $0 == "," }).count == 1, let comma = t.lastIndex(of: ",") {
            let after = t.distance(from: comma, to: t.endIndex) - 1
            if after == 1 || after == 2 { t.replaceSubrange(comma...comma, with: ".") }
            else { t = t.replacingOccurrences(of: ",", with: "") }
        } else {
            t = t.replacingOccurrences(of: ",", with: "")
        }
        let isDigit: (Character) -> Bool = { $0 >= "0" && $0 <= "9" }
        guard !t.isEmpty, t.allSatisfy({ isDigit($0) || $0 == "." }), t.filter({ $0 == "." }).count <= 1, t.contains(where: isDigit) else {
            return .notANumber
        }
        if let dot = t.firstIndex(of: "."), t.distance(from: dot, to: t.endIndex) - 1 > 2 { return .tooManyDecimals }
        guard let v = Double(t), v.isFinite else { return .notANumber }
        if v <= 0 { return .notPositive }
        if v > maxAmount { return .tooLarge }
        return .ok((v * 100).rounded() / 100)
    }

    /// What to tell the person about a rejected amount; nil when it is fine.
    static func message(for check: AmountCheck) -> String? {
        switch check {
        case .ok:              return nil
        case .empty:           return "Enter the amount."
        case .notANumber:      return "Enter a valid amount."
        case .notPositive:     return "The amount must be more than zero."
        case .tooManyDecimals: return "Use at most 2 decimal places."
        case .tooLarge:        return "The amount can't be more than \(inr(maxAmount))."
        }
    }

    /// The note as it is sent: trimmed, cut to 500 characters, nil when blank.
    static func cleanNote(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(maxNoteLength))
    }

    // MARK: Sending

    /// A key that is the same for the same entry and different for a different one, so a retry after a dropped
    /// connection can be recognised by a server that supports `Idempotency-Key` — and an edited entry is never
    /// mistaken for the first. `attempt` is one per opened sheet. (FNV-1a over the entry's fields.)
    static func idempotencyKey(attempt: String, kind: String, amount: Double, leadId: String?, note: String?) -> String {
        let cents = Int64((amount * 100).rounded())
        let material = "\(kind)|\(cents)|\(leadId ?? "")|\(note ?? "")"
        var h: UInt64 = 0xcbf29ce484222325
        for b in material.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return "tgt-\(attempt)-\(String(h, radix: 16))"
    }

    /// What to show when logging or deleting fails. A broken connection says so (the sheet stays open, nothing is
    /// queued); otherwise the server's own message; otherwise `fallback`.
    static func failureMessage(urlErrorCode: URLError.Code?, serverMessage: String?, fallback: String) -> String {
        if let code = urlErrorCode, AttendanceSyncPolicy.isTransient(urlError: code) {
            return "No connection — check your network and try again."
        }
        if let m = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { return m }
        return fallback
    }

    static func failureMessage(for error: Error, fallback: String) -> String {
        if let u = error as? URLError { return failureMessage(urlErrorCode: u.code, serverMessage: nil, fallback: fallback) }
        return failureMessage(urlErrorCode: nil, serverMessage: (error as? LocalizedError)?.errorDescription, fallback: fallback)
    }

    /// The server's refusal of a delete is always about the 24-hour window (or the entry not being yours).
    static let deleteRefused = "Entries can only be deleted by the person who logged them, within 24 hours of logging."

    // MARK: Routes

    /// The rupee-target endpoints are the caller's own figures, not city-scoped like the lead-count target ones,
    /// so the global city picker must not be appended to them.
    static func isRupeeTargetsPath(_ path: String) -> Bool {
        ["/api/v1/crm/targets/types", "/api/v1/crm/targets/progress", "/api/v1/crm/targets/entries"]
            .contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
