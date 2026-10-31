//
//  OfflinePunch.swift
//  Kinematic
//
//  The rules of OFFLINE CHECK-IN / CHECK-OUT, as pure Foundation so they are unit-tested (see
//  KinematicTests/OfflinePunchTests). Mirrors the Android implementation (OfflinePunch.kt / OfflinePunchState.kt).
//
//  Opt-in per client BY DATA: everything here only runs for a client whose attendance rules say
//  `allow_offline_checkin: true` (AttendanceRulesStore.shared.rules.allowOfflineCheckin). For every other client the
//  punch flow is the one the app always had: nothing here is consulted.
//
//  How an opted-in punch travels:
//   1. At the tap the app fixes ONE Idempotency-Key and the capture instant (`capturedAt`) and writes the punch to the
//      attendance queue (AttendanceCache) with the selfie, if any, copied to app-private storage.
//   2. It tries the server inline, sending `captured_at` + the key. If that cannot get through for a connectivity
//      reason (AttendanceSyncPolicy: no network, a timeout, 408 / 429 / 5xx) the row stays queued and the rep is told
//      "Checked in 09:12 — will sync when online".
//   3. The queue replays it with the SAME key and the SAME body: selfie upload first (its URL is stored on the row
//      before it is used), then the POST, a check-in strictly before its check-out. `verdict` says whether the row is
//      done, waits, or is refused for good.
//
//  The server hashes the request body against the Idempotency-Key, so a retry must carry byte-identical content:
//  everything in the body is fixed when the punch is captured; only `?date=` (a query parameter, not hashed) depends on
//  when the request is made.
//

import Foundation

enum OfflinePunch {

    // MARK: kinds

    /// The two punches. `rawValue` is the `kind` stored on a queue row.
    enum Kind: String, Equatable {
        case checkIn = "checkin"
        case checkOut = "checkout"

        /// "Checked in" — used in "Checked in 09:12 — will sync when online".
        var verb: String { self == .checkIn ? "Checked in" : "Checked out" }
        /// "Check-in" — used in labels and failure notices.
        var noun: String { self == .checkIn ? "Check-in" : "Check-out" }
        /// The Idempotency-Key prefix (the one the queue has always used).
        var keyPrefix: String { self == .checkIn ? "att-ci-" : "att-co-" }
    }

    /// A fresh Idempotency-Key. Generate ONCE at the tap and reuse it for the inline attempt and every replay.
    static func newKey(_ kind: Kind) -> String { kind.keyPrefix + UUID().uuidString }

    // MARK: time

    /// Attendance days are India days — the same zone the server uses for `attendance.date` and its `captured_at` check.
    static let istTimeZone: TimeZone = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone(secondsFromGMT: 19_800) ?? TimeZone.current

    /// The server ignores a `captured_at` older than this.
    static let maxAge: TimeInterval = 36 * 3600

    /// Margin so a punch that is just inside the limit here is not just outside it by the time the server sees it.
    static let ageSafety: TimeInterval = 5 * 60

    /// `captured_at` as the server wants it: ISO-8601 in UTC with a `Z` designator and whole seconds,
    /// e.g. `2026-10-12T04:03:11Z`.
    static func formatCapturedAt(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let whole = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
        return f.string(from: whole)
    }

    /// Inverse of `formatCapturedAt` (also reads an ISO instant with fractional seconds); nil when unreadable.
    static func parseCapturedAt(_ iso: String?) -> Date? {
        guard let s = iso?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    /// An instant in the shape the app's time helpers parse everywhere (`yyyy-MM-ddTHH:mm:ss.SSSZ`). Used for the
    /// locally derived stand-in record, never sent to the server.
    static func formatLocalIso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return f.string(from: date)
    }

