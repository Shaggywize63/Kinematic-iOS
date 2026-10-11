//
//  FormFieldLogic.swift
//  Kinematic
//
//  The pure rules behind the form-builder question renderer (`FieldCard`) and the two screens that submit a form
//  (`ActivitySubmissionView` for route-plan forms, `AdHocFormFillView` for ad-hoc ones): which control a question
//  gets, how its answer is stored and shown, and what blocks a submit. Both screens call THIS, so they cannot drift
//  apart. Pure Foundation: unit-tested (see KinematicTests/FormFieldLogicTests). Mirrors the Android `FormFieldLogic`.
//
//  Storage formats (what goes to the server in a response `value`):
//    • date      `yyyy-MM-dd`
//    • time      `HH:mm` (24-hour)
//    • datetime  `yyyy-MM-dd'T'HH:mm` (the rep's own clock, no zone)
//    • checkbox with options (multi select): the chosen option values joined with `,`
//    • checkbox without options / consent: `true` / `false`
//    • location  `lat,lng` (six decimals)
//    • rating    the number of stars, `1...max`
//

import Foundation

/// A calendar day as plain numbers (no time zone involved), the way a date answer is stored (`yyyy-MM-dd`).
struct FormDay: Equatable {
    let year: Int
    let month: Int
    let day: Int
}

/// A time of day, the way a time answer is stored (`HH:mm`, 24-hour).
struct FormClock: Equatable {
    let hour: Int
    let minute: Int
}

/// A day and a time on the rep's own clock (`yyyy-MM-dd'T'HH:mm`, no zone).
struct FormDateTimeParts: Equatable {
    let date: FormDay
    let hour: Int
    let minute: Int
}

enum FormFieldLogic {

    // MARK: - which control

    /// The control a question is rendered with. `.other` = an unknown `field_type`: the plain text box it always got.
    enum Kind: Equatable {
        case text, longText, email, phone, number, checkbox, multiSelect, dropdown, yesNo, radio
        case photo, file, signature, rating, date, time, dateTime, location, section, other
    }

    /// The control for a question of builder type `fieldType`. `hasOptions`: the question carries answer options, which
    /// is what makes a builder `checkbox` ("Multi Select") a list of checkboxes instead of one yes/no box.
    static func kindOf(fieldType: String?, hasOptions: Bool) -> Kind {
        let t: String = (fieldType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "text", "short_text":      return .text
        case "textarea", "long_text":   return .longText
        case "email":                   return .email
        case "phone":                   return .phone
        case "number":                  return .number
        case "consent":                 return .checkbox
        case "checkbox":                return hasOptions ? .multiSelect : .checkbox
        case "multi_select":            return .multiSelect
        case "select", "dropdown":      return .dropdown
        case "yes_no":                  return .yesNo
        case "radio":                   return .radio
        case "photo", "image":          return .photo
        case "file":                    return .file
        case "signature":               return .signature
        case "rating":                  return .rating
        case "date":                    return .date
        case "time":                    return .time
        case "datetime":                return .dateTime
        // The builder says `location`; older apps only knew `gps`. Both are the same capture control.
        case "location", "gps":         return .location
        // The builder says `section_header`; older apps only knew `section`.
        case "section", "section_header": return .section
        default:                        return .other
        }
    }

    static func kindOf(_ field: FormField) -> Kind {
        kindOf(fieldType: field.fieldType, hasOptions: !(field.options ?? []).isEmpty)
    }

    // MARK: - visibility

    /// Is the question shown, given the answers so far? Always, unless it depends on another question's answer
    /// (`depends_on_id` / `depends_on_value`) and that answer is not the expected one (case-insensitive). Rendering and
    /// validation both use this, so a question that is not on screen can never block a submit.
    static func isVisible(_ field: FormField, responses: [String: String]) -> Bool {
        guard let depId = field.dependsOnId, !depId.isEmpty else { return true }
        let parent: String = responses[depId] ?? ""
        let expected: String = field.dependsOnValue ?? ""
        return parent.caseInsensitiveCompare(expected) == .orderedSame
    }

    /// The questions that are on screen and ask for an answer (a section header never does).
    static func answerable(_ fields: [FormField], responses: [String: String]) -> [FormField] {
        fields.filter { isVisible($0, responses: responses) && kindOf($0) != .section }
    }

    // MARK: - validation

    enum ProblemKind: Equatable { case missing, phone, email, number }

    /// What blocks the submit: the `kind` of problem on the question labelled `label`.
    struct Problem: Equatable {
        let kind: ProblemKind
        let label: String
    }

    /// What the form shows above the submit button when it cannot be sent.
    struct Banner: Equatable {
        let title: String
        let detail: String
    }

