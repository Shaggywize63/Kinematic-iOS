//
//  TravelPrompt.swift
//  Kinematic
//
//  The rules behind "Add today's travel to expenses?" — pure Swift, unit-tested (see KinematicTests/TravelPromptTests).
//  Mirrors the Android `TravelPrompt`.
//
//  Opt-in per client BY DATA: the prompt exists only when the expense policy that governs the rep says
//  `gps_distance: true` AND lists vehicle rates (`eligible`); every other client never sees it. After the final
//  check-out the app asks the server how far the rep travelled that India day (`GET /attendance/travel`), shows the
//  distance with the vehicle chips of the policy and the amount it will come to (km x rate — a preview, the server
//  prices the line), and on "Add to expenses" creates a DRAFT claim with one mileage line (`claimBody`) and opens it in
//  the editor. "Not now" is remembered per user and day (`Memory`).
//

import Foundation

enum TravelPrompt {

    // MARK: when is it offered?

    /// The vehicles the sheet offers: the policy's own, in its order, without blank or repeated ids.
    static func vehicles(_ rules: ExpensePolicyRules?) -> [ExpenseVehicleRate] {
        ExpenseLogic.policyVehicles(rules)
    }

    /// Offer the prompt at all? Only for a signed-in rep whose client has the expenses module (`expensesEnabled`) and
    /// whose resolved policy pays GPS distance (`gps_distance: true`) by vehicle. A policy that could not be fetched
    /// (nil rules) never qualifies.
    static func eligible(rules: ExpensePolicyRules?, expensesEnabled: Bool, signedIn: Bool) -> Bool {
        expensesEnabled && signedIn && rules?.gps_distance == true && !vehicles(rules).isEmpty
    }

    /// The India day (`yyyy-MM-dd`) an instant falls on — the day the travel is about.
    static func istDate(_ now: Date) -> String {
        let ist: TimeZone = TimeZone(secondsFromGMT: 5 * 3600 + 30 * 60) ?? TimeZone.current
        guard let parts = FormFieldLogic.parts(of: now, timeZone: ist) else { return "" }
        return FormFieldLogic.formatDate(parts.date)
    }

    /// The vehicle chosen for the rep when there is nothing to choose (the policy lists exactly one), else nil.
    static func defaultVehicle(_ rules: ExpensePolicyRules?) -> String? {
        ExpenseLogic.soleVehicleId(vehicles(rules))
    }

    /// Today's mode of transport as a vehicle of the policy, or nil: `modeId` (the id the rep chose at Clock-In, for a
    /// client whose attendance rule asks for it) when it is one of the policy's `vehicle_rates`; `public_transport`,
    /// `other`, an id the policy does not list, no mode, no policy = nothing special (`TransportMode.preselectVehicle`).
    static func vehicleForMode(_ rules: ExpensePolicyRules?, modeId: String?) -> String? {
        TransportMode.preselectVehicle(modeId: modeId, policyVehicleIds: vehicles(rules).map { $0.id })
    }

    /// The vehicle the sheet starts on: today's mode when it is a vehicle of the policy, else the only vehicle when the
    /// policy lists exactly one, else none — the rep chooses. With no `modeId` this is exactly `defaultVehicle`, i.e.
    /// the sheet of a client that does not ask for a mode is unchanged.
    static func initialVehicle(_ rules: ExpensePolicyRules?, modeId: String?) -> String? {
        vehicleForMode(rules, modeId: modeId) ?? defaultVehicle(rules)
    }

    // MARK: "Not now" and friends, per user and day

    /// What the rep did with the prompt on a given day.
    enum Memory: String, CaseIterable {
        /// Pressed "Not now" (or closed the sheet): do not pop the sheet again; the Home card stays as the way back in.
        case snoozed
        /// Closed the Home card: nothing is offered again that day.
        case dismissed
        /// A draft claim was created: nothing is offered again that day.
        case added
    }

