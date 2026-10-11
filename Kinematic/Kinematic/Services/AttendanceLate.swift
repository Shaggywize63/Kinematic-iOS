//
//  AttendanceLate.swift
//  Kinematic
//
//  "Late by N min" for clients that track it. The API adds a `late` block to an attendance record ONLY for a client
//  that configured shift rules (`clients.settings.attendance_rules` with a shift_start / shift_end / grace_minutes /
//  weekly_off) and only on a record that has a check-in. For every other client the key is absent, so
//  `AttendanceRecord.late` is nil and nothing late is ever shown (see KinematicTests/AttendanceLateTests).
//

import Foundation

/// `late` on an attendance record. `isLate` = the check-in was later than shift start + grace (IST); `minutesLate` =
/// minutes after the shift start when late, else 0.
struct AttendanceLateInfo: Codable, Equatable {
    var isLate: Bool
    var minutesLate: Int?

    init(isLate: Bool = false, minutesLate: Int? = nil) {
        self.isLate = isLate
        self.minutesLate = minutesLate
    }

    private enum CodingKeys: String, CodingKey {
        case isLate = "is_late"
        case minutesLate = "minutes_late"
    }

    /// Tolerant: a missing or mistyped value reads as "not late" / "no minutes".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let late: Bool? = try? c.decodeIfPresent(Bool.self, forKey: .isLate)
        isLate = late ?? false
        if let i = try? c.decodeIfPresent(Int.self, forKey: .minutesLate) {
            minutesLate = i
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .minutesLate), d.isFinite, abs(d) < 1_000_000 {
            minutesLate = Int(d)
        } else {
            minutesLate = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isLate, forKey: .isLate)
        try c.encodeIfPresent(minutesLate, forKey: .minutesLate)
    }
}

/// What the screens show about lateness. Pure, so it is unit-tested.
enum AttendanceLate {

    /// "Late by 45 min" for a record the API marked late; nil when it has no `late` block (no rules configured) or is
    /// not late. `is_late` with no minutes reads just "Late".
    static func label(_ late: AttendanceLateInfo?) -> String? {
        guard let late = late, late.isLate else { return nil }
        let minutes: Int = late.minutesLate ?? 0
        return minutes > 0 ? "Late by \(minutes) min" : "Late"
    }

    /// True when the client reports late info at all (some record carries a `late` block, even a not-late one) — the
    /// cue to show the "Late" tally. False for every client without shift rules.
    static func showsLateInfo(history: [AttendanceRecord], today: AttendanceRecord?) -> Bool {
        if today?.late != nil { return true }
        return history.contains(where: { $0.late != nil })
    }

    /// How many of the records are late days. A late day still COUNTS as present (late is a subset of present).
    static func lateCount(_ records: [AttendanceRecord]) -> Int {
        records.filter { $0.checkinAt != nil && $0.late?.isLate == true }.count
    }
}