    private static func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isAsciiDigit(_ ch: Character) -> Bool {
        ch.isASCII && ch.isNumber
    }

    private static func isDigits(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { isAsciiDigit($0) }
    }

    /// A plain decimal number: optional sign, digits, optional decimal part. No letters, exponent, thousands separators.
    static func isNumeric(_ raw: String) -> Bool {
        var s: Substring = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if s.first == "+" || s.first == "-" { s = s.dropFirst() }
        if s.isEmpty { return false }
        var digitsBefore: Int = 0
        var digitsAfter: Int = 0
        var seenDot: Bool = false
        for ch in s {
            if ch == "." {
                if seenDot { return false }
                seenDot = true
            } else if isAsciiDigit(ch) {
                if seenDot { digitsAfter += 1 } else { digitsBefore += 1 }
            } else {
                return false
            }
        }
        return digitsBefore > 0 || digitsAfter > 0
    }

    /// Is the answer an unusable phone number? Not ten digits, ignoring any punctuation. Blank = not this check's business.
    static func isInvalidPhone(_ raw: String) -> Bool {
        if raw.isEmpty { return false }
        return raw.filter { isAsciiDigit($0) }.count != 10
    }

    /// Does this question hold an e-mail address (the `email` type OR a text box with the e-mail keyboard)?
    static func isEmailField(_ field: FormField) -> Bool {
        kindOf(field) == .email || trimmed(field.keyboardType).lowercased() == "email"
    }

    /// Does this question hold a phone number (the `phone` type OR a text box with the phone keyboard)?
    static func isPhoneField(_ field: FormField) -> Bool {
        kindOf(field) == .phone || trimmed(field.keyboardType).lowercased() == "phone"
    }

    /// The stored answer of a ticked single checkbox / consent: "true" (also "yes" / "1", which the consent switch reads).
    static func isAffirmative(_ value: String?) -> Bool {
        let v: String = trimmed(value).lowercased()
        return v == "true" || v == "yes" || v == "1"
    }

    /// The stored form of a single checkbox.
    static func checkboxValue(_ on: Bool) -> String { on ? "true" : "false" }

    /// Has a required question NOT been answered?
    ///  • a section header is never required and never answered;
    ///  • a single checkbox / consent is answered only when it is ticked (`"false"` is a stored value, not an answer);
    ///  • anything else is answered when it holds something other than blanks, or (photo / file / signature) has an
    ///    attachment (`hasAsset`: the picture is held outside `responses` until the form is sent).
    static func isMissing(_ field: FormField, value: String?, hasAsset: Bool = false) -> Bool {
        if !field.isRequired { return false }
        switch kindOf(field) {
        case .section:
            return false
        case .checkbox:
            return !isAffirmative(value)
        default:
            return trimmed(value).isEmpty && !hasAsset
        }
    }

    /// Required questions that are on screen and unanswered, in form order.
    static func missingRequired(fields: [FormField], responses: [String: String], hasAsset: (String) -> Bool = { _ in false }) -> [FormField] {
        answerable(fields, responses: responses).filter {
            isMissing($0, value: responses[$0.id], hasAsset: hasAsset($0.id))
        }
    }

    /// The first thing that blocks the submit, or nil. Only questions that are on screen count. Order: a missing
    /// required answer first (in form order), then a bad phone number, then a bad e-mail, then a bad number — each the
    /// first such question in form order. `isEmail` decides whether a non-blank answer is an e-mail address.
    static func firstProblem(
        fields: [FormField],
        responses: [String: String],
        hasAsset: (String) -> Bool = { _ in false },
        isEmail: (String) -> Bool = { FormFieldLogic.looksLikeEmail($0) }
    ) -> Problem? {
        let shown: [FormField] = answerable(fields, responses: responses)
        if let f = shown.first(where: { isMissing($0, value: responses[$0.id], hasAsset: hasAsset($0.id)) }) {
            return Problem(kind: .missing, label: f.label)
        }
        if let f = shown.first(where: { isPhoneField($0) && isInvalidPhone(responses[$0.id] ?? "") }) {
            return Problem(kind: .phone, label: f.label)
        }
        if let f = shown.first(where: { isEmailField($0) && badEmail(responses[$0.id] ?? "", isEmail: isEmail) }) {
            return Problem(kind: .email, label: f.label)
        }
        if let f = shown.first(where: { badNumber($0, responses[$0.id] ?? "") }) {
            return Problem(kind: .number, label: f.label)
        }
        return nil
    }

    private static func badEmail(_ value: String, isEmail: (String) -> Bool) -> Bool {
        !value.isEmpty && !isEmail(value)
    }

