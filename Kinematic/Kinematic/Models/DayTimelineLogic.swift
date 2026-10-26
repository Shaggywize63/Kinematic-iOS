//
//  DayTimelineLogic.swift
//  Kinematic
//
//  The rules behind the Timeline screen (module `timeline`): which events a day has, in what order, and how they
//  read. Order and numbering mirror the web Daily Travel Report (`buildTimeline` in the dashboard's travelReport.ts)
//  and the Android screen, so a manager looking at the app, the dashboard and Android sees the same day.
//
//  Pure Foundation, no UI — unit-tested without a session.
//

import Foundation

/// The raw value is the tie-break rank: at the same instant a check-in comes first and a check-out last; a leg starts
/// when the previous stop ends.
enum DayTimelineKind: Int {
    case checkin = 0, travel = 1, halt = 2, visit = 3, checkout = 4
}

struct DayTimelineEvent: Equatable, Identifiable {
    let id: String
    let kind: DayTimelineKind
    /// 1-based position in time order.
    let seq: Int
    /// The number a visit or halt carries: they share one count, in time order. nil for the other kinds.
    let marker: Int?
    let start: Date?
    let end: Date?
    /// A travel leg that runs to "now" (the shift is still open).
    let openEnd: Bool
    /// Visits and halts only.
    let minutes: Int?
    /// Travel legs only.
    let km: Double?
    let title: String
    let detail: String
    /// Where it happened, when known — a visit or halt location (opened in Maps).
    let lat: Double?
    let lng: Double?
}

enum DayTimelineLogic {

    // MARK: - The events of a day

    private struct Raw {
        let id: String
        let kind: DayTimelineKind
        let start: Date?
        let end: Date?
        let openEnd: Bool
        let minutes: Int?
        let km: Double?
        let title: String
        let detail: String
        let lat: Double?
        let lng: Double?
    }

