//
//  RatePrompt.swift
//  Kinematic
//
//  The rate-the-app prompt ("Enjoying Kinematic?" -> the system review request): when it may appear and what is
//  remembered between sessions. Pure Swift, unit-tested (see KinematicTests/RatePromptTests). Mirrors the Android
//  `RatePrompt`; the session rules (only from Home, once per session) are in `RatePromptCoordinator`.
//
//  Opt-in per client BY DATA: nothing is counted and nothing is shown unless the client's `app_ui_config.features` has
//  `rate_prompt: true` (`featureId`, `ClientFeatures.featureOn`). Everything is remembered PER DEVICE, so none of it is
//  cleared when somebody signs out.
//
//  It is offered only after the app has proved useful to the rep: installed for at least `minInstallDays` days (the
//  stored first-launch date), opened on at least `minOpenDays` different days, and at least `minPositiveMoments` good
//  moments (a successful online check-out, a form that reached the server). It is never asked after the rep rated or
//  said "Don't ask again", at most `maxPrompts` times in all, and not again within `minDaysBetweenPrompts` days of the
//  last "Maybe later".
//

import Foundation

enum RatePrompt {

    /// The key in `app_ui_config.features`.
    static let featureId: String = "rate_prompt"

    static let minInstallDays: Int = 3
    static let minOpenDays: Int = 3
    static let minPositiveMoments: Int = 2
    static let maxPrompts: Int = 3
    static let minDaysBetweenPrompts: Int = 30

    /// Counters stop growing here; nothing needs a larger number.
    private static let countCap: Int = 1000

    private static let dayMs: Int64 = 24 * 60 * 60 * 1000

    /// Where the rep's answer left things.
    enum State: String, CaseIterable {
        case undecided = "NONE"
        case rated = "RATED"
        case never = "NEVER"
    }

    /// What is remembered.
    ///  • `openDays` / `lastOpenDay`: how many different days the app was opened, and the latest one (`yyyy-MM-dd`, the device's own day);
    ///  • `positives`: good moments so far;
    ///  • `prompts` / `lastPromptAtMs`: how many times the dialog was answered with "Maybe later", and when last (0 = never);
    ///  • `state`: `.undecided` until the rep rated ("Rate now" / the Settings row) or chose "Don't ask again".
    struct Record: Equatable {
        var state: State = .undecided
        var openDays: Int = 0
        var lastOpenDay: String = ""
        var positives: Int = 0
        var prompts: Int = 0
        var lastPromptAtMs: Int64 = 0
    }

    /// Milliseconds since 1970 of `date`.
    static func ms(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: the rules

    /// May the dialog be shown now? Every condition must hold: the feature is on; the rep has not rated or opted out; the
    /// app has been installed for at least 3 days (`installMs` = the first-launch time; unknown = no); opened on at
    /// least 3 different days; at least 2 good moments; fewer than 3 prompts so far; and the last "Maybe later" at
    /// least 30 days ago.
    static func eligible(featureOn: Bool, record: Record, installMs: Int64?, nowMs: Int64) -> Bool {
        if !featureOn { return false }
        if record.state != .undecided { return false }
        guard let install = installMs else { return false }
        if nowMs - install < Int64(minInstallDays) * dayMs { return false }
        if record.openDays < minOpenDays { return false }
        if record.positives < minPositiveMoments { return false }
        if record.prompts >= maxPrompts { return false }
        if record.lastPromptAtMs > 0 && nowMs - record.lastPromptAtMs < Int64(minDaysBetweenPrompts) * dayMs { return false }
        return true
    }

    // MARK: the counters

    /// The device's own calendar day of `ms`, `yyyy-MM-dd`.
    static func dayOf(ms: Int64, timeZone: TimeZone = .current) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        guard let parts = FormFieldLogic.parts(of: date, timeZone: timeZone) else { return "" }
        return FormFieldLogic.formatDate(parts.date)
    }

    /// The app was opened on `day`: one more different day, unless it is the day already counted last (or the rep has
    /// answered for good).
    static func noteOpen(_ r: Record, day: String) -> Record {
        if r.state != .undecided || day.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || day == r.lastOpenDay { return r }
        var out = r
        out.openDays = min(r.openDays + 1, countCap)
        out.lastOpenDay = day
        return out
    }