    private static func badNumber(_ field: FormField, _ value: String) -> Bool {
        kindOf(field) == .number && !trimmed(value).isEmpty && !isNumeric(value)
    }

    /// The message above the submit button, built from the same rules as `firstProblem`; nil when the form can be sent.
    /// A missing-answer banner names EVERY missing question; the format problems name every offending one.
    static func banner(
        fields: [FormField],
        responses: [String: String],
        hasAsset: (String) -> Bool = { _ in false },
        isEmail: (String) -> Bool = { FormFieldLogic.looksLikeEmail($0) }
    ) -> Banner? {
        let shown: [FormField] = answerable(fields, responses: responses)
        let missing: [FormField] = shown.filter { isMissing($0, value: responses[$0.id], hasAsset: hasAsset($0.id)) }
        if !missing.isEmpty {
            let title: String = "Fill these required field\(missing.count == 1 ? "" : "s") first"
            return Banner(title: title, detail: missing.map { $0.label }.joined(separator: " • "))
        }
        let phones: [FormField] = shown.filter { isPhoneField($0) && isInvalidPhone(responses[$0.id] ?? "") }
        if !phones.isEmpty {
            return Banner(title: "Enter a 10-digit mobile number", detail: phones.map { $0.label }.joined(separator: " • "))
        }
        let mails: [FormField] = shown.filter { isEmailField($0) && badEmail(responses[$0.id] ?? "", isEmail: isEmail) }
        if !mails.isEmpty {
            return Banner(title: "Enter a valid email address", detail: mails.map { $0.label }.joined(separator: " • "))
        }
        let numbers: [FormField] = shown.filter { badNumber($0, responses[$0.id] ?? "") }
        if !numbers.isEmpty {
            return Banner(title: "Enter a valid number", detail: numbers.map { $0.label }.joined(separator: " • "))
        }
        return nil
    }

    /// Share of the required questions that are on screen and answered, 0...1 (0.5 when nothing is required).
    static func completion(fields: [FormField], responses: [String: String], hasAsset: (String) -> Bool = { _ in false }) -> Double {
        let required: [FormField] = answerable(fields, responses: responses).filter { $0.isRequired }
        if required.isEmpty { return 0.5 }
        let unmet: Int = required.filter { isMissing($0, value: responses[$0.id], hasAsset: hasAsset($0.id)) }.count
        return Double(required.count - unmet) / Double(required.count)
    }

    // The address pattern of Android's matcher: `name@domain.tld`, no spaces, no empty labels.
    private static let emailPattern: String =
        #"^[A-Za-z0-9._%+'\-]+@[A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?)+$"#
    private static let emailRegex: NSRegularExpression? = try? NSRegularExpression(pattern: emailPattern)

    /// `name@domain.tld`: no spaces, no empty labels, no label starting or ending with a hyphen.
    static func looksLikeEmail(_ raw: String) -> Bool {
        guard let regex = emailRegex else { return raw.contains("@") && !raw.contains(" ") }
        let range = NSRange(location: 0, length: raw.utf16.count)
        guard let match = regex.firstMatch(in: raw, options: [], range: range) else { return false }
        return match.range.location == 0 && match.range.length == range.length
    }

    // MARK: - rating

    static let defaultRatingMax: Int = 5
    private static let minRatingMax: Double = 1
    private static let maxRatingMax: Double = 10

    /// How many stars a rating question has: the builder's `validation.max` (`validationMax`, already read as a number),
    /// 5 when it is absent or unreadable, kept within 1...10.
    static func ratingMax(_ validationMax: Double?) -> Int {
        guard let raw = validationMax, raw.isFinite else { return defaultRatingMax }
        let clamped: Double = min(max(raw, minRatingMax), maxRatingMax)
        return Int(clamped)
    }

    // MARK: - options

    /// The label of the option stored as `value`; the stored value itself when no option matches (or has no label).
    static func optionLabel(_ options: [FormOption]?, value: String) -> String {
        guard let option = options?.first(where: { $0.value == value }) else { return value }
        let label: String = option.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? value : option.label
    }

