//
//  FormVisit.swift
//  Kinematic
//
//  The rules of CHECK-IN / CHECK-OUT ON EVERY FORM, as pure Swift so they are unit-tested (see
//  KinematicTests/FormVisitTests). Mirrors the Android `FormVisit`.
//
//  Opt-in per client BY DATA: everything here only applies when the signed-in user's attendance rules say
//  `form_checkin_required: true` (`AttendanceRulesStore`). With the rule off — or never loaded — `stamp` answers
//  "nothing" and a form is sent exactly as it always was.
//
//  With the rule on, for every form a rep fills:
//   • BEFORE filling, a visit is started: the time and GPS are remembered on the phone (no API call, no photo);
//   • WHEN submitting, the form is stamped with that check-in and a check-out (time + GPS) — the submit IS the
//     check-out. The server derives the time spent from the two times;
//   • the visit is used ONLY when it is THIS form's (`sessionMatches`: same key — the activity id of a route-plan form,
//     `adHocKey` of an ad-hoc one — and same outlet, and recent) and is forgotten once the form is saved.
//

import Foundation

/// A visit that is open: started on one form, closed by that form's submit.
struct FormVisitSession: Codable, Equatable {
    /// Which form: the activity id of a route-plan form, `FormVisit.adHocKey(templateId)` of an ad-hoc one.
    var key: String
    /// The outlet of a route-plan form (nil for an ad-hoc one).
    var outletId: String?
    /// What to call it on screen (the outlet, or the form's name).
    var name: String?
    /// When it was started: an ISO instant (`2026-10-10T04:30:00.000Z`).
    var checkInAt: String
    var lat: Double?
    var lng: Double?
}

enum FormVisit {

    /// Prefix of the key of an ad-hoc form (no outlet, no activity): `adhoc:<templateId>`.
    static let adHocPrefix: String = "adhoc:"

    /// A visit older than this is stale (left behind yesterday): it no longer belongs to the form being filled.
    /// The server also drops a duration over 24 h.
    static let maxSessionAge: TimeInterval = 24 * 60 * 60

    /// The phone clock may sit a little ahead of the time a visit was stamped with.
    static let clockSkew: TimeInterval = 5 * 60

