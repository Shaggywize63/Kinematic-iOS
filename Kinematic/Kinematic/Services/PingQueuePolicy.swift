//
//  PingQueuePolicy.swift
//  Kinematic
//
//  The rules of the OFFLINE PING QUEUE, as pure Foundation so they are unit-tested (see
//  KinematicTests/PingQueuePolicyTests). Mirrors the Android implementation (PingQueuePolicy.kt).
//
//  When a live heartbeat can't be uploaded (the rep is in a no-signal zone), the fix is parked in
//  OfflinePingCache and replayed on reconnect with its original capture time, so the server backfills
//  the trail. This decides what is queued, which rows are still worth sending, and how the capture time
//  is formatted for the server.
//

import Foundation

enum PingQueuePolicy {

    /// Keep queued fixes at most this long. Deliberately UNDER the server's 36h `captured_at` window, so a
    /// fix that survives in the queue is always still honoured when it flushes, never silently dropped.
    static let maxAge: TimeInterval = 24 * 3600

    /// Hard cap on queued rows per rep, so a very long outage can't grow the store without bound.
    static let maxQueue = 2000

    /// Most fixes to replay in one flush pass — a backlog drains over several heartbeats, not one burst.
    static let flushBatch = 200

    /// Queue a failed live heartbeat only when all hold:
    ///  - `trackingApplies`: this tenant uses live tracking (never queue for an opted-out tenant),
    ///  - `hasFix`: a real GPS fix, not the 0,0 "no fix" sentinel,
    ///  - `retryable`: the send failed for a CONNECTIVITY reason (a `URLError`). A server answer (4xx /
    ///    success:false) is final and would never succeed on replay, so it is not queued.
    static func shouldEnqueue(trackingApplies: Bool, hasFix: Bool, retryable: Bool) -> Bool {
        trackingApplies && hasFix && retryable
    }

    /// A queued fix is still worth flushing when it is no older than `maxAge` at `now`.
    static func isFresh(capturedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(capturedAt) <= maxAge
    }

    /// The oldest capture time still kept at `now`; anything before it is pruned, never sent.
    static func pruneCutoff(now: Date) -> Date {
        now.addingTimeInterval(-maxAge)
    }

    /// Capture time as the server's `captured_at` parser wants it: ISO-8601 UTC, whole seconds, `Z`
    /// (e.g. `2026-11-25T04:03:11Z`). Reuses the attendance queue's formatter so both are identical.
    static func formatCapturedAt(_ date: Date) -> String {
        OfflinePunch.formatCapturedAt(date)
    }
}
