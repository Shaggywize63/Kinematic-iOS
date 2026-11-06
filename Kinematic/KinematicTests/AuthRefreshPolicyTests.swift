//
//  AuthRefreshPolicyTests.swift
//  KinematicTests
//
//  What keeps a phone signed in. These are the ways the app used to sign people out on its own: any 4xx from the
//  refresh endpoint (429 / 403 / 404 / 408 included) treated as "refresh token rejected", a 200 reply it could not read
//  treated as "dead", a second refresh for the same stale token, and a Keychain read that failed (device not yet
//  unlocked after boot) being remembered as "no token".
//

import XCTest
import Security
@testable import Kinematic

@MainActor
final class AuthRefreshPolicyTests: XCTestCase {

    private func body(_ json: String) -> Data { Data(json.utf8) }

    // MARK: - what is a dead session

    func testOnly400And401SayTheRefreshTokenIsDead() {
        XCTAssertTrue(AuthRefreshPolicy.isDefinitiveRejection(status: 400))
        XCTAssertTrue(AuthRefreshPolicy.isDefinitiveRejection(status: 401))
    }

    func testRateLimitsProxyAnswersAndServerErrorsAreNotAVerdict() {
        for status in [0, 403, 404, 408, 413, 422, 429, 500, 502, 503, 504] {
            XCTAssertFalse(AuthRefreshPolicy.isDefinitiveRejection(status: status), "status \(status)")
            XCTAssertEqual(AuthRefreshPolicy.outcome(status: status, body: body("{}")), .transient, "status \(status)")
        }
    }

    func testRejectedWhateverTheBodySays() {
        XCTAssertEqual(AuthRefreshPolicy.outcome(status: 401, body: body(#"{"success":false,"error":"Invalid or expired refresh token"}"#)), .rejected)
        XCTAssertEqual(AuthRefreshPolicy.outcome(status: 400, body: Data()), .rejected)
    }

    // MARK: - reading a 200

    func testASuccessfulRefreshCarriesBothTokens() {
        let json = #"{"success":true,"data":{"access_token":"A2","refresh_token":"R2","expires_at":99,"project":"kinematic"}}"#
        XCTAssertEqual(AuthRefreshPolicy.outcome(status: 200, body: body(json)), .refreshed(accessToken: "A2", refreshToken: "R2"))
    }

    func testAReplyWithoutANewRefreshTokenKeepsTheOldOne() {
        XCTAssertEqual(AuthRefreshPolicy.outcome(status: 200, body: body(#"{"success":true,"data":{"access_token":"A2"}}"#)),
                       .refreshed(accessToken: "A2", refreshToken: nil))
        XCTAssertEqual(AuthRefreshPolicy.outcome(status: 200, body: body(#"{"success":true,"data":{"access_token":"A2","refresh_token":""}}"#)),
                       .refreshed(accessToken: "A2", refreshToken: nil))
    }

    func testA200WeCannotUseIsNotAVerdictEitherWay() {
        let unusable = [
            "",
            "not json",
            #"{"success":false}"#,
            #"{"success":true}"#,
            #"{"success":true,"data":{"access_token":""}}"#,
            #"{"success":true,"data":{}}"#,
        ]
        for json in unusable {
            XCTAssertEqual(AuthRefreshPolicy.outcome(status: 200, body: body(json)), .transient, json)
        }
    }

    // MARK: - one refresh per stale token

    func testACallerThatFailedJustBeforeARefreshFinishedReusesIt() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(AuthRefreshPolicy.shouldReuseRecentRefresh(lastSuccess: t, now: t.addingTimeInterval(0.2)))
        XCTAssertTrue(AuthRefreshPolicy.shouldReuseRecentRefresh(lastSuccess: t, now: t.addingTimeInterval(4.9)))
    }

    func testAnOldRefreshIsNotReused() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(AuthRefreshPolicy.shouldReuseRecentRefresh(lastSuccess: t, now: t.addingTimeInterval(5)))
        XCTAssertFalse(AuthRefreshPolicy.shouldReuseRecentRefresh(lastSuccess: t, now: t.addingTimeInterval(3600)))
        XCTAssertFalse(AuthRefreshPolicy.shouldReuseRecentRefresh(lastSuccess: nil, now: t))
        // A clock that went backwards must not look "recent".
        XCTAssertFalse(AuthRefreshPolicy.shouldReuseRecentRefresh(lastSuccess: t, now: t.addingTimeInterval(-10)))
    }

    // MARK: - Keychain: a failed read is not "no token"

    func testOnlyItemNotFoundMayBeRememberedAsAbsent() {
        XCTAssertTrue(KeychainReadPolicy.shouldCacheAbsence(status: errSecItemNotFound))
    }

    func testALockedOrFailingKeychainIsNeverRememberedAsAbsent() {
        // errSecInteractionNotAllowed: device not unlocked since boot (background launch). errSecNotAvailable /
        // errSecAuthFailed / errSecIO: the Keychain could not answer. None of these mean "signed out".
        for status in [errSecInteractionNotAllowed, errSecNotAvailable, errSecAuthFailed, errSecIO, errSecDecode, errSecParam] {
            XCTAssertFalse(KeychainReadPolicy.shouldCacheAbsence(status: status), "status \(status)")
        }
    }
}
