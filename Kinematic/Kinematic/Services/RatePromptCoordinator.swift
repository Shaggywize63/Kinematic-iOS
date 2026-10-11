//
//  RatePromptCoordinator.swift
//  Kinematic
//
//  The session side of the rate-the-app prompt (opt-in per client BY DATA: `app_ui_config.features.rate_prompt == true`).
//  The counters, the eligibility rules and the stored record are `RatePrompt` / `RatePromptStore` (pure, unit-tested,
//  per device); here: feeding the counters, and the SESSION rules. Home ARMS the prompt (`offer()` while it is quiet,
//  `withdraw()` when it is not), so it is never asked over a camera, a form or one of Home's own dialogs; and it is
//  answered at most once per app session.
//
//  Nothing happens for a client that has not opted in: no counter moves and `offer()` shows nothing.
//

import Foundation
import Combine

@MainActor
final class RatePromptCoordinator: ObservableObject {

    static let shared = RatePromptCoordinator()

    /// True while the "Enjoying Kinematic?" dialog should be on screen.
    @Published private(set) var showingPrompt: Bool = false

    private let defaults: UserDefaults
    private var answered: Bool = false
    private var lastNotedOpenDay: String? = nil

    /// `defaults` is a test seam (production uses the standard one).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Is this client opted in? Only an explicit `true` in `app_ui_config.features`.
    private var featureOn: Bool { ClientFeatures.featureOn(RatePrompt.featureId) }

    // MARK: feeding the counters

    /// The app came to the foreground (or Home appeared): count today as a day it was opened — once per day, and nothing
    /// for a client that has not opted in.
    func noteAppOpened(now: Date = Date()) {
        if !featureOn { return }
        let day: String = RatePrompt.dayOf(ms: RatePrompt.ms(now))
        if day == lastNotedOpenDay { return }
        lastNotedOpenDay = day
        RatePromptStore.update(in: defaults) { RatePrompt.noteOpen($0, day: day) }
    }

    /// A good moment happened (a successful online check-out, a form that reached the server).
    func notePositiveMoment() {
        if !featureOn { return }
        RatePromptStore.update(in: defaults) { RatePrompt.notePositive($0) }
    }

    // MARK: showing it

    /// Home is on screen with nothing else asking for attention: show the dialog if the rules allow it
    /// (`RatePrompt.eligible`). Does nothing once the rep has answered it this session, or while it is already showing.
    func offer(now: Date = Date()) {
        if showingPrompt || answered { return }
        if !featureOn { return }
        let ok: Bool = RatePrompt.eligible(
            featureOn: true,
            record: RatePromptStore.read(in: defaults),
            installMs: RatePromptStore.firstLaunchMs(in: defaults),
            nowMs: RatePrompt.ms(now)
        )
        if ok { showingPrompt = true }
    }

    /// Home left the screen, or something else needs it: take the dialog back (it can be offered again on a later visit).
    func withdraw() {
        showingPrompt = false
    }

    // MARK: the answers

    /// "Rate now" (the caller asks the system for the review), and the Settings row: never ask again.
    func rated() {
        answered = true
        showingPrompt = false
        RatePromptStore.update(in: defaults) { RatePrompt.rated($0) }
    }

    /// "Maybe later" (also the dialog dismissed): asked again no sooner than 30 days from now, at most 3 times in all.
    func maybeLater(now: Date = Date()) {
        answered = true
        showingPrompt = false
        let nowMs: Int64 = RatePrompt.ms(now)
        RatePromptStore.update(in: defaults) { RatePrompt.maybeLater($0, nowMs: nowMs) }
    }

    /// "Don't ask again".
    func never() {
        answered = true
        showingPrompt = false
        RatePromptStore.update(in: defaults) { RatePrompt.never($0) }
    }
}
