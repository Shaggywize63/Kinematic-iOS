//
//  TravelPromptModel.swift
//  Kinematic
//
//  State behind "Add today's travel to expenses?" (the sheet after the final check-out and the card on Home). The rules
//  live in `TravelPrompt` (pure, unit-tested); this class only fetches (the expense policy, the day's distance),
//  remembers what the rep chose per user and day, and holds what the screens show.
//
//  Opt-in by DATA: nothing is offered unless the rep's resolved expense policy says `gps_distance: true` and lists
//  vehicle rates (`TravelPrompt.eligible`) and the client has the expenses module. Everything here is idle for every
//  other client: the policy is not even fetched until a shift is completed.
//

import Foundation
import Combine

@MainActor
final class TravelPromptModel: ObservableObject {

    static let shared = TravelPromptModel()

    /// The India day the prompt is about.
    @Published private(set) var date: String = TravelPrompt.istDate(Date())
    /// The policy says `gps_distance` with vehicles, and the client has expenses: the prompt may be offered.
    @Published private(set) var eligible: Bool = false
    @Published private(set) var rules: ExpensePolicyRules? = nil
    @Published private(set) var currency: String = "INR"
    /// What the rep already did with the prompt today, or nil.
    @Published private(set) var memory: TravelPrompt.Memory? = nil
    @Published private(set) var sheetOpen: Bool = false
    /// The day's distance is being fetched.
    @Published private(set) var loading: Bool = false
    @Published private(set) var outcome: TravelPrompt.Outcome? = nil
    @Published private(set) var vehicleId: String? = nil
    /// Today's mode of transport (an id) for a client whose attendance rule asks for one; nil otherwise. Only used to
    /// pre-select `vehicleId`.
    @Published private(set) var transportModeId: String? = nil
    /// The draft claim is being created.
    @Published private(set) var creating: Bool = false
    @Published private(set) var errorText: String? = nil
    /// A check-out has just reached the server and the sheet is about to open (other prompts wait for it).
    @Published private(set) var checkoutPending: Bool = false

    private var policy: ExpensePolicy? = nil
    private var policyTriedAt: Date? = nil
    private var heldFor: String? = nil
    /// The rep picked a vehicle themselves: today's mode of transport no longer chooses for them.
    private var vehicleTouched: Bool = false
    private var travelTask: Task<Void, Never>? = nil

    /// A failed policy fetch is not retried more often than this.
    private let policyRetry: TimeInterval = 60

    private init() {}

    // MARK: whose state is this

