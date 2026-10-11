//
//  FormVisitViews.swift
//  Kinematic
//
//  The screen side of check-in / check-out on every form (attendance rule `form_checkin_required`, rules in
//  `FormVisit`): the tracker a form screen holds, the running "On visit · 04:07" chip, the locked state of a form whose
//  visit has not been started, and the "Time on visit" summary after the submit.
//
//  Opt-in per client BY DATA. With the rule off none of this appears: `FormVisitTracker.enabled` is false and the
//  form screens behave exactly as they always did.
//

import SwiftUI
import Combine

@MainActor
final class FormVisitTracker: ObservableObject {

    enum StartResult {
        case started
        /// Location is off: show this prompt (it names the problem and offers Settings).
        case blocked(LocationGatePrompt)
        /// Location is on but no position could be had.
        case noFix
    }

    /// Which form this tracker belongs to (see `FormVisit.sessionMatches`).
    let key: String
    let outletId: String?
    let name: String?

    /// This form's open visit, if there is one.
    @Published private(set) var session: FormVisitSession?
    /// What the last saved form's visit came to (for the success state); nil until a form is saved under the rule.
    @Published private(set) var summary: FormVisit.Summary?
    @Published private(set) var starting: Bool = false

    init(key: String, outletId: String?, name: String?) {
        self.key = key
        self.outletId = outletId
        self.name = name
        self.session = nil
        self.summary = nil
        reload()
    }

    private var userId: String? { Session.currentUser?.id }

    /// The rule for the signed-in person right now (unknown = off).
    var enabled: Bool { AttendanceRulesStore.shared.currentRules().formCheckinRequired }

    /// Read this form's visit from the phone (only a visit that is really this form's, and recent, counts).
    func reload(now: Date = Date()) {
        let stored: FormVisitSession? = FormVisitStore.session(forKey: key, userId: userId)
        session = FormVisit.sessionMatches(stored, key: key, outletId: outletId, now: now) ? stored : nil
    }

    /// Start the visit: the time and the position, nothing else — no API call, no photo.
    func start() async -> StartResult {
        if let prompt = LocationGate.promptIfBlocked(verb: "start your visit") { return .blocked(prompt) }
        if starting { return .noFix }
        starting = true
        defer { starting = false }
        guard let fix = await FormLocationFix.current() else { return .noFix }
        let now = Date()
        let started = FormVisitSession(key: key, outletId: outletId, name: name,
                                       checkInAt: FormVisit.iso(now), lat: fix.lat, lng: fix.lng)
        FormVisitStore.save(started, userId: userId, now: now)
        session = started
        return .started
    }

    /// What a submission made now is stamped with (nothing when the rule is off or there is no visit of this form).
    func stamp(lat: Double?, lng: Double?, now: Date = Date()) -> FormVisit.Stamp {
        reload(now: now)
        return FormVisit.stamp(enabled: enabled, session: session, key: key, outletId: outletId,
                               lat: lat, lng: lng, now: now)
    }

    /// The form was saved with `stamp`: forget the visit it closed and keep its summary for the success state.
    func saved(with stamp: FormVisit.Stamp) {
        if stamp.clearSession {
            FormVisitStore.remove(key: key, userId: userId)
            session = nil
        }
        summary = stamp.summary
    }

    func dismissSummary() {
        summary = nil
    }
}

extension FormVisit {
    /// The two lines of the success state: the total, and when it started and ended.
    static func summaryMessage(_ summary: Summary, timeZone: TimeZone = .current) -> String {
        totalLabel(summary) + "\nChecked in and out: " + windowLabel(summary, timeZone: timeZone)
    }
}

/// "On visit · 04:07" — the running time since a visit was started. Ticks once a second while it is on screen.
struct VisitTimerChip: View {
    let checkInAt: String

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.caption)
                Text(FormVisit.timerLabel(checkInAt: checkInAt, now: context.date))
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

/// What a form shows instead of its questions until the visit is started.
struct FormVisitLockedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text("Start your visit first")
                .font(.title3.bold())
            Text("Tap “Start visit (Check-in)” to record your time and location, then fill in the form.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

/// The success state of a form for a `form_checkin_required` client: the visit's length and when it started and ended.
struct FormVisitSummaryView: View {
    let summary: FormVisit.Summary

    var body: some View {
        VStack(spacing: 6) {
            Text(FormVisit.totalLabel(summary))
                .font(.headline)
            Text("Checked in and out: " + FormVisit.windowLabel(summary))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
