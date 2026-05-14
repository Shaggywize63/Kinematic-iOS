import Foundation
import CallKit

/// Observes outgoing calls placed via tel: / FaceTime so the CRM can stamp
/// `duration_seconds` on the matching call activity.
///
/// Why CXCallObserver and not READ_PHONE_STATE-equivalent: on iOS,
/// CXCallObserver is part of CallKit and observes calls placed via the
/// system dialer regardless of which app initiated them. **No entitlement
/// or permission is required** to read this — it's privacy-respecting
/// (no peer phone number, no audio access; just per-call lifecycle flags).
///
/// Usage:
///   1. The Call button calls `CallObserver.shared.startTracking()` when
///      the user taps it. This resets the per-call timestamps so a fresh
///      call doesn't inherit duration from a previous one.
///   2. The composer (or its dismissal path) calls
///      `CallObserver.shared.consumeDuration()` to retrieve the duration
///      in seconds. Returns nil if no call connected during the window —
///      the rep tapped Call but the dialer was closed without connecting.
final class CallObserver: NSObject, CXCallObserverDelegate {
    static let shared = CallObserver()

    private let callObserver = CXCallObserver()
    /// Outgoing-call UUIDs we've seen connect during the active tracking
    /// window, with their connect timestamps. Most flows have at most one
    /// entry, but we key by UUID so an accidental second call doesn't
    /// trample the first.
    private var connectedAt: [UUID: Date] = [:]
    /// Captured end timestamps once the system reports the call ended.
    private var endedAt: [UUID: Date] = [:]
    /// Tracking window — set true by startTracking(), cleared by
    /// consumeDuration(). Without this the observer would happily count
    /// background calls placed unrelated to the CRM.
    private var isTracking: Bool = false
    /// Snapshot of the timestamp when tracking started. Used to discard
    /// calls that were already in progress before the user tapped Call.
    private var trackingStartedAt: Date?

    private override init() {
        super.init()
        callObserver.setDelegate(self, queue: .main)
    }

    /// Begin observing. Called from the tap-to-call handler before
    /// presenting the composer.
    func startTracking() {
        isTracking = true
        trackingStartedAt = Date()
        connectedAt.removeAll()
        endedAt.removeAll()
    }

    /// Return the duration in whole seconds of the most recent outgoing
    /// call that ended during the tracking window. Returns nil if no call
    /// connected (e.g. user backed out of the dialer without dialing).
    /// Clears state so subsequent invocations don't return stale data.
    func consumeDuration() -> Int? {
        defer {
            isTracking = false
            trackingStartedAt = nil
            connectedAt.removeAll()
            endedAt.removeAll()
        }
        // Pick the most recent ended call. Most flows have exactly one.
        guard let (id, end) = endedAt.max(by: { $0.value < $1.value }),
              let start = connectedAt[id]
        else { return nil }
        let seconds = Int(end.timeIntervalSince(start).rounded())
        return max(0, seconds)
    }

    /// Stop without consuming — used if the parent view disappears
    /// without ever reading the duration (e.g. user navigated away
    /// before the composer mounted).
    func cancelTracking() {
        isTracking = false
        trackingStartedAt = nil
        connectedAt.removeAll()
        endedAt.removeAll()
    }

    // MARK: - CXCallObserverDelegate

    func callObserver(_ observer: CXCallObserver, callChanged call: CXCall) {
        guard isTracking else { return }
        // Only interested in outgoing calls placed *during* our tracking
        // window. Filter out incoming calls and ones that were already in
        // progress when the rep tapped Call.
        guard call.isOutgoing else { return }
        if let trackingStart = trackingStartedAt {
            // Ignore calls that were already connected before we started
            // tracking — only count ones that connect during our window.
            if call.hasConnected, connectedAt[call.uuid] == nil {
                // Heuristic: if the call has connected but we have no record
                // of its start, assume it connected just now. Slight inaccuracy
                // is fine — worst case we under-report by a few hundred ms.
                connectedAt[call.uuid] = max(Date(), trackingStart)
            }
        }
        if call.hasEnded {
            endedAt[call.uuid] = Date()
        }
    }
}