    /// A good moment happened (a successful online check-out / a form that reached the server).
    static func notePositive(_ r: Record) -> Record {
        if r.state != .undecided { return r }
        var out = r
        out.positives = min(r.positives + 1, countCap)
        return out
    }

    /// "Maybe later" (or the dialog dismissed): counts as a prompt and starts the 30-day wait.
    static func maybeLater(_ r: Record, nowMs: Int64) -> Record {
        if r.state != .undecided { return r }
        var out = r
        out.prompts = min(r.prompts + 1, countCap)
        out.lastPromptAtMs = nowMs
        return out
    }

    /// "Rate now" (or the Settings row): never ask again.
    static func rated(_ r: Record) -> Record {
        if r.state != .undecided { return r }
        var out = r
        out.state = .rated
        return out
    }

    /// "Don't ask again".
    static func never(_ r: Record) -> Record {
        if r.state != .undecided { return r }
        var out = r
        out.state = .never
        return out
    }

    /// Did a submitted form reach the server, as opposed to being only saved for later? The offline queue grows when a
    /// submit is held back, so a queue that did not grow means the form went through (`pendingBefore` / `pendingAfter`
    /// = the queue's size before and after the submit).
    static func formReachedServer(pendingBefore: Int, pendingAfter: Int) -> Bool {
        pendingAfter <= pendingBefore
    }

    // MARK: storage

    private static let version: String = "v1"

    /// The record as one short string: `v1;STATE;openDays;lastOpenDay;positives;prompts;lastPromptAtMs`.
    static func encode(_ r: Record) -> String {
        [version, r.state.rawValue, String(r.openDays), r.lastOpenDay, String(r.positives), String(r.prompts), String(r.lastPromptAtMs)]
            .joined(separator: ";")
    }

    private static func clamp(_ n: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(n, lo), hi)
    }

    /// Inverse of `encode`. Anything unreadable (no record, another version, a damaged value) reads as a fresh record.
    static func decode(_ raw: String?) -> Record {
        guard let raw = raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return Record() }
        let p: [String] = raw.split(separator: ";", omittingEmptySubsequences: false).map { String($0) }
        if p.count != 7 || p[0] != version { return Record() }
        guard let state = State(rawValue: p[1]),
              let openDays = Int(p[2]),
              let positives = Int(p[4]),
              let prompts = Int(p[5]),
              let lastPrompt = Int64(p[6]) else { return Record() }
        return Record(
            state: state,
            openDays: clamp(openDays, 0, countCap),
            lastOpenDay: p[3],
            positives: clamp(positives, 0, countCap),
            prompts: clamp(prompts, 0, countCap),
            lastPromptAtMs: max(lastPrompt, 0)
        )
    }
}

/// What the rate prompt remembers on this phone. PER DEVICE: deliberately not cleared at sign-out (`SessionCleanup`
/// leaves these keys alone). `UserDefaults` is a parameter so tests use their own suite.
enum RatePromptStore {
    static let recordKey: String = "rate_prompt_record"
    static let firstLaunchKey: String = "rate_prompt_first_launch_ms"

    static func read(in defaults: UserDefaults = .standard) -> RatePrompt.Record {
        RatePrompt.decode(defaults.string(forKey: recordKey))
    }

    /// Change the record with `transform` (one of the pure transitions in `RatePrompt`); nothing is written when it
    /// changes nothing.
    static func update(in defaults: UserDefaults = .standard, _ transform: (RatePrompt.Record) -> RatePrompt.Record) {
        let current = read(in: defaults)
        let next = transform(current)
        if next != current { defaults.set(RatePrompt.encode(next), forKey: recordKey) }
    }

    /// When this phone first ran the app (ms since 1970), or nil if never recorded.
    static func firstLaunchMs(in defaults: UserDefaults = .standard) -> Int64? {
        guard let n = defaults.object(forKey: firstLaunchKey) as? NSNumber else { return nil }
        let v = n.int64Value
        return v > 0 ? v : nil
    }

    /// Remember the first launch (once). Called as the app starts, whatever the client — so the install age is real if the
    /// client switches the prompt on later.
    static func recordFirstLaunchIfNeeded(now: Date = Date(), in defaults: UserDefaults = .standard) {
        if firstLaunchMs(in: defaults) != nil { return }
        defaults.set(NSNumber(value: RatePrompt.ms(now)), forKey: firstLaunchKey)
    }
}
