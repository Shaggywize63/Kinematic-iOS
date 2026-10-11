//
//  CustomFieldInput.swift
//  Kinematic
//
//  The input rules of the CRM custom fields (`CustomFieldsSection`), kept apart from the views so they are unit-tested
//  (see KinematicTests/CustomFieldInputTests). Mirrors the Android `CrmDateTime` and the "proper inputs" changes of the
//  CRM custom-field forms: a `datetime` field picks a day AND a time, a long answer gets a multi-line box, a `number` /
//  `currency` field takes digits and one decimal point only.
//
//  Built-in lead / contact / deal / account fields are NOT touched here: these are the admin-defined custom fields
//  (stored in the `custom_fields` jsonb), so the built-in field-override gate does not apply to them.
//

import Foundation

/// The date-and-time rules of the CRM `datetime` custom field.
///
/// The stored value stays what it always was: an ISO instant in UTC, `yyyy-MM-dd'T'HH:mm:ss'Z'` (the old picker
/// stamped the moment it was set; the new one stores the day and time the rep picked, on their own clock, converted to
/// UTC with zero seconds). A value written by another client (a bare date, an offset, fractions of a second) still reads.
enum CrmDateTime {

    private static func utcMidnight(_ d: FormDay) -> Date? {
        var comps = DateComponents()
        comps.year = d.year
        comps.month = d.month
        comps.day = d.day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return utc.date(from: comps)
    }

    /// The moment a stored value stands for. Reads an ISO instant (`Z`, an offset, fractions of a second), a timestamp with
    /// no zone (taken as UTC) and a bare `yyyy-MM-dd` (midnight UTC, as the old date picker stored it). Nil when
    /// blank or unreadable.
    static func parseDate(_ raw: String?) -> Date? {
        let s: String = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if let d = ActivityFeedLogic.parseDate(s) { return d }
        if s.count == 10, let day = FormFieldLogic.parseDate(s) { return utcMidnight(day) }
        return nil
    }

    /// The moment of `parts` on the clock of `timeZone`, as the stored string: `yyyy-MM-dd'T'HH:mm:ss'Z'` in UTC. Nil
    /// when the parts are not a real moment.
    static func store(_ parts: FormDateTimeParts, timeZone: TimeZone = .current) -> String? {
        guard let moment = FormFieldLogic.moment(day: parts.date, hour: parts.hour, minute: parts.minute, timeZone: timeZone) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: moment)
    }

    /// The day and time on the clock of `timeZone` a stored value stands for (to open the pickers on), or nil.
    static func localParts(_ raw: String?, timeZone: TimeZone = .current) -> FormDateTimeParts? {
        guard let d = parseDate(raw) else { return nil }
        return FormFieldLogic.parts(of: d, timeZone: timeZone)
    }

    /// What the field shows for a stored value, on the clock of `timeZone`: `11 Oct 2026, 4:30 PM`; empty for no value;
    /// the stored text itself when it cannot be read.
    static func display(_ raw: String?, timeZone: TimeZone = .current) -> String {
        let s: String = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        guard let p = localParts(s, timeZone: timeZone) else { return s }
        return FormFieldLogic.friendlyDateTime(p.date, hour: p.hour, minute: p.minute)
    }
}

enum CustomFieldInput {

    /// What a number / currency box keeps of what was typed or pasted: digits and at most one decimal point (the first).
    static func numeric(_ raw: String) -> String {
        var out: String = ""
        var seenDot: Bool = false
        for ch in raw {
            if ch.isASCII && ch.isNumber {
                out.append(ch)
            } else if ch == "." && !seenDot {
                seenDot = true
                out.append(ch)
            }
        }
        return out
    }

    /// Is this custom-field type a long answer (a multi-line box)?
    static func isLongText(_ fieldType: String) -> Bool {
        switch fieldType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "longtext", "long_text", "textarea": return true
        default:                                  return false
        }
    }

    /// Is this custom-field type a number box (digits and one decimal point only)?
    static func isNumeric(_ fieldType: String) -> Bool {
        let t: String = fieldType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == "number" || t == "currency"
    }
}