    /// The option values held in a multi-select answer (`a,b,c`), in the order they were chosen, without repeats.
    static func selectedValues(_ raw: String) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for part in raw.split(separator: ",", omittingEmptySubsequences: true) {
            let v: String = String(part)
            if !seen.contains(v) {
                seen.insert(v)
                out.append(v)
            }
        }
        return out
    }

    /// The multi-select answer after ticking / unticking `optionValue`: the same comma-joined option values the old
    /// control wrote, in the order they were chosen (a newly ticked one goes last).
    static func toggleSelected(_ raw: String, optionValue: String, checked: Bool) -> String {
        var list: [String] = selectedValues(raw)
        if checked {
            if !list.contains(optionValue) { list.append(optionValue) }
        } else {
            list.removeAll { $0 == optionValue }
        }
        return list.joined(separator: ",")
    }

    // MARK: - date / time / datetime

    private static let months: [String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func two(_ n: Int) -> String {
        n < 10 ? "0\(n)" : "\(n)"
    }

    private static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11:           return 30
        case 2:                     return isLeap(year) ? 29 : 28
        default:                    return 0
        }
    }

    /// `yyyy-MM-dd` exactly (four-digit year); nil when it is not a real day.
    private static func parseDay(_ s: String) -> FormDay? {
        let parts: [String] = s.split(separator: "-", omittingEmptySubsequences: false).map { String($0) }
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              isDigits(parts[0]), isDigits(parts[1]), isDigits(parts[2]),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        guard y >= 1, m >= 1, m <= 12, d >= 1, d <= daysInMonth(year: y, month: m) else { return nil }
        return FormDay(year: y, month: m, day: d)
    }

    /// `yyyy-MM-dd` from a stored value (also accepts a longer ISO timestamp, whose date part is used); nil when unreadable.
    static func parseDate(_ raw: String?) -> FormDay? {
        let s: String = trimmed(raw)
        if s.count < 10 { return nil }
        return parseDay(String(s.prefix(10)))
    }

    static func formatDate(_ d: FormDay) -> String {
        let y: String = String(d.year)
        let padded: String = String(repeating: "0", count: max(0, 4 - y.count)) + y
        return "\(padded)-\(two(d.month))-\(two(d.day))"
    }

    /// `11 Oct 2026`.
    static func friendlyDate(_ d: FormDay) -> String {
        let m: String = (d.month >= 1 && d.month <= 12) ? months[d.month - 1] : "?"
        return "\(d.day) \(m) \(d.year)"
    }

    /// A time of day from `H:mm`, `HH:mm`, `HH:mm:ss` or `HH:mm:ss.fff`; nil when unreadable or out of range.
    private static func parseClock(_ s: String) -> FormClock? {
        let parts: [String] = s.split(separator: ":", omittingEmptySubsequences: false).map { String($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard parts[0].count == 1 || parts[0].count == 2, isDigits(parts[0]) else { return nil }
        guard parts[1].count == 2, isDigits(parts[1]) else { return nil }
        if parts.count == 3 {
            let sec: [String] = parts[2].split(separator: ".", omittingEmptySubsequences: false).map { String($0) }
            guard sec.count <= 2, sec[0].count == 2, isDigits(sec[0]) else { return nil }
            if sec.count == 2 {
                guard isDigits(sec[1]) else { return nil }
            }
        }
        guard let h = Int(parts[0]), let m = Int(parts[1]), h >= 0, h <= 23, m >= 0, m <= 59 else { return nil }
        return FormClock(hour: h, minute: m)
    }

    static func parseTime(_ raw: String?) -> FormClock? {
        parseClock(trimmed(raw))
    }

    /// The stored form of a time: `HH:mm`, 24-hour.
    static func formatTime(hour: Int, minute: Int) -> String {
        "\(two(hour)):\(two(minute))"
    }

    /// `4:30 PM`: a time the way a person reads it (12-hour).
    static func friendlyTime(hour: Int, minute: Int) -> String {
        let h12: Int = (hour % 12 == 0) ? 12 : (hour % 12)
        return "\(h12):\(two(minute)) \(hour < 12 ? "AM" : "PM")"
    }

    /// What the time field shows for a stored value: `4:30 PM`; empty for no value; the stored text itself when it cannot be read.
    static func timeDisplay(_ raw: String?) -> String {
        let s: String = trimmed(raw)
        if s.isEmpty { return "" }
        if let c = parseClock(s) { return friendlyTime(hour: c.hour, minute: c.minute) }
        return s
    }

    private static func isValidZone(_ zone: String) -> Bool {
        if zone == "Z" { return true }
        guard let first = zone.first, first == "+" || first == "-" else { return false }
        let body: String = String(zone.dropFirst())
        if body.count == 2 || body.count == 4 { return isDigits(body) }
        if body.count == 5 {
            let p: [String] = body.split(separator: ":", omittingEmptySubsequences: false).map { String($0) }
            return p.count == 2 && p[0].count == 2 && p[1].count == 2 && isDigits(p[0]) && isDigits(p[1])
        }
        return false
    }

    /// Splits `yyyy-MM-dd[T ]clock[zone]` into its day, clock and whether a zone suffix was present.
    private static func splitDateTime(_ raw: String?) -> (day: FormDay, clock: FormClock, hasZone: Bool)? {
        let s: String = trimmed(raw)
        guard s.count > 11 else { return nil }
        let chars: [Character] = Array(s)
        guard chars[10] == "T" || chars[10] == " " else { return nil }
        guard let day = parseDay(String(chars[0..<10])) else { return nil }
        let rest: [Character] = Array(chars[11...])
        var clockEnd: Int = rest.count
        for (i, ch) in rest.enumerated() {
            if !(isAsciiDigit(ch) || ch == ":" || ch == ".") {
                clockEnd = i
                break
            }
        }
        let clockText: String = String(rest[0..<clockEnd])
        let zoneText: String = String(rest[clockEnd...]).trimmingCharacters(in: .whitespaces)
        guard let clock = parseClock(clockText) else { return nil }
        if !zoneText.isEmpty && !isValidZone(zoneText) { return nil }
        return (day, clock, !zoneText.isEmpty)
    }

    /// `yyyy-MM-dd'T'HH:mm` -> its parts. Also reads a space instead of the `T`, seconds, and a zone suffix (which is
    /// ignored: the wall-clock time as stored is what is shown). Nil when unreadable.
    static func parseDateTime(_ raw: String?) -> FormDateTimeParts? {
        guard let p = splitDateTime(raw) else { return nil }
        return FormDateTimeParts(date: p.day, hour: p.clock.hour, minute: p.clock.minute)
    }

    /// True when the stored text carries a zone (`Z`, `+05:30` ...).
    static func dateTimeHasZone(_ raw: String?) -> Bool {
        splitDateTime(raw)?.hasZone ?? false
    }

    /// The stored form of a date and time: `yyyy-MM-dd'T'HH:mm`.
    static func formatDateTime(_ d: FormDay, hour: Int, minute: Int) -> String {
        "\(formatDate(d))T\(two(hour)):\(two(minute))"
    }

    /// `11 Oct 2026, 4:30 PM` for a date and time.
    static func friendlyDateTime(_ d: FormDay, hour: Int, minute: Int) -> String {
        "\(friendlyDate(d)), \(friendlyTime(hour: hour, minute: minute))"
    }

    /// What the date-and-time field shows for a stored value; empty for no value; the stored text itself when it cannot be read.
    static func dateTimeDisplay(_ raw: String?) -> String {
        let s: String = trimmed(raw)
        if s.isEmpty { return "" }
        if let p = parseDateTime(s) { return friendlyDateTime(p.date, hour: p.hour, minute: p.minute) }
        return s
    }

    // MARK: - bridge to the system pickers

    /// A Gregorian calendar on `timeZone`: the stored strings are ISO (Gregorian) whatever calendar the phone shows.
    static func gregorian(_ timeZone: TimeZone = .current) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// The moment of `day` at `hour`:`minute` on the clock of `timeZone` (what a `DatePicker` is bound to).
    static func moment(day: FormDay, hour: Int, minute: Int, timeZone: TimeZone = .current) -> Date? {
        var c = DateComponents()
        c.year = day.year
        c.month = day.month
        c.day = day.day
        c.hour = hour
        c.minute = minute
        return gregorian(timeZone).date(from: c)
    }

    /// The day and time on the clock of `timeZone` a `DatePicker` answer stands for.
    static func parts(of date: Date, timeZone: TimeZone = .current) -> FormDateTimeParts? {
        let c = gregorian(timeZone).dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let y = c.year, let mo = c.month, let d = c.day, let h = c.hour, let mi = c.minute else { return nil }
        return FormDateTimeParts(date: FormDay(year: y, month: mo, day: d), hour: h, minute: mi)
    }

    // MARK: - location

    /// The stored form of a captured position: `lat,lng` with six decimals; nil for a position that cannot be real.
    static func formatLatLng(lat: Double, lng: Double) -> String? {
        if lat.isNaN || lng.isNaN { return nil }
        if lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0 { return nil }
        return String(format: "%.6f,%.6f", lat, lng)
    }

    /// What the location field shows for a stored `lat,lng`: `12.971599, 77.594563`; the stored text itself when it is not that shape.
    static func locationDisplay(_ raw: String?) -> String {
        let s: String = trimmed(raw)
        let parts: [String] = s.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
        if parts.count != 2 { return s }
        let a: String = parts[0].trimmingCharacters(in: .whitespaces)
        let b: String = parts[1].trimmingCharacters(in: .whitespaces)
        if Double(a) == nil || Double(b) == nil { return s }
        return a + ", " + b
    }
}
