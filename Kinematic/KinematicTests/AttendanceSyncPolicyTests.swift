//
//  AttendanceSyncPolicyTests.swift
//  KinematicTests
//
//  When a check-in / check-out fails: only a failure to get through to the server (no network, a
//  timeout, 408 / 429 / 5xx) is "saved offline — will sync" and stays queued. A server refusal shows its
//  own message, rolls the optimistic state back and is never replayed. Plus the tolerant `error`
//  decoding that stops a refusal from being mistaken for a network failure.
//

import XCTest
@testable import Kinematic

final class AttendanceSyncPolicyTests: XCTestCase {

    // MARK: - classify

    func testTransportFailuresAreTransient() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .timedOut, .cannotConnectToHost, .networkConnectionLost, .dataNotAllowed,
            .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .callIsActive,
        ]
        for c in codes {
            XCTAssertEqual(AttendanceSyncPolicy.classify(urlErrorCode: c, httpStatus: nil, serverCode: nil), .transient, "\(c)")
        }
    }

    func testOtherTransportErrorsAreNotRetriedBlindly() {
        // Not "the network is away": a cancelled request, a bad URL, a TLS failure, an unreadable reply.
        let codes: [URLError.Code] = [.cancelled, .badURL, .secureConnectionFailed, .badServerResponse, .cannotDecodeContentData, .unsupportedURL]
        for c in codes {
            XCTAssertEqual(AttendanceSyncPolicy.classify(urlErrorCode: c, httpStatus: nil, serverCode: nil), .rejected, "\(c)")
        }
    }

    func testTimeoutsRateLimitsAndServerErrorsAreTransient() {
        for status in [408, 429, 500, 501, 502, 503, 504, 599] {
            XCTAssertEqual(AttendanceSyncPolicy.classify(urlErrorCode: nil, httpStatus: status, serverCode: nil), .transient, "\(status)")
            XCTAssertTrue(AttendanceSyncPolicy.isTransient(httpStatus: status))
        }
    }

    func testAnAnswerFromTheServerIsNotAConnectivityProblem() {
        for status in [200, 201, 400, 403, 404, 409, 410, 422, 451, 600, 0] {
            XCTAssertEqual(AttendanceSyncPolicy.classify(urlErrorCode: nil, httpStatus: status, serverCode: nil), .rejected, "\(status)")
            XCTAssertFalse(AttendanceSyncPolicy.isTransient(httpStatus: status))
        }
        // Nothing known at all is not "offline" either.
        XCTAssertEqual(AttendanceSyncPolicy.classify(urlErrorCode: nil, httpStatus: nil, serverCode: nil), .rejected)
    }

    func testAnExpiredSignInIsItsOwnKind() {
        XCTAssertEqual(AttendanceSyncPolicy.classify(urlErrorCode: nil, httpStatus: 401, serverCode: nil), .authRequired)
    }

    func testTheLocationBackstopIsRecognisedFromTheBody() {
        XCTAssertEqual(AttendanceSyncPolicy.classify(urlErrorCode: nil, httpStatus: 400, serverCode: "LOCATION_REQUIRED"), .locationRequired)
        XCTAssertEqual(AttendanceSyncPolicy.classify(urlErrorCode: nil, httpStatus: 422, serverCode: "LOCATION_REQUIRED"), .locationRequired)
        // Another code is just a refusal; and when the request never got through, the network error wins.
        XCTAssertEqual(AttendanceSyncPolicy.classify(urlErrorCode: nil, httpStatus: 400, serverCode: "ALREADY_CHECKED_IN"), .rejected)
        XCTAssertEqual(AttendanceSyncPolicy.classify(urlErrorCode: .timedOut, httpStatus: nil, serverCode: "LOCATION_REQUIRED"), .transient)
    }

    // MARK: - what the queue does

    func testOnlyAFailureToGetThroughKeepsARowQueued() {
        XCTAssertEqual(AttendanceSyncPolicy.queueAction(for: .transient), .keepAndStop)
        XCTAssertEqual(AttendanceSyncPolicy.queueAction(for: .authRequired), .keepAndStop)
        // A refusal is never replayed (it could only be refused again, forever).
        XCTAssertEqual(AttendanceSyncPolicy.queueAction(for: .rejected), .drop)
        XCTAssertEqual(AttendanceSyncPolicy.queueAction(for: .locationRequired), .drop)
    }

    private func row(_ kind: String, at seconds: TimeInterval) -> PendingAttendance {
        PendingAttendance(id: UUID(), idempotencyKey: "k-\(kind)-\(seconds)", userKey: "u", kind: kind, lat: 1, lng: 2,
                          selfieUrl: nil, battery: nil, createdAt: Date(timeIntervalSince1970: seconds),
                          attempt: 0, lastError: nil, isSynced: false)
    }

    func testTheQueueIsDrainedOldestFirstSoACheckOutNeverPrecedesItsCheckIn() {
        // The cache keeps newest first (rows.insert(at: 0)); the drain must not follow that order.
        let newestFirst = [row("checkout", at: 200), row("checkin", at: 100)]
        XCTAssertEqual(AttendanceSyncPolicy.drainOrder(newestFirst).map { $0.kind }, ["checkin", "checkout"])
    }

    func testAnAcceptedPunchWithAnUnreadableReplyIsStillSuccess() {
        for status in [200, 201, 204, 299] { XCTAssertTrue(AttendanceSyncPolicy.acceptedDespiteUnreadableReply(httpStatus: status), "\(status)") }
        for status in [199, 301, 400, 500, 502] { XCTAssertFalse(AttendanceSyncPolicy.acceptedDespiteUnreadableReply(httpStatus: status), "\(status)") }
        XCTAssertFalse(AttendanceSyncPolicy.acceptedDespiteUnreadableReply(httpStatus: nil))
    }

    // MARK: - what the person is told

    func testTheSavedOfflineToastNamesTheRealReason() {
        XCTAssertEqual(AttendanceSyncPolicy.savedOfflineMessage(httpStatus: nil), "Saved offline — will sync when network is available")
        XCTAssertEqual(AttendanceSyncPolicy.savedOfflineMessage(httpStatus: 503), "Saved — the server is busy, will sync shortly")
        XCTAssertEqual(AttendanceSyncPolicy.savedOfflineMessage(httpStatus: 429), "Saved — the server is busy, will sync shortly")
    }

    func testAFailureIsShownInPlainWordsNeverARawSystemError() {
        func msg(server: String? = nil, url: URLError.Code? = nil, status: Int? = nil) -> String {
            AttendanceSyncPolicy.userMessage(serverMessage: server, urlErrorCode: url, httpStatus: status, fallback: "Failed")
        }
        XCTAssertEqual(msg(url: .notConnectedToInternet), "No internet connection — check your network and try again.")
        XCTAssertEqual(msg(url: .timedOut), "The request timed out — check your network and try again.")
        XCTAssertEqual(msg(url: .cannotConnectToHost), "Couldn't reach the server — try again in a moment.")
        // The server's own words win over a status line.
        XCTAssertEqual(msg(server: "You are outside the allowed area.", status: 403), "You are outside the allowed area.")
        XCTAssertEqual(msg(server: "  ", status: 403), "You don't have permission to do that.")
        XCTAssertEqual(msg(status: 401), "Your session has expired — sign in again.")
        XCTAssertEqual(msg(status: 503), "The server is busy — try again in a moment.")
        XCTAssertEqual(msg(status: 400), "Failed")
        XCTAssertEqual(msg(), "Failed")
        XCTAssertEqual(AttendanceSyncPolicy.userMessage(for: URLError(.notConnectedToInternet), httpStatus: nil, fallback: "x"),
                       "No internet connection — check your network and try again.")
    }

    // MARK: - the response envelope

    private func decode(_ json: String) throws -> ApiResponse<[String: String]> {
        try JSONDecoder().decode(ApiResponse<[String: String]>.self, from: Data(json.utf8))
    }

    func testAStringErrorStillDecodes() throws {
        let r = try decode(#"{"success":false,"error":"Already checked in","details":{"code":"X"}}"#)
        XCTAssertFalse(r.success)
        XCTAssertEqual(r.error, "Already checked in")
        XCTAssertEqual(r.details?.code, "X")
    }

    func testAnObjectErrorDecodesToItsMessageInsteadOfFailingTheWholeResponse() throws {
        // This used to throw, which the attendance flow read as "couldn't reach the server".
        let r = try decode(#"{"success":false,"error":{"code":"OUTSIDE_GEOFENCE","message":"You are outside the allowed area."}}"#)
        XCTAssertFalse(r.success)
        XCTAssertEqual(r.error, "You are outside the allowed area.")
        // An object with no message, null, or something else entirely: no text, but still a readable response.
        XCTAssertNil(try decode(#"{"success":false,"error":{"code":"X"}}"#).error)
        XCTAssertNil(try decode(#"{"success":false,"error":null}"#).error)
        XCTAssertNil(try decode(#"{"success":false,"error":42}"#).error)
    }

    func testExtrasOfTheWrongTypeAreDroppedNotFatal() throws {
        let r = try decode(#"{"success":true,"data":{"id":"a"},"message":{"x":1},"details":"nope"}"#)
        XCTAssertTrue(r.success)
        XCTAssertEqual(r.data?["id"], "a")
        XCTAssertNil(r.message)
        XCTAssertNil(r.details)
        XCTAssertEqual(try decode(#"{"success":true,"message":"ok"}"#).message, "ok")
    }

    func testTheSuccessFlagIsStillRequired() {
        XCTAssertThrowsError(try decode(#"{"error":"x"}"#))
    }

    // MARK: - rows queued by an older build

    func testARowQueuedBeforeTheNewFieldsStillLoads() throws {
        let json = """
        {"id":"7B2F1C0E-0000-4000-8000-000000000001","idempotencyKey":"att-ci-1","userKey":"abc","kind":"checkin",
         "lat":18.5,"lng":73.8,"selfieUrl":null,"battery":80,"createdAt":780000000,"attempt":2,"lastError":"x","isSynced":false}
        """
        let row = try JSONDecoder().decode(PendingAttendance.self, from: Data(json.utf8))
        XCTAssertEqual(row.kind, "checkin")
        XCTAssertEqual(row.attempt, 2)
        XCTAssertNil(row.faceScore)
        XCTAssertNil(row.isMock)
        XCTAssertNil(row.rejectedReason)
    }

    func testTheEvidenceAndTheRefusalSurviveASaveAndLoad() throws {
        var r = row("checkin", at: 100)
        r.faceScore = 0.91; r.faceVerified = true; r.faceModelId = "m1"; r.isMock = false; r.locationAccuracyM = 12.5
        r.rejectedReason = "You are outside the allowed area."
        let back = try JSONDecoder().decode(PendingAttendance.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.faceScore, 0.91)
        XCTAssertEqual(back.faceVerified, true)
        XCTAssertEqual(back.faceModelId, "m1")
        XCTAssertEqual(back.isMock, false)
        XCTAssertEqual(back.locationAccuracyM, 12.5)
        XCTAssertEqual(back.rejectedReason, "You are outside the allowed area.")
    }
}
