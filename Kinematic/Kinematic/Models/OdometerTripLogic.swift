// OdometerTripLogic — the rules behind the two-step daily odometer trip ("Today's travel"), kept free of
// SwiftUI so they can be unit-tested (see KinematicTests/OdometerTripLogicTests). The card only renders what
// these decide: which step to show, what each step still needs before it can be saved, the vehicle to
// pre-select, and the distance between two readings. Mirrors the Android OdometerTripLogic.

import Foundation

/// Where the day's trip has got to.
enum OdometerTripStatus: String, Equatable {
    /// Not started — the morning step is shown.
    case none
    /// The start reading is in — the evening step is shown.
    case open
    /// Both readings are in; the claim is priced and ready to submit.
    case closed

    init(_ raw: String?) {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "open":   self = .open
        case "closed": self = .closed
        default:       self = .none
        }
    }
}

/// What a step of the daily trip still needs before it can be saved. Order is the order to show them in.
/// Hashable so the card can list them with `ForEach(id: \.self)`.
enum OdometerTripMissing: Hashable {
    case reading
    case vehicle
    case photo
    case endBelowStart

    var text: String {
        switch self {
        case .reading:       return "Enter the odometer reading."
        case .vehicle:       return "Choose a vehicle."
        case .photo:         return "Add a photo of the odometer."
        case .endBelowStart: return "The reading at the end of the day is lower than the start reading."
        }
    }
}

enum OdometerTripLogic {

    /// The trip's status (nil trip — never started — is `.none`).
    static func status(_ trip: OdometerTrip?) -> OdometerTripStatus {
        guard let t = trip else { return .none }
        return OdometerTripStatus(t.status)
    }

    /// After a check-in reaches the server, the START capture is offered only when the day's trip has not begun yet
    /// (status none). If a start is already recorded (open) or the trip is closed, nothing is offered.
    static func offersStart(_ trip: OdometerTrip?) -> Bool { status(trip) == .none }

    /// After the final check-out, the END capture is offered only when the trip is open — a start reading is in but
    /// the end has not closed it. A trip that never started (none) or is already closed offers nothing.
    static func offersEnd(_ trip: OdometerTrip?) -> Bool { status(trip) == .open }

    /// An odometer reading: any finite number from 0 up (a new vehicle can read 0). Mirrors ExpenseLineFields.
    static func reading(_ s: String) -> Double? {
        guard let v = Double(s.trimmingCharacters(in: .whitespaces)), v >= 0, v.isFinite else { return nil }
        return v
    }

    /// The vehicle to pre-select on the start step: the server's `sole_vehicle`, else the only rate when the policy
    /// lists exactly one, else nil — with several vehicles the rep must choose.
    static func defaultVehicle(soleVehicle: String?, vehicleRates: [ExpenseVehicleRate]) -> String? {
        if let s = soleVehicle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        return vehicleRates.count == 1 ? vehicleRates[0].id : nil
    }

    /// A vehicle must be chosen before starting only when the policy lists more than one (one is pre-selected).
    static func vehicleChoiceRequired(_ vehicleRates: [ExpenseVehicleRate]) -> Bool {
        vehicleRates.count > 1
    }

    /// Km travelled, or nil until both readings are in and in order.
    static func distance(start: Double?, end: Double?) -> Double? {
        guard let s = start, let e = end, e >= s else { return nil }
        return ((e - s) * 100).rounded() / 100
    }

    /// What the morning step still needs (empty = ready to Save start).
    static func startMissing(readingText: String, vehicle: String, photoURL: String,
                             photosRequired: Bool, vehicleRates: [ExpenseVehicleRate]) -> [OdometerTripMissing] {
        var out: [OdometerTripMissing] = []
        if reading(readingText) == nil { out.append(.reading) }
        if vehicleChoiceRequired(vehicleRates),
           vehicle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.vehicle) }
        if photosRequired, photoURL.trimmingCharacters(in: .whitespaces).isEmpty { out.append(.photo) }
        return out
    }

    /// What the evening step still needs (empty = ready to Save end). `startReading` is the recorded morning reading;
    /// an end lower than it is called out.
    static func endMissing(readingText: String, startReading: Double?,
                           photoURL: String, photosRequired: Bool) -> [OdometerTripMissing] {
        var out: [OdometerTripMissing] = []
        let end = reading(readingText)
        if end == nil { out.append(.reading) }
        if let e = end, let s = startReading, e < s { out.append(.endBelowStart) }
        if photosRequired, photoURL.trimmingCharacters(in: .whitespaces).isEmpty { out.append(.photo) }
        return out
    }

    static func canSaveStart(readingText: String, vehicle: String, photoURL: String,
                             photosRequired: Bool, vehicleRates: [ExpenseVehicleRate]) -> Bool {
        startMissing(readingText: readingText, vehicle: vehicle, photoURL: photoURL,
                     photosRequired: photosRequired, vehicleRates: vehicleRates).isEmpty
    }

    static func canSaveEnd(readingText: String, startReading: Double?,
                           photoURL: String, photosRequired: Bool) -> Bool {
        endMissing(readingText: readingText, startReading: startReading,
                   photoURL: photoURL, photosRequired: photosRequired).isEmpty
    }

    /// The label for the button that opens the closed trip's claim: it invites a submit while the claim is still a
    /// draft (or was sent back), and simply views it once it has gone to an approver.
    static func reviewButtonLabel(claimStatus: String?) -> String {
        switch (claimStatus ?? "draft").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "draft", "rejected": return "Review & submit"
        default:                      return "View claim"
        }
    }
}

extension OdometerTrip {
    var statusKind: OdometerTripStatus { OdometerTripStatus(status) }

    /// "12340 → 12392" (a missing end shows "—").
    var readingsText: String {
        let a = odometer_start.map { ExpenseLogic.trimNumber($0) } ?? "—"
        let b = odometer_end.map { ExpenseLogic.trimNumber($0) } ?? "—"
        return "\(a) → \(b)"
    }
}