    /// `"<userId>|<date>|<code>"`; nil when the user is not known (nothing is remembered then).
    static func encodeMemory(userId: String?, date: String, memory: Memory) -> String? {
        let u: String = (userId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty || u.contains("|") { return nil }
        return "\(u)|\(date)|\(memory.rawValue)"
    }

    /// The memory for exactly this user and day, or nil (no record, another user, another day, unreadable).
    static func decodeMemory(_ raw: String?, userId: String?, date: String) -> Memory? {
        let u: String = (userId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return nil }
        guard let raw = raw else { return nil }
        let parts: [String] = raw.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
        if parts.count != 3 || parts[0] != u || parts[1] != date { return nil }
        return Memory(rawValue: parts[2])
    }

    /// Pop the sheet right after a check-out? Only a fresh one, once, when nothing was decided that day.
    static func autoShow(eligible: Bool, memory: Memory?) -> Bool {
        eligible && memory == nil
    }

    /// Show the Home card? After check-out, until the rep added the claim or closed the card ("Not now" keeps it).
    static func showCard(eligible: Bool, shiftCompleted: Bool, memory: Memory?) -> Bool {
        eligible && shiftCompleted && (memory == nil || memory == .snoozed)
    }

    // MARK: what the server said

    enum Outcome: Equatable {
        /// Something to claim: `km` (2 dp) over `legs` legs; `method` = the server's "gps_trail" / "straight_line" / "mixed".
        case ready(km: Double, legs: Int, method: String?)
        /// The day has no travel to claim (no attendance, or the distance came to nothing). Never turned into a zero claim.
        case noTravel
        /// The shift is still open on the server (the check-out is queued offline): the distance is not final.
        case notSynced
        /// The call failed (offline, server error): say so, let the rep retry.
        case unavailable(String)
    }

    /// Two decimals, like the server and the editor.
    static func roundKm(_ km: Double) -> Double {
        (km * 100).rounded() / 100
    }

    /// Turn the travel reply (or its failure) into what the sheet shows. A missing summary is a failure, never "0 km".
    static func outcomeOf(summary: TravelSummary?, error: String?) -> Outcome {
        guard let s = summary else {
            let message: String = (error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .unavailable(message.isEmpty ? "Couldn't load today's travel." : message)
        }
        if s.inProgress == true { return .notSynced }
        let km: Double = roundKm(s.totalKm ?? 0)
        let attendance: String = (s.attendanceId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if attendance.isEmpty || s.method == "none" || km <= 0 { return .noTravel }
        return .ready(km: km, legs: s.legCount, method: s.method)
    }

    /// What the rep is told when the call failed: a connection problem says so, anything else shows the server's reason.
    static func failureMessage(_ error: Error) -> String {
        if error is URLError {
            return "Couldn't reach the server to work out today's travel. Check your connection and try again."
        }
        let text: String = error.localizedDescription
        return text.isEmpty ? "Couldn't load today's travel." : text
    }

    /// The server refuses a second GPS line for a day already claimed ("Travel for 2026-10-10 is already claimed on EXP-12").
    static func isAlreadyClaimed(_ message: String?) -> Bool {
        (message ?? "").lowercased().contains("already claimed")
    }

    /// "3 legs" / "1 leg".
    static func legsText(_ legs: Int) -> String {
        legs == 1 ? "1 leg" : "\(legs) legs"
    }

    /// "23.4 km" (no trailing zeros).
    static func kmText(_ km: Double) -> String {
        ExpenseLogic.trimNumber(km) + " km"
    }

    /// A line under the distance when it is an estimate; nil for a measured GPS route.
    static func methodNote(_ method: String?) -> String? {
        switch method {
        case "straight_line"?: return "Estimated in a straight line between your check-in and check-out."
        case "mixed"?:         return "Part of this is estimated in a straight line where the GPS route was incomplete."
        default:               return nil
        }
    }

    // MARK: the amount and the claim

    /// km x the vehicle's rate per km (2 dp) — the preview shown on the sheet. Nil until a vehicle is chosen.
    static func amountPreview(km: Double, vehicle: ExpenseVehicleRate?) -> Double? {
        guard let v = vehicle else { return nil }
        return (km * v.rate_per_km * 100).rounded() / 100
    }

    /// "Two wheeler · ₹4/km" — the chip text.
    static func chipLabel(_ vehicle: ExpenseVehicleRate, currency: String) -> String {
        let name: String = vehicle.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ExpenseLogic.vehicleName(vehicle.id, in: nil)
            : vehicle.label
        return "\(name) · \(ExpenseLogic.money(vehicle.rate_per_km, currency))/km"
    }

    /// The draft's title: "Travel · 10 Oct 2026". The policy may rename the mileage category (the claim editor already
    /// says "Travel" for a by-vehicle policy unless it does), and the title follows that name.
    static func claimTitle(_ rules: ExpensePolicyRules?, date: String) -> String {
        let word: String = ExpenseLogic.customLabel("mileage", labels: rules?.category_labels) ?? "Travel"
        return "\(word) · \(ExpenseLogic.shortDate(date) ?? date)"
    }

    /// The claim to create: ONE mileage line for `date` with the chosen vehicle and the distance, no odometer and no
    /// amount (the server prices a GPS-distance line from the vehicle's rate). Saved as a draft by the caller.
    static func claimBody(_ rules: ExpensePolicyRules?, date: String, vehicleId: String, km: Double) -> ExpenseClaimInput {
        let line = ExpenseClaimItemInput(
            id: nil,
            category: "mileage",
            item_date: date,
            description: "GPS distance for \(ExpenseLogic.shortDate(date) ?? date)",
            amount: nil,
            distance_km: roundKm(km),
            from_location: nil,
            to_location: nil,
            merchant: nil,
            receipt_url: nil,
            ai_extracted: nil,
            vehicle_type: vehicleId,
            odometer_start: nil,
            odometer_end: nil,
            odometer_start_photo_url: nil,
            odometer_end_photo_url: nil
        )
        return ExpenseClaimInput(title: claimTitle(rules, date: date), items: [line])
    }
}

/// Where "Not now" and friends are remembered: ONE record on the phone that names its owner and day (`encodeMemory`),
/// so another person's, or yesterday's, is never read. `SessionCleanup` removes it at sign-out.
enum TravelPromptStore {
    static let storageKey: String = "travel_prompt_memory"

    static func read(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: storageKey)
    }

    static func write(_ raw: String?, in defaults: UserDefaults = .standard) {
        if let raw = raw { defaults.set(raw, forKey: storageKey) } else { defaults.removeObject(forKey: storageKey) }
    }
}