    /// The India date (`yyyy-MM-dd`) an instant falls on — correct either side of IST midnight (18:30 UTC).
    static func istDate(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = istTimeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// The `?date=` query to send, or nil. A punch is sent without a date when it belongs to today (IST) — the
    /// server's default — and with `?date=<attendance day>` when it belongs to another day (a check-in captured on a
    /// previous IST day, or the check-out of a shift that started on an earlier day).
    static func dateQuery(attendanceDate: String?, now: Date) -> String? {
        guard let d = attendanceDate?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty else { return nil }
        return d == istDate(now) ? nil : d
    }

    /// True when the capture is too old for the server to honour its `captured_at` (it would stamp server time instead).
    static func isTooOld(capturedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(capturedAt) > maxAge - ageSafety
    }

    /// `09:12` — the wall-clock time of an instant in `zone` (24-hour).
    static func clock(_ date: Date, zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: what the rep is told

    /// "Checked in 09:12 — will sync when online".
    static func queuedMessage(kind: Kind, capturedAt: Date, zone: TimeZone) -> String {
        "\(kind.verb) \(clock(capturedAt, zone: zone)) — will sync when online"
    }

    /// Shown after "Check-in failed: " / "Check-out failed: " when a selfie is needed but there is none to save.
    static let selfieRequiredMessage = "a selfie is required while offline. Please retake it."

    static let checkinRefusedMessage = "Its check-in was not accepted, so there is no shift to check out of."
    static let tooOldMessage = "Captured more than 36 hours ago, too old to sync. Ask your manager to regularize this day."

    // MARK: queue or fail?

    enum Decision: Equatable {
        /// Keep it in the queue and tell the rep it will sync.
        case queue
        /// Show the real error, exactly as before. Nothing is saved.
        case fail
        /// It could be queued, but a selfie is demanded and there is none — ask for one instead of saving a punch that
        /// would be refused.
        case needSelfie
    }

    /// Queue or fail? Only when the client allows offline check-in AND the failure is a connectivity one
    /// (`retryable`: AttendanceSyncPolicy `.transient`). Every other answer (a 4xx refusal, `success:false`, an
    /// unreadable reply) is a real error: shown, never "saved".
    static func decide(allowOffline: Bool, retryable: Bool, hasPhoto: Bool, selfieRequired: Bool) -> Decision {
        if !allowOffline { return .fail }
        if !retryable { return .fail }
        if selfieRequired && !hasPhoto { return .needSelfie }
        return .queue
    }

    // MARK: what a server answer means

    enum Verdict: Equatable {
        /// The server has the punch (2xx, or 409 = this shift is already recorded): finished.
        case done
        /// Not delivered — keep the row and retry later (outage, throttling, 5xx, a session that needs refreshing).
        case hold
        /// The server gave a final "no": mark the row failed, show it, never retry.
        case reject
    }

    /// A reply that is neither a connectivity failure nor an HTTP status (an unreadable reply, a bug) is retried this
    /// many times, then refused.
    static let maxUnknownAttempts = 3

    /// A 409 meaning the server already holds this punch. The idempotency middleware's own refusals (same key reused
    /// with a different body / by a different user / too long) are genuine rejections.
    static func isAlreadyRecorded(httpStatus: Int?, message: String?) -> Bool {
        guard httpStatus == 409 else { return false }
        let m: String = (message ?? "").lowercased()
        if m.contains("different request body") || m.contains("different user") || m.contains("too long") { return false }
        return true
    }

    /// Verdict for a FAILED send (a successful one is `.done` without asking).
    ///  - a 409 that means "already recorded" → done;
    ///  - an expired sign-in (401) or a connectivity failure (no network, 408 / 429 / 5xx) → hold: a punch must not
    ///    be thrown away for that;
    ///  - the "turn on location" backstop → reject (the stored fix is what it is; replaying cannot fix it);
    ///  - any other answer from the server (a 4xx, `success:false`) → reject;
    ///  - no status at all and not a connectivity failure (an unreadable reply or a bug) → hold a few times, then
    ///    reject, so it cannot loop for ever.
    static func verdict(failure: AttendanceFailureKind, httpStatus: Int?, message: String?, attempt: Int) -> Verdict {
        if isAlreadyRecorded(httpStatus: httpStatus, message: message) { return .done }
        switch failure {
        case .transient, .authRequired:
            return .hold
        case .locationRequired:
            return .reject
        case .rejected:
            if httpStatus == nil || httpStatus == 0 {
                return attempt < maxUnknownAttempts ? .hold : .reject
            }
            return .reject
        }
    }

    // MARK: ordering: a check-out never goes before its check-in

    /// How the latest EARLIER queued check-in stands.
    enum CheckinOutcome: Equatable {
        case synced
        case pending
        case rejected
    }

    enum Gate: Equatable {
        /// Go ahead and send it.
        case send
        /// Its check-in has not reached the server yet — leave it queued.
        case waitForCheckin
        /// Its check-in was refused for good, so there is no shift to close — refuse it too.
        case rejectNoCheckin
    }

    /// May this punch be sent now? Rows are replayed oldest first. A check-in always may. A check-out may when no
    /// check-in is queued ahead of it (`precedingCheckin` nil) or the latest one already succeeded; it waits while
    /// that check-in is still pending and is refused when that check-in was refused.
    static func gate(kind: Kind, precedingCheckin: CheckinOutcome?) -> Gate {
        if kind == .checkIn { return .send }
        guard let outcome = precedingCheckin else { return .send }
        switch outcome {
        case .synced: return .send
        case .pending: return .waitForCheckin
        case .rejected: return .rejectNoCheckin
        }
    }
}

// MARK: - What the screens read while a punch is waiting

/// The app keeps ONE "today" record (what the server last said). While opted-in punches are queued, the record the UI
/// reads is that record with the queued punches laid over it (`effectiveToday`): a queued check-in shows the rep as
/// checked in (a stand-in record), a queued check-out as checked out. Once a punch reaches the server it drops out of
/// the queue, the overlay disappears and the real server record is what is left. With nothing queued `effectiveToday`
/// returns the server record untouched, so a client that never queues anything sees exactly what it saw before.
enum OfflinePunchState {

    /// `id` of the stand-in record built from a queued check-in (never a server id).
    static let pendingRecordId = "pending-offline"

    /// One queued punch as the UI sees it. `rejected` = the server refused it for good (it stays visible, with `error`,
    /// until the rep dismisses it) — a rejected punch never counts as checked in / out. `transportMode` = the travel
    /// mode the rep chose for a queued check-in (so Home can show it before the check-in has synced).
    struct PendingPunch: Equatable {
        var id: String
        var kind: OfflinePunch.Kind
        var capturedAt: Date
        /// When the row was queued — the replay order.
        var queuedAt: Date
        var attendanceDate: String
        var rejected: Bool
        var error: String?
        var transportMode: String?

        init(id: String, kind: OfflinePunch.Kind, capturedAt: Date, queuedAt: Date? = nil, attendanceDate: String,
             rejected: Bool = false, error: String? = nil, transportMode: String? = nil) {
            self.id = id
            self.kind = kind
            self.capturedAt = capturedAt
            self.queuedAt = queuedAt ?? capturedAt
            self.attendanceDate = attendanceDate
            self.rejected = rejected
            self.error = error
            self.transportMode = transportMode
        }
    }

    // MARK: the record the UI reads

    /// `base` (the server's record for today, or nil) with the live (not rejected) `punches` laid over it.
    ///  - a queued check-in the server does not have yet → a stand-in record, status `checked_in`, check-in time =
    ///    capture time; when `base` already holds a check-in for that same day the server record wins;
    ///  - a queued check-out → the record reads `checked_out` with the capture time, unless `base` already has a
    ///    check-out.
    /// Returns `base` itself when there is nothing live to lay over it.
    static func effectiveToday(base: AttendanceRecord?, punches: [PendingPunch]) -> AttendanceRecord? {
        let live: [PendingPunch] = punches.filter { !$0.rejected }.sorted { $0.queuedAt < $1.queuedAt }
        if live.isEmpty { return base }
        let pendingIn: PendingPunch? = live.last(where: { $0.kind == .checkIn })
        let pendingOut: PendingPunch? = live.last(where: { $0.kind == .checkOut })

        var rec: AttendanceRecord? = base
        if let pin = pendingIn, !serverHasCheckin(rec, pin) {
            rec = standIn(pin)
        }
        if let pout = pendingOut, rec?.checkoutAt == nil {
            let outAt: String = OfflinePunch.formatLocalIso(pout.capturedAt)
            var shell: AttendanceRecord = rec ?? AttendanceRecord(
                id: pendingRecordId, date: pout.attendanceDate, status: nil,
                checkinAt: nil, checkoutAt: nil, totalHours: nil,
                checkinSelfieUrl: nil, checkoutSelfieUrl: nil)
            shell.status = "checked_out"
            shell.checkoutAt = outAt
            shell.lastCheckoutAt = outAt
            // Drop the server's session list for this offline overlay: the pending checkout
            // isn't in it yet, so the sessions-aware isClockedIn must fall back to the flat
            // checkout above (otherwise a still-"open" session would read as clocked in).
            shell.sessions = nil
            rec = shell
        }
        return rec
    }

    private static func serverHasCheckin(_ rec: AttendanceRecord?, _ pendingIn: PendingPunch) -> Bool {
        guard let r = rec, r.checkinAt != nil else { return false }
        return isoDateOf(r.date) == pendingIn.attendanceDate
    }

    private static func standIn(_ pendingIn: PendingPunch) -> AttendanceRecord {
        let at: String = OfflinePunch.formatLocalIso(pendingIn.capturedAt)
        return AttendanceRecord(
            id: pendingRecordId,
            date: pendingIn.attendanceDate,
            status: "checked_in",
            checkinAt: at,
            checkoutAt: nil,
            totalHours: nil,
            checkinSelfieUrl: nil,
            checkoutSelfieUrl: nil,
            firstCheckinAt: at,
            transportMode: pendingIn.transportMode)
    }

    /// True when the record is the stand-in built from a queued punch rather than something the server sent.
    static func isStandIn(_ rec: AttendanceRecord?) -> Bool {
        rec?.id == pendingRecordId
    }

    /// The day (`yyyy-MM-dd`) of the shift a check-out closes: the day of the open record the rep is looking at (the
    /// shift may have started before today, e.g. overnight), else the India day of the capture. Sent as `?date=` when
    /// it is not today, so the server closes THAT shift and not today's.
    static func shiftDate(today: AttendanceRecord?, capturedAt: Date) -> String {
        let d: String = today?.checkinAt != nil ? isoDateOf(today?.date) : ""
        if isIsoDay(d) { return d }
        return OfflinePunch.istDate(capturedAt)
    }

    // MARK: what the rep reads

    /// A line for the home / attendance screens. `isError` = a refused punch that needs the rep's attention.
    struct Notice: Equatable {
        var text: String
        var isError: Bool
    }

    /// The one line to show for the queued `punches`, or nil when there are none:
    ///  - a refused punch first (it needs attention): "Check-in 09:12 was not accepted: <reason>";
    ///  - else the latest waiting one: "Checked in 09:12 — will sync when online".
    static func notice(punches: [PendingPunch], zone: TimeZone) -> Notice? {
        let refused: [PendingPunch] = punches.filter { $0.rejected }
        if let latest = refused.max(by: { $0.queuedAt < $1.queuedAt }) {
            return Notice(text: refusedText(latest, zone: zone), isError: true)
        }
        let waiting: [PendingPunch] = punches.filter { !$0.rejected }
        guard let latest = waiting.max(by: { $0.queuedAt < $1.queuedAt }) else { return nil }
        return Notice(text: OfflinePunch.queuedMessage(kind: latest.kind, capturedAt: latest.capturedAt, zone: zone),
                      isError: false)
    }

    static func refusedText(_ p: PendingPunch, zone: TimeZone) -> String {
        let head: String = "\(p.kind.noun) \(OfflinePunch.clock(p.capturedAt, zone: zone)) was not accepted"
        if let reason = p.error?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            return "\(head): \(reason)"
        }
        return head
    }

    // MARK: date helpers

    /// An API date as `yyyy-MM-dd`: accepts ISO (with or without a time part) and the legacy `dd--MM--yyyy`; anything
    /// else comes back trimmed.
    static func isoDateOf(_ raw: String?) -> String {
        let s: String = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 10 {
            let head: String = String(s.prefix(10))
            if isIsoDay(head) { return head }
        }
        let chars: [Character] = Array(s)
        if chars.count == 12, chars[2] == "-", chars[3] == "-", chars[6] == "-", chars[7] == "-" {
            let dd: String = String(chars[0..<2])
            let mm: String = String(chars[4..<6])
            let yyyy: String = String(chars[8..<12])
            if allDigits(dd) && allDigits(mm) && allDigits(yyyy) { return "\(yyyy)-\(mm)-\(dd)" }
        }
        return s
    }

    /// True for exactly `yyyy-MM-dd` (digits and two dashes; the calendar is not checked).
    static func isIsoDay(_ s: String) -> Bool {
        let chars: [Character] = Array(s)
        if chars.count != 10 { return false }
        if chars[4] != "-" || chars[7] != "-" { return false }
        for (i, ch) in chars.enumerated() {
            if i == 4 || i == 7 { continue }
            if !ch.isASCII || !ch.isNumber { return false }
        }
        return true
    }

    /// True when `rec` is the record for the current India day — the only persisted record worth showing on an offline start.
    static func isForToday(_ rec: AttendanceRecord?, now: Date) -> Bool {
        guard let r = rec else { return false }
        return isoDateOf(r.date) == OfflinePunch.istDate(now)
    }

    private static func allDigits(_ s: String) -> Bool {
        if s.isEmpty { return false }
        for ch in s {
            if !ch.isASCII || !ch.isNumber { return false }
        }
        return true
    }
}