    private var currentUserId: String? {
        let t: String = (Session.currentUser?.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Forget everything held (sign-out, or a different person signed in): nothing of the previous person survives.
    func reset() {
        travelTask?.cancel()
        travelTask = nil
        policy = nil
        policyTriedAt = nil
        heldFor = nil
        vehicleTouched = false
        date = TravelPrompt.istDate(Date())
        eligible = false
        rules = nil
        currency = "INR"
        memory = nil
        sheetOpen = false
        loading = false
        outcome = nil
        vehicleId = nil
        transportModeId = nil
        creating = false
        errorText = nil
        checkoutPending = false
    }

    private func syncUser() {
        let uid: String? = currentUserId
        if uid != heldFor {
            reset()
            heldFor = uid
        }
    }

    // MARK: eligibility

    private func ensurePolicy(force: Bool) async {
        let now = Date()
        if !force {
            if policy != nil { return }
            if let tried = policyTriedAt, now.timeIntervalSince(tried) < policyRetry { return }
        }
        policyTriedAt = now
        let fetched: ExpensePolicy? = try? await ExpensesAPI.shared.policy()
        policy = ExpenseLogic.policyAfterRefresh(current: policy, fetched: fetched)
    }

    private func evaluate(date day: String, expensesEnabled: Bool, forcePolicy: Bool) async {
        syncUser()
        let uid: String? = currentUserId
        if expensesEnabled { await ensurePolicy(force: forcePolicy) }
        // Somebody else signed in while the policy was being fetched: this answer is not theirs.
        if uid != currentUserId { return }
        let r: ExpensePolicyRules? = policy?.rules
        date = day
        eligible = TravelPrompt.eligible(rules: r, expensesEnabled: expensesEnabled, signedIn: uid != nil)
        rules = r
        currency = policy?.currency ?? "INR"
        memory = TravelPrompt.decodeMemory(TravelPromptStore.read(), userId: uid, date: day)
        // The rep's own pick wins; else today's mode of transport when it is one of the policy's vehicles; else the only vehicle.
        if vehicleId == nil { vehicleId = TravelPrompt.initialVehicle(r, modeId: transportModeId) }
    }

    /// Home is showing and the shift is completed: work out whether the card is due. Never opens the sheet. Does nothing
    /// (and fetches nothing) before check-out.
    func refresh(shiftCompleted: Bool, expensesEnabled: Bool) async {
        if !shiftCompleted || !expensesEnabled { return }
        if sheetOpen { return } // do not change the day under an open sheet
        await evaluate(date: TravelPrompt.istDate(Date()), expensesEnabled: expensesEnabled, forcePolicy: false)
    }

    /// A check-out for `date` just reached the server: offer the sheet once, when nothing was decided for that day.
    func onFreshCheckout(date day: String, expensesEnabled: Bool) async {
        if !expensesEnabled { return }
        checkoutPending = true
        await evaluate(date: day, expensesEnabled: expensesEnabled, forcePolicy: true)
        checkoutPending = false
        if TravelPrompt.autoShow(eligible: eligible, memory: memory) { openSheetNow() }
    }

    // MARK: the sheet

    /// The Home card was tapped.
    func openSheet() {
        if eligible { openSheetNow() }
    }

    private func openSheetNow() {
        sheetOpen = true
        errorText = nil
        creating = false
        loadTravel()
    }

    /// Ask again (after a failure or while the check-out was still syncing).
    func retry() {
        loadTravel()
    }

    private func loadTravel() {
        travelTask?.cancel()
        let day: String = date
        loading = true
        outcome = nil
        errorText = nil
        travelTask = Task { [weak self] in
            let result: TravelPrompt.Outcome
            do {
                let summary: TravelSummary = try await ExpensesAPI.shared.travel(date: day)
                result = TravelPrompt.outcomeOf(summary: summary, error: nil)
            } catch {
                result = TravelPrompt.outcomeOf(summary: nil, error: TravelPrompt.failureMessage(error))
            }
            if Task.isCancelled { return }
            guard let strongSelf = self else { return }
            strongSelf.loading = false
            strongSelf.outcome = result
        }
    }

    func selectVehicle(_ id: String) {
        vehicleTouched = true
        vehicleId = id
    }

    /// Today's mode of transport, from the attendance record (pass nil when the client's attendance rule does not ask for
    /// one). When it is a vehicle of the policy's `vehicle_rates` the sheet starts on that vehicle; `public_transport` /
    /// `other` / an unknown id change nothing. Never overrides a vehicle the rep picked themselves. Safe to call before
    /// the policy is known: the pre-selection is applied as soon as it is.
    func setTransportMode(_ modeId: String?) {
        let trimmed: String = (modeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let id: String? = trimmed.isEmpty ? nil : trimmed
        if transportModeId == id { return }
        transportModeId = id
        if !vehicleTouched { vehicleId = TravelPrompt.initialVehicle(rules, modeId: id) }
    }

    /// "Not now" (or the sheet was closed): do not pop it again today; the Home card stays. Never overrides "added" / "dismissed".
    func notNow() {
        if memory == nil || memory == .snoozed {
            remember(.snoozed)
        } else {
            sheetOpen = false
            creating = false
            errorText = nil
        }
    }

    /// The sheet was swiped away: like "Not now", except that a day with nothing to claim has nothing to come back to,
    /// so it ends the prompt for the day (the Home card goes too).
    func closeSheet() {
        if creating { return }
        if outcome == TravelPrompt.Outcome.noTravel { dismissCard() } else { notNow() }
    }

    /// The Home card was closed: nothing more is offered today.
    func dismissCard() {
        remember(.dismissed)
    }

    private func remember(_ m: TravelPrompt.Memory) {
        travelTask?.cancel()
        memory = m
        sheetOpen = false
        creating = false
        errorText = nil
        loading = false
        if let raw = TravelPrompt.encodeMemory(userId: currentUserId, date: date, memory: m) {
            TravelPromptStore.write(raw)
        }
    }

    // MARK: adding the claim

    /// "Add to expenses" was pressed: create the DRAFT claim with one mileage line, then open it in the editor. A refusal
    /// (e.g. "Travel for 2026-10-10 is already claimed on EXP-12") is shown on the sheet; "already claimed" also ends the
    /// prompt for the day.
    func add() async {
        if creating { return }
        guard let current = outcome, case .ready(let km, _, _) = current, let vehicle = vehicleId else { return }
        creating = true
        errorText = nil
        let body: ExpenseClaimInput = TravelPrompt.claimBody(rules, date: date, vehicleId: vehicle, km: km)
        do {
            let claim: ExpenseClaim = try await ExpensesAPI.shared.createClaim(body)
            remember(.added)
            // Let the sheet finish closing before the claim's screen is presented over the app.
            try? await Task.sleep(nanoseconds: 450_000_000)
            KiniAppState.shared.open(.expenseClaim(claim.id, edit: true))
        } catch {
            addFailed(error.localizedDescription)
        }
    }

    private func addFailed(_ message: String) {
        let trimmed: String = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String = trimmed.isEmpty ? "Couldn't add today's travel to your expenses." : trimmed
        creating = false
        errorText = text
        if TravelPrompt.isAlreadyClaimed(text) {
            memory = .added
            if let raw = TravelPrompt.encodeMemory(userId: currentUserId, date: date, memory: .added) {
                TravelPromptStore.write(raw)
            }
        }
    }
}
