import Foundation

/// One check-in → check-out punch within a day, under the multiple-check-in/out-per-day
/// model. `status` is "open" (checked in, not yet out) or "closed". The daily
/// `AttendanceRecord` carries the rollup (first check-in, last check-out, summed minutes);
/// this is the list of individual punches it now also returns in `sessions`.
struct AttendanceSession: Codable {
    let id: String?
    let seq: Int?
    let status: String?
    let checkinAt: String?
    let checkinLatitude: Double?
    let checkinLongitude: Double?
    let checkinSelfieUrl: String?
    let checkoutAt: String?
    let checkoutLatitude: Double?
    let checkoutLongitude: Double?
    let checkoutSelfieUrl: String?
    let workingMinutes: Int?
    let transportMode: String?

    enum CodingKeys: String, CodingKey {
        case id, seq, status
        case checkinAt = "checkin_at"
        case checkinLatitude = "checkin_lat"
        case checkinLongitude = "checkin_lng"
        case checkinSelfieUrl = "checkin_selfie_url"
        case checkoutAt = "checkout_at"
        case checkoutLatitude = "checkout_lat"
        case checkoutLongitude = "checkout_lng"
        case checkoutSelfieUrl = "checkout_selfie_url"
        case workingMinutes = "working_minutes"
        case transportMode = "transport_mode"
    }

    var isOpen: Bool { status == "open" }

    /// "HH:mm" (device-local) for a punch timestamp, or "--" when absent / unparseable.
    static func localTime(_ iso: String?) -> String {
        guard let iso = iso, !iso.isEmpty else { return "--" }
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        guard let date = isoFull.date(from: iso) ?? isoPlain.date(from: iso) else { return "--" }
        let out = DateFormatter()
        out.dateFormat = "HH:mm"
        return out.string(from: date)
    }

    /// Worked time of this session as "Xh Ym" / "Ym", or nil when unknown.
    var durationText: String? {
        guard let m = workingMinutes, m > 0 else { return nil }
        let h = m / 60, mm = m % 60
        return h > 0 ? "\(h)h \(mm)m" : "\(mm)m"
    }
}

extension AttendanceRecord {
    /// The latest punch (highest seq), or nil when the backend sent no session list.
    var latestSession: AttendanceSession? {
        sessions?.max(by: { ($0.seq ?? 0) < ($1.seq ?? 0) })
    }

    /// Clocked in right now — an open punch. Falls back to the flat checkin/checkout pair
    /// when there is no session list (legacy payloads, or an optimistic local record).
    var isClockedIn: Bool {
        if let s = latestSession { return s.status == "open" }
        return checkinAt != nil && checkoutAt == nil
    }

    /// Clocked in earlier today and currently out — the last punch is closed. Drives the
    /// "clocked out" surfaces (and the travel prompt) WITHOUT locking the day: the rep may
    /// clock in again, which opens a new session.
    var hasCheckedOut: Bool {
        if let s = latestSession { return s.status == "closed" }
        return checkinAt != nil && checkoutAt != nil
    }

    /// Today's punches oldest-first, for the attendance screen's punch list.
    var sessionsInOrder: [AttendanceSession] {
        (sessions ?? []).sorted(by: { ($0.seq ?? 0) < ($1.seq ?? 0) })
    }
}
