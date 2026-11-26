//
//  PingQueuePolicyTests.swift
//  KinematicTests
//
//  The offline ping queue's rules (PingQueuePolicy): pure Foundation. Mirrors the Android
//  PingQueuePolicyTest. A live heartbeat that can't upload for a connectivity reason is queued and
//  replayed on reconnect with its original capture time; these decide what is queued, what is still
//  worth sending, and how the capture time is formatted for the server.
//

import XCTest
@testable import Kinematic

final class PingQueuePolicyTests: XCTestCase {

    // MARK: shouldEnqueue

    func testQueuesAConnectivityFailureForATrackingTenantWithAFix() {
        XCTAssertTrue(PingQueuePolicy.shouldEnqueue(trackingApplies: true, hasFix: true, retryable: true))
    }

    func testNeverQueuesForANonTrackingTenant() {
        XCTAssertFalse(PingQueuePolicy.shouldEnqueue(trackingApplies: false, hasFix: true, retryable: true))
    }

    func testNeverQueuesWithoutARealFix() {
        XCTAssertFalse(PingQueuePolicy.shouldEnqueue(trackingApplies: true, hasFix: false, retryable: true))
    }

    func testNeverQueuesAFinalAnswer() {
        // A 4xx / success:false is not retryable — replay would never succeed, so it is not queued.
        XCTAssertFalse(PingQueuePolicy.shouldEnqueue(trackingApplies: true, hasFix: true, retryable: false))
    }

    // MARK: freshness / pruning

    func testARecentFixIsFresh() {
        let now = Date()
        XCTAssertTrue(PingQueuePolicy.isFresh(capturedAt: now.addingTimeInterval(-60), now: now))
    }

    func testAFixAtTheAgeLimitIsStillFresh() {
        let now = Date()
        XCTAssertTrue(PingQueuePolicy.isFresh(capturedAt: now.addingTimeInterval(-PingQueuePolicy.maxAge), now: now))
    }

    func testAFixPastTheAgeLimitIsStale() {
        let now = Date()
        XCTAssertFalse(PingQueuePolicy.isFresh(capturedAt: now.addingTimeInterval(-PingQueuePolicy.maxAge - 1), now: now))
    }

    func testPruneCutoffIsOneMaxAgeBeforeNow() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertEqual(PingQueuePolicy.pruneCutoff(now: now), now.addingTimeInterval(-PingQueuePolicy.maxAge))
    }

    func testQueueMaxAgeStaysUnderTheServer36hWindow() {
        // A fix that survives in the queue must still be honoured (not dropped) when it flushes.
        XCTAssertLessThan(PingQueuePolicy.maxAge, 36 * 3600)
    }

    // MARK: captured_at formatting

    func testFormatsCapturedAtAsIsoUtcWholeSecondsWithZ() {
        let date = Date(timeIntervalSince1970: 1_764_043_391) // 2025-11-25T04:03:11Z
        XCTAssertEqual(PingQueuePolicy.formatCapturedAt(date), "2025-11-25T04:03:11Z")
    }

    func testTruncatesSubSecondToWholeSeconds() {
        let date = Date(timeIntervalSince1970: 1_764_043_391.777)
        XCTAssertEqual(PingQueuePolicy.formatCapturedAt(date), "2025-11-25T04:03:11Z")
    }
}
