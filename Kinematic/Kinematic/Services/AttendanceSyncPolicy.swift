// AttendanceSyncPolicy — what a failed attendance punch means, as pure functions so it is unit-tested
// (see KinematicTests/AttendanceSyncPolicyTests) and the screens only act on the answer.
//
// The rule it enforces: "Saved offline — will sync" and the queued retry are for failures that are
// about getting through to the server — no network, a timeout, a server that is down or busy. Anything
// the server actually answered with a refusal (a 4xx, a `success: false` body) is not a connectivity
// problem: the person is shown the server's own message, the optimistic check-in / check-out is rolled
// back, and the queued row is dropped — retrying a refusal can only be refused again, forever.

import Foundation

/// How a failed attendance punch is treated.
enum AttendanceFailureKind: Equatable {
    /// Nothing is wrong with the punch itself: no network, a timeout, or the server answered 408 / 429 / 5xx.
    /// Keep it queued (same Idempotency-Key) and retry later.
    case transient
    /// The server's "turn on location" backstop (`details.code == "LOCATION_REQUIRED"`).
    case locationRequired
    /// 401 even after the silent token refresh: the person has to sign in again. The punch is not at fault.
    case authRequired
    /// Anything else: the server looked at this punch and said no (or the request can never succeed as sent).
    /// Show its message, undo the optimistic state, never replay.
    case rejected
}

/// What came back from one attendance call.
struct AttendanceSubmitResult {
    let success: Bool
    /// The server's record of the day, when it sent one with the success.
    let record: AttendanceRecord?
    /// What to tell the person: the server's own words, else a plain line. Nil on success.
    let message: String?
    /// Nil on success.
    let failure: AttendanceFailureKind?
    let httpStatus: Int?

    static func ok(record: AttendanceRecord?, httpStatus: Int?) -> AttendanceSubmitResult {
        AttendanceSubmitResult(success: true, record: record, message: nil, failure: nil, httpStatus: httpStatus)
    }

    static func failed(_ kind: AttendanceFailureKind, message: String?, httpStatus: Int?) -> AttendanceSubmitResult {
        AttendanceSubmitResult(success: false, record: nil, message: message, failure: kind, httpStatus: httpStatus)
    }
}

enum AttendanceSyncPolicy {
    /// Transport failures that mean "the network is not there right now". A superset of the list the visit and
    /// form queues already use (not-connected, timed-out, cannot-connect, connection-lost, data-not-allowed),
    /// plus the DNS and roaming/call errors a phone gets when it is half-offline.
    static let transientURLErrorCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .timedOut, .cannotConnectToHost, .networkConnectionLost, .dataNotAllowed,
        .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .callIsActive,
    ]

    static func isTransient(urlError code: URLError.Code) -> Bool { transientURLErrorCodes.contains(code) }

    /// 408 Request Timeout, 429 Too Many Requests and every 5xx are worth retrying; other statuses are answers.
    static func isTransient(httpStatus status: Int) -> Bool { status == 408 || status == 429 || (500...599).contains(status) }

    /// Classify a failed call. `urlErrorCode` is set when the request itself failed (no response); `httpStatus`
    /// is the status of the response when there was one (even if its body could not be read); `serverCode` is
    /// the body's `details.code`.
    static func classify(urlErrorCode: URLError.Code?, httpStatus: Int?, serverCode: String?) -> AttendanceFailureKind {
        if let code = urlErrorCode { return isTransient(urlError: code) ? .transient : .rejected }
        if serverCode == "LOCATION_REQUIRED" { return .locationRequired }
        if let status = httpStatus {
            if status == 401 { return .authRequired }
            if isTransient(httpStatus: status) { return .transient }
        }
        return .rejected
    }

    /// What the queue drain does with a row whose send failed this way.
    enum QueueAction: Equatable {
        /// Leave the row queued and stop draining: the rest would fail the same way, and order matters.
        case keepAndStop
        /// The row can never succeed as it is: mark it rejected and carry on with the next one.
        case drop
    }

    static func queueAction(for kind: AttendanceFailureKind) -> QueueAction {
        switch kind {
        case .transient, .authRequired:   return .keepAndStop
        case .locationRequired, .rejected: return .drop
        }
    }

    /// The order the queue is drained in: oldest first, so a check-out never goes ahead of its check-in.
    static func drainOrder(_ rows: [PendingAttendance]) -> [PendingAttendance] {
        rows.sorted { $0.createdAt < $1.createdAt }
    }

    /// A reply the app could not read still counts as success when the server said 2xx: the punch was accepted.
    static func acceptedDespiteUnreadableReply(httpStatus: Int?) -> Bool {
        guard let status = httpStatus else { return false }
        return (200..<300).contains(status)
    }

    /// The toast for a punch that was queued instead of sent.
    static func savedOfflineMessage(httpStatus: Int?) -> String {
        if let status = httpStatus, isTransient(httpStatus: status) {
            return "Saved — the server is busy, will sync shortly"
        }
        return "Saved offline — will sync when network is available"
    }

    /// What to show for a failed call: the server's own message when it sent one, else a plain line for the
    /// kind of failure, else `fallback`. Never a raw system error string.
    static func userMessage(serverMessage: String?, urlErrorCode: URLError.Code?, httpStatus: Int?, fallback: String) -> String {
        if let code = urlErrorCode {
            switch code {
            case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost, .internationalRoamingOff, .callIsActive:
                return "No internet connection — check your network and try again."
            case .timedOut:
                return "The request timed out — check your network and try again."
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Couldn't reach the server — try again in a moment."
            default:
                break
            }
        }
        if let m = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { return m }
        if let status = httpStatus {
            if status == 401 { return "Your session has expired — sign in again." }
            if status == 403 { return "You don't have permission to do that." }
            if isTransient(httpStatus: status) { return "The server is busy — try again in a moment." }
        }
        return fallback
    }

    /// Same, for a thrown error.
    static func userMessage(for error: Error, httpStatus: Int?, fallback: String) -> String {
        userMessage(serverMessage: nil, urlErrorCode: (error as? URLError)?.code, httpStatus: httpStatus, fallback: fallback)
    }
}
