//
//  AttendancePunch.swift
//  Kinematic
//
//  The small, pure rules of the GPS-ONLY check-in / check-out: what the Home / Attendance screens call things when a
//  client's attendance rule says no selfie (`selfie_required: false`), whether a remembered GPS fix is recent enough to
//  stand in for a fresh one, and when a selfie is demanded. Unit-tested (KinematicTests/AttendancePunchTests).
//
//  The flow itself lives in `AttendanceViewModel` (ViewModels/AttendanceViewModel+Punch.swift): a single tap, a fresh
//  location, then the same `toggleAttendance` path the camera uses — with no photo. A client that has not turned the
//  rule off (or whose rules have never loaded) sees EXACTLY the strings and camera flow it always had: every function
//  below returns the original text when `selfieRequired` is true.
//

import Foundation

enum AttendancePunch {

    /// A last-known fix older than this is not "where the rep is now".
    static let maxLastFixAge: TimeInterval = 60

    /// A fix timestamped slightly in the future (a clock that moved) is still fine; further than this is not.
    static let maxClockSkew: TimeInterval = 5

    /// How long a GPS-only punch waits for a fresh fix before telling the rep to try again.
    static let fixTimeout: TimeInterval = 12

    /// May a last-known fix taken at `fixTime` be used at `now`? (A fix with no time is never fresh.)
    static func isFreshEnough(fixTime: Date?, now: Date) -> Bool {
        guard let t = fixTime else { return false }
        let age: TimeInterval = now.timeIntervalSince(t)
        return age >= -maxClockSkew && age <= maxLastFixAge
    }

    /// The Home card's headline. Only the "not checked in yet" state mentions the selfie today, so only it changes.
    /// `hasCheckin` = the record has a check-in (so "Check In to Resume" applies when paused).
    /// With multiple check-in/out per day, a clocked-out rep is "Clocked Out" (they may
    /// clock in again) rather than a terminal "Shift Completed".
    static func headline(shiftEnded: Bool, isIn: Bool, hasCheckin: Bool, selfieRequired: Bool) -> String {
        if shiftEnded { return "Clocked Out" }
        if isIn { return "Shift Active" }
        if hasCheckin { return "Check In to Resume" }
        return selfieRequired ? "Daily Selfie Required" : "Daily Check-In Required"
    }

    /// The Home card's sub-line for the not-checked-in-yet state.
    static func tapHint(selfieRequired: Bool) -> String {
        selfieRequired ? "Tap to complete check-in" : "Tap to check in"
    }

    /// The SF Symbol of the Home card's action glyph (the camera, or a location pin when there
    /// is no selfie). A clocked-out rep can clock in again, so the glyph stays the actionable
    /// check-in symbol rather than a terminal "done" seal.
    static func actionGlyph(shiftEnded: Bool, selfieRequired: Bool) -> String {
        return selfieRequired ? "camera.fill" : "location.fill"
    }

    /// The Attendance screen's check-in button text when no selfie is needed (the selfie text is the one it always had).
    static func checkInButtonTitle(needsSelfie: Bool) -> String {
        needsSelfie ? "TAKE SELFIE TO CHECK IN" : "CHECK IN NOW"
    }

    /// Whether a selfie is demanded for this punch: the rule says so AND the person is a field executive (the server
    /// only insists on a selfie from role `executive`, and only while the rule is on). `isExecutive` is the app's own
    /// existing role test, unchanged.
    static func selfieDemanded(isExecutive: Bool, ruleRequired: Bool) -> Bool {
        isExecutive && ruleRequired
    }

    /// What the rep is told when no usable location arrives for a GPS-only punch.
    static func noFixMessage(isCheckIn: Bool) -> String {
        let verb: String = isCheckIn ? "check in" : "check out"
        return "Couldn't get your location to \(verb). Make sure location is on, move to an open area and try again."
    }

    // MARK: the request

    /// The JSON body of `POST /attendance/checkin` | `/checkout`. Every opt-in field is absent unless it is set, so for a
    /// client that configured nothing the body is exactly what it always was:
    ///  - `transport_mode` — the answer to "How are you travelling today?" (a CHECK-IN only);
    ///  - `captured_at` — the real punch time, from an offline-capable punch only.
    static func requestPayload(isCheckIn: Bool, lat: Double, lng: Double, selfieUrl: String?, battery: Int?,
                               faceScore: Double?, faceVerified: Bool?, faceModelId: String?,
                               isMock: Bool?, locationAccuracyM: Double?,
                               transportMode: String?, capturedAt: String?) -> [String: Any] {
        var payload: [String: Any] = ["latitude": lat, "longitude": lng]
        if let transportMode = transportMode, isCheckIn { payload["transport_mode"] = transportMode }
        if let capturedAt = capturedAt { payload["captured_at"] = capturedAt }
        if let selfie = selfieUrl { payload["selfie_url"] = selfie }
        if let battery = battery { payload["battery_percentage"] = battery }
        // Face-recognition attendance (module face_attendance): the on-device 1:1 match result.
        if let faceScore = faceScore { payload["face_score"] = faceScore }
        if let faceVerified = faceVerified { payload["face_verified"] = faceVerified }
        if let faceModelId = faceModelId { payload["face_model_id"] = faceModelId }
        // GPS-integrity signals (all field-force tenants): is_mock = the fix was software-simulated; accuracy in metres.
        if let isMock = isMock { payload["is_mock"] = isMock }
        if let locationAccuracyM = locationAccuracyM { payload["location_accuracy_m"] = locationAccuracyM }
        return payload
    }

    /// The serialised body. Keys are sorted: the server hashes the body against the Idempotency-Key, so a replay (possibly
    /// after a relaunch) must serialise to exactly the bytes the first attempt did.
    static func requestBody(_ payload: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// `?date=<attendance day>` — only for a punch that belongs to a day other than today (see `OfflinePunch.dateQuery`).
    static func queryItems(dateQuery: String?) -> [URLQueryItem]? {
        guard let d = dateQuery, !d.isEmpty else { return nil }
        return [URLQueryItem(name: "date", value: d)]
    }
}
