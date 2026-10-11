//
//  ActivityFeedLogic.swift
//  Kinematic
//
//  What a "Recent activity" card says (the Activity tab's Work Feed): a title, an optional second line and a time
//  line. Pure, so the choices are unit-tested (see KinematicTests/ActivityFeedLogicTests). Mirrors the Android
//  `ActivityFeedLogic`.
//
//  The title is the most useful name the row has: the server's own best title, else the form's "Customer Name"
//  answer, else the outlet, else the form's name, else "Form Submission". An outlet called "Unknown Store" is the
//  server's stand-in for "no outlet", not a name, so it counts as missing (so does any blank text).
//

import Foundation

enum ActivityFeedLogic {

    /// The name older servers put on a row that has no outlet. Never worth showing.
    static let placeholderStore: String = "Unknown Store"

    /// The title of a row with nothing to name it by.
    static let fallbackTitle: String = "Form Submission"

    /// `raw` trimmed, or nil when it is blank or the "Unknown Store" stand-in.
    private static func usable(_ raw: String?) -> String? {
        let s: String = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s.caseInsensitiveCompare(placeholderStore) == .orderedSame { return nil }
        return s
    }

    /// The card's title, see the file comment for the order.
    static func title(_ item: ActivityFeedItem) -> String {
        if let t = usable(item.title) { return t }
        if let t = usable(item.customerName) { return t }
        if let t = usable(item.outletName) { return t }
        if let t = usable(item.formName) { return t }
        return fallbackTitle
    }

    /// The card's second line: the server's subtitle, else the form's name; nil when there is nothing to add (a line
    /// that only repeats the title is not added).
    static func subtitle(_ item: ActivityFeedItem) -> String? {
        let title: String = Self.title(item)
        if let s = usable(item.subtitle), s.caseInsensitiveCompare(title) != .orderedSame { return s }
        if let f = usable(item.formName), f.caseInsensitiveCompare(title) != .orderedSame { return f }
        return nil
    }

    // MARK: timestamps

    private static func digits(_ chars: [Character], _ from: Int, _ count: Int) -> Int? {
        guard from >= 0, from + count <= chars.count else { return nil }
        var n: Int = 0
        for i in from..<(from + count) {
            guard chars[i].isASCII, let d = chars[i].wholeNumberValue else { return nil }
            n = n * 10 + d
        }
        return n
    }

    /// An API timestamp as a Date: `Z`, an offset (`+05:30`, `+0530`, `+00`) and fractions of a second all read; a
    /// timestamp with no zone is taken as UTC. Nil when unreadable (including an impossible date or offset).
    static func parseDate(_ iso: String?) -> Date? {
        let s: String = (iso ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let c: [Character] = Array(s)
        guard c.count >= 16 else { return nil }
        guard let year = digits(c, 0, 4), c[4] == "-",
              let month = digits(c, 5, 2), c[7] == "-",
              let day = digits(c, 8, 2),
              c[10] == "T" || c[10] == " ",
              let hour = digits(c, 11, 2), c[13] == ":",
              let minute = digits(c, 14, 2) else { return nil }
        var i: Int = 16
        var second: Int = 0
        if i < c.count && c[i] == ":" {
            guard let sec = digits(c, i + 1, 2) else { return nil }
            second = sec
            i += 3
        }
        if i < c.count && c[i] == "." {
            i += 1
            let start = i
            while i < c.count && c[i].isASCII && c[i].isNumber { i += 1 }
            if i == start { return nil }
        }
        while i < c.count && c[i] == " " { i += 1 }
        var offsetSeconds: Int = 0
        if i < c.count {
            if c[i] == "Z" {
                i += 1
            } else if c[i] == "+" || c[i] == "-" {
                let sign: Int = c[i] == "-" ? -1 : 1
                guard let oh = digits(c, i + 1, 2) else { return nil }
                i += 3
                var om: Int = 0
                if i < c.count {
                    if c[i] == ":" { i += 1 }
                    guard let m = digits(c, i, 2) else { return nil }
                    om = m
                    i += 2
                }
                if oh > 18 || om > 59 { return nil }
                offsetSeconds = sign * (oh * 3600 + om * 60)
                if abs(offsetSeconds) > 18 * 3600 { return nil }
            } else {
                return nil
            }
        }
        if i != c.count { return nil }
        guard year >= 1, month >= 1, month <= 12, day >= 1, day <= FormFieldLogic.daysInMonth(year: year, month: month),
              hour <= 23, minute <= 59, second <= 59 else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        guard let local = utc.date(from: comps) else { return nil }
        return local.addingTimeInterval(-TimeInterval(offsetSeconds))
    }

    /// The card's time line, on the clock of `timeZone`: just the time (`04:30 PM`) for something from today, the day and
    /// time (`11 Oct, 04:30 PM`) for anything older (with the year, `11 Oct 2025, 04:30 PM`, when it is not this year).
    /// `--` when the timestamp is missing or unreadable.
    static func timeLine(_ submittedAt: String?, now: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard let at = parseDate(submittedAt) else { return "--" }
        let cal: Calendar = FormFieldLogic.gregorian(timeZone)
        let a = cal.dateComponents([.year, .month, .day], from: at)
        let n = cal.dateComponents([.year, .month, .day], from: now)
        let pattern: String
        if a.year == n.year && a.month == n.month && a.day == n.day {
            pattern = "hh:mm a"
        } else if a.year == n.year {
            pattern = "d MMM, hh:mm a"
        } else {
            pattern = "d MMM yyyy, hh:mm a"
        }
        let f = DateFormatter()
        f.calendar = cal
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f.string(from: at)
    }
}