    /// The key of an ad-hoc form. One per template, so a visit started for one form is never used for another.
    static func adHocKey(_ templateId: String?) -> String {
        adHocPrefix + (templateId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isAdHocKey(_ key: String?) -> Bool {
        (key ?? "").hasPrefix(adHocPrefix)
    }

    // MARK: instants and GPS

    /// An instant the way forms send it: `2026-10-10T04:30:00.000Z` (UTC, milliseconds).
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// An ISO instant (with or without fractions of a second) as a Date; nil when blank or unreadable.
    static func parseInstant(_ iso: String?) -> Date? {
        let s: String = (iso ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    /// `"lat,lng"` — the text the form tables store for a GPS point; nil unless both are real numbers.
    static func gps(lat: Double?, lng: Double?) -> String? {
        guard let a = lat, let b = lng, a.isFinite, b.isFinite else { return nil }
        return "\(a),\(b)"
    }

    // MARK: which visit is this form's

    private static func sameId(_ a: String?, _ b: String?) -> Bool {
        let x: String = (a ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let y: String = (b ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return x.caseInsensitiveCompare(y) == .orderedSame
    }

    /// Does `session` belong to THE FORM being filled? `key` is the form's key and `outletId` its outlet (nil for an
    /// ad-hoc form). Both must match (ids compare case-insensitively, a blank outlet equals none), and the visit must be
    /// recent: started no more than `maxSessionAge` ago and not (beyond clock skew) in the future. No visit, an
    /// unreadable start time or another form's visit do not match.
    static func sessionMatches(_ session: FormVisitSession?, key: String?, outletId: String?, now: Date) -> Bool {
        guard let s = session else { return false }
        if !sameId(s.key, key) { return false }
        if !sameId(s.outletId, outletId) { return false }
        guard let started = parseInstant(s.checkInAt) else { return false }
        let age: TimeInterval = now.timeIntervalSince(started)
        return age >= -clockSkew && age <= maxSessionAge
    }

    // MARK: stamping a submission

    /// What a finished visit comes to: when it started and ended and for how long.
    struct Summary: Equatable {
        let checkInAt: String
        let checkOutAt: String
        let checkIn: Date
        let checkOut: Date

        var duration: TimeInterval { checkOut.timeIntervalSince(checkIn) }

        /// Whole minutes, rounded like the server (`round((out - in) / 60000)`).
        var minutes: Int { Int(((duration + 30.0) / 60.0).rounded(.down)) }
    }

    /// The four values a form submission carries, and what to do with the visit afterwards.
    struct Stamp: Equatable {
        var checkInAt: String? = nil
        var checkOutAt: String? = nil
        var checkInGps: String? = nil
        var checkOutGps: String? = nil
        /// Forget the stored visit once the form is saved.
        var clearSession: Bool = false
        /// The visit's start, end and length for the success state; nil when there is no complete visit.
        var summary: Summary? = nil

        /// Nothing stamped, nothing cleared: a form sent as it always was.
        static let empty = Stamp()
    }

    /// Decide the check-in / check-out a form is submitted with. `enabled` false (the rule off or unknown): nothing —
    /// the request is exactly what it always was. `enabled` true: only a visit that matches the form (`key`,
    /// `outletId`) is used; the check-in is that visit's start, the check-out is `now` with the form's own fix
    /// (`lat`, `lng`). With no matching visit there is nothing to close, so nothing is stamped and nothing is cleared.
    static func stamp(enabled: Bool, session: FormVisitSession?, key: String?, outletId: String?,
                      lat: Double?, lng: Double?, now: Date) -> Stamp {
        if !enabled { return .empty }
        guard let own = session, sessionMatches(own, key: key, outletId: outletId, now: now) else { return .empty }
        let outAt: String = iso(now)
        var summary: Summary? = nil
        if let started = parseInstant(own.checkInAt), now >= started {
            summary = Summary(checkInAt: own.checkInAt, checkOutAt: outAt, checkIn: started, checkOut: now)
        }
        return Stamp(checkInAt: own.checkInAt,
                     checkOutAt: outAt,
                     checkInGps: gps(lat: own.lat, lng: own.lng),
                     checkOutGps: gps(lat: lat, lng: lng),
                     clearSession: true,
                     summary: summary)
    }

    // MARK: what the rep reads

    /// Seconds since `checkInAt` at `now` (never negative); nil when the start time is unreadable.
    static func elapsed(checkInAt: String?, now: Date) -> TimeInterval? {
        guard let started = parseInstant(checkInAt) else { return nil }
        return max(0, now.timeIntervalSince(started))
    }

    /// `04:07`, or `1:02:03` from the first hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total: Int = Int(max(0, seconds))
        let h: Int = total / 3600
        let m: Int = (total % 3600) / 60
        let s: Int = total % 60
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        if h > 0 { return "\(h):\(two(m)):\(two(s))" }
        return "\(two(m)):\(two(s))"
    }

    /// The running chip while a visit is open: `On visit · 04:07`. Just `On visit` when the start time is unreadable.
    static func timerLabel(checkInAt: String?, now: Date) -> String {
        guard let secs = elapsed(checkInAt: checkInAt, now: now) else { return "On visit" }
        return "On visit · " + clock(secs)
    }

    /// A length of time in words: `under a minute`, `12 min`, `1 h`, `1 h 5 min`.
    static func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes: Int = Int(((max(0, seconds) + 30.0) / 60.0).rounded(.down))
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        if minutes % 60 == 0 { return "\(minutes / 60) h" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    /// The success state's headline: `Time on visit: 12 min`.
    static func totalLabel(_ summary: Summary) -> String {
        "Time on visit: " + durationLabel(summary.duration)
    }

    /// `10:02 → 10:14` in `timeZone`.
    static func windowLabel(_ summary: Summary, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: summary.checkIn) + " → " + f.string(from: summary.checkOut)
    }
}

// MARK: - Remembering open visits on the phone

/// The open visits of the signed-in person, kept on the phone so a visit survives the app being closed. One entry per
/// form key. Stored as ONE record that names its owner: another person's record is never read, and sign-out removes
/// it (`SessionCleanup`). `UserDefaults` is a parameter so tests use their own suite.
enum FormVisitStore {
    /// The single key the record lives under (`SessionCleanup` removes it at sign-out).
    static let storageKey: String = "form_visit_sessions"

    /// At most this many open visits are kept (the oldest go first).
    static let maxSessions: Int = 20

    private struct Record: Codable {
        var userId: String
        var sessions: [FormVisitSession]
    }

    private static func normalized(_ userId: String?) -> String? {
        let t: String = (userId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Two form keys are the same form when they match ignoring case and stray spaces (like the ids in `sessionMatches`).
    private static func sameKey(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private static func read(in defaults: UserDefaults) -> Record? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    /// The open visits of `userId`; empty for nobody, another person's record, or no record.
    static func sessions(userId: String?, in defaults: UserDefaults = .standard) -> [FormVisitSession] {
        guard let uid = normalized(userId), let record = read(in: defaults), record.userId == uid else { return [] }
        return record.sessions
    }

    /// The open visit of the form with `key`, or nil.
    static func session(forKey key: String, userId: String?, in defaults: UserDefaults = .standard) -> FormVisitSession? {
        sessions(userId: userId, in: defaults).first { sameKey($0.key, key) }
    }

    /// `existing` with `added` put in: it replaces the visit of the same form, visits too old to ever match again are
    /// dropped, and only the newest `maxSessions` are kept. Pure, so it is tested without a UserDefaults.
    static func merged(_ existing: [FormVisitSession], adding added: FormVisitSession, now: Date) -> [FormVisitSession] {
        var list: [FormVisitSession] = existing.filter { s in
            if sameKey(s.key, added.key) { return false }
            guard let started = FormVisit.parseInstant(s.checkInAt) else { return false }
            return now.timeIntervalSince(started) <= FormVisit.maxSessionAge
        }
        list.append(added)
        if list.count > maxSessions { list.removeFirst(list.count - maxSessions) }
        return list
    }

    /// Remember a started visit for `userId` (nothing is stored without a user).
    static func save(_ session: FormVisitSession, userId: String?, now: Date = Date(), in defaults: UserDefaults = .standard) {
        guard let uid = normalized(userId) else { return }
        let current: [FormVisitSession] = sessions(userId: uid, in: defaults)
        let record = Record(userId: uid, sessions: merged(current, adding: session, now: now))
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: storageKey) }
    }

    /// Forget the visit of the form with `key` (the form was saved).
    static func remove(key: String, userId: String?, in defaults: UserDefaults = .standard) {
        guard let uid = normalized(userId) else { return }
        let kept: [FormVisitSession] = sessions(userId: uid, in: defaults).filter { !sameKey($0.key, key) }
        if kept.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(Record(userId: uid, sessions: kept)) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