    private static func pointLabel(_ p: DayPoint?) -> String {
        let l = (p?.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !l.isEmpty { return l }
        switch p?.kind {
        case "checkin": return "Check-in"
        case "form_checkout", "form_checkin": return "Visit"
        case "checkout": return "Check-out"
        case "now": return "Now"
        default: return "Stop"
        }
    }

    /// Every event of the day in time order: the check-in, each travel leg, each visit, each halt and the check-out.
    /// Ordered by when each STARTS, so a halt in the middle of a long leg appears after that leg's row (the leg began
    /// first) and before the visit that follows it. A day with no attendance has none.
    static func buildTimeline(_ report: DayReportData) -> [DayTimelineEvent] {
        guard report.attendanceId != nil else { return [] }
        var raw: [Raw] = []

        if let t = report.checkin {
            raw.append(Raw(id: "checkin", kind: .checkin, start: t, end: nil, openEnd: false, minutes: nil, km: nil,
                           title: "Check-in", detail: "", lat: nil, lng: nil))
        }
        for (i, l) in report.legs.enumerated() {
            let open = l.to?.kind == "now"
            var suffix = ""
            if l.method == "straight_line" { suffix = " · straight line" }
            else if l.method == "none" { suffix = " · no location" }
            raw.append(Raw(id: "leg-\(l.index)-\(i)", kind: .travel, start: l.from?.at, end: open ? nil : l.to?.at,
                           openEnd: open, minutes: nil, km: l.km, title: "Travel",
                           detail: "\(pointLabel(l.from)) → \(pointLabel(l.to))\(suffix)", lat: nil, lng: nil))
        }
        for (i, v) in report.visits.enumerated() {
            raw.append(Raw(id: "visit-\(v.id)-\(i)", kind: .visit, start: v.arrival, end: v.departure, openEnd: false,
                           minutes: v.minutes, km: nil, title: "Visit", detail: v.label, lat: v.lat, lng: v.lng))
        }
        for (i, h) in report.halts.enumerated() {
            raw.append(Raw(id: "halt-\(h.index)-\(i)", kind: .halt, start: h.start, end: h.end, openEnd: false,
                           minutes: h.minutes, km: nil, title: "Halt",
                           detail: h.points > 0 ? "\(h.points) GPS pings" : "", lat: h.lat, lng: h.lng))
        }
        if let t = report.checkout {
            raw.append(Raw(id: "checkout", kind: .checkout, start: t, end: nil, openEnd: false, minutes: nil, km: nil,
                           title: "Check-out", detail: "", lat: nil, lng: nil))
        }

        // Rows with no readable time sink to the bottom rather than jumping to the top. The original position is the
        // last tie-break, so the order is total and does not depend on the sort being stable.
        let indexed: [(offset: Int, item: Raw)] = raw.enumerated().map { (offset: $0.offset, item: $0.element) }
        let ordered = indexed.sorted { a, b in
            switch (a.item.start, b.item.start) {
            case (nil, nil):
                return a.offset < b.offset
            case (nil, _):
                return false
            case (_, nil):
                return true
            case (let x?, let y?):
                if x != y { return x < y }
                if a.item.kind.rawValue != b.item.kind.rawValue { return a.item.kind.rawValue < b.item.kind.rawValue }
                return a.offset < b.offset
            }
        }

        var marker = 0
        var out: [DayTimelineEvent] = []
        for (i, entry) in ordered.enumerated() {
            let r = entry.item
            var number: Int? = nil
            if r.kind == .visit || r.kind == .halt {
                marker += 1
                number = marker
            }
            out.append(DayTimelineEvent(id: r.id, kind: r.kind, seq: i + 1, marker: number, start: r.start, end: r.end,
                                        openEnd: r.openEnd, minutes: r.minutes, km: r.km, title: r.title,
                                        detail: r.detail, lat: r.lat, lng: r.lng))
        }
        return out
    }

    // MARK: - Formatting (India time)

    private static let ist: TimeZone = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone(secondsFromGMT: 19800) ?? TimeZone(secondsFromGMT: 0)!
    private static let utc: TimeZone = TimeZone(secondsFromGMT: 0)!

    private static func formatter(_ pattern: String, _ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = pattern
        return f
    }

    private static let clock = formatter("h:mm a", ist)
    private static let istDay = formatter("yyyy-MM-dd", ist)
    private static let plainDayIn = formatter("yyyy-MM-dd", utc)
    private static let dayOut = formatter("EEE, d MMM yyyy", utc)

    /// "9:05 AM" in India time; "—" when unknown.
    static func clockText(_ d: Date?) -> String {
        guard let d = d else { return "—" }
        return clock.string(from: d)
    }

    /// "9:05 AM – 9:40 AM", "9:05 AM – now" for a leg still running, or just the start.
    static func rangeText(_ e: DayTimelineEvent) -> String {
        guard let s = e.start else { return "—" }
        if e.openEnd { return "\(clockText(s)) – now" }
        if let end = e.end, end != s { return "\(clockText(s)) – \(clockText(end))" }
        return clockText(s)
    }

    /// "12 min", "1h 05m"; nil for nothing to show.
    static func durationText(_ minutes: Int?) -> String? {
        guard let m = minutes, m >= 0 else { return nil }
        if m < 60 { return "\(m) min" }
        let rest = m % 60
        if rest == 0 { return "\(m / 60)h" }
        return "\(m / 60)h " + (rest < 10 ? "0\(rest)" : "\(rest)") + "m"
    }

    /// "23.4 km" — at most two decimals, no trailing zeros.
    static func kmText(_ km: Double?) -> String {
        let raw = km ?? 0
        let v = raw.isFinite ? (raw * 100).rounded() / 100 : 0
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s + " km"
    }

    /// "7h 30m" from decimal hours; "—" when unknown.
    static func hoursText(_ hours: Double?) -> String {
        guard let h = hours, h.isFinite, abs(h) < 10_000 else { return "—" }
        let total = Int((h * 60).rounded())
        return "\(total / 60)h \(total % 60)m"
    }

    /// "Fri, 16 Oct 2026" from `YYYY-MM-DD`; the input itself when it is not a date.
    static func dayLabel(_ ymd: String) -> String {
        guard let d = plainDayIn.date(from: ymd) else { return ymd }
        return dayOut.string(from: d)
    }

    /// The day before / after `ymd`; `ymd` itself when it is not a date.
    static func shiftDay(_ ymd: String, by days: Int) -> String {
        guard let d = plainDayIn.date(from: ymd) else { return ymd }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        guard let moved = cal.date(byAdding: .day, value: days, to: d) else { return ymd }
        return plainDayIn.string(from: moved)
    }

    /// Today in India as `YYYY-MM-DD`.
    static func today(now: Date = Date()) -> String {
        istDay.string(from: now)
    }

    // MARK: - Who sees the team

    /// The roles that may open another person's day — the server's SUPERVISOR_OR_ABOVE_ROLES (`city-manager` is the
    /// spelling some app builds carry).
    private static let teamRoles: Set<String> = [
        "super_admin", "admin", "main_admin", "sub_admin", "client", "city_manager", "city-manager", "supervisor",
    ]

    /// True when the signed-in role may pick someone else's day. The server enforces it anyway (a rep gets 403 and an
    /// unlisted role an empty team), so this only decides whether the screen offers the Team view at all.
    static func canViewTeam(role: String?) -> Bool {
        let r = (role ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return teamRoles.contains(r)
    }
}
