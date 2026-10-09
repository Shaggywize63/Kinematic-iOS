//
//  QueueOwnershipTests.swift
//  KinematicTests
//
//  The offline queues used to be keyed by the last 24 characters of the access token, which every silent
//  refresh replaces — so a row queued earlier no longer matched its own user and was never sent. They are now
//  keyed by the stable user id. These pin the key itself and the careful migration of rows queued under the old
//  key: nothing is lost, nothing is ever adopted by the wrong person.
//

import XCTest
@testable import Kinematic

final class QueueOwnershipTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)     // the moment this login began
    private func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

    /// An access token whose last 24 characters are `tail` (padded to 24).
    private func token(_ tail: String) -> String {
        "eyJhbGciOi.header.payload." + String(repeating: "x", count: max(0, 24 - tail.count)) + tail
    }

    private func who(user: String? = "user-1", token tok: String = "", start: Date? = nil) -> QueueOwnership.Identity {
        QueueOwnership.Identity(userId: user, token: tok, sessionStart: start)
    }

    private func row(_ key: String, hoursAfterLogin: Double, kind: String = "checkin") -> PendingAttendance {
        PendingAttendance(id: UUID(), idempotencyKey: "k-\(UUID().uuidString)", userKey: key, kind: kind, lat: 1, lng: 2,
                          selfieUrl: nil, battery: nil, createdAt: at(hoursAfterLogin), attempt: 0, lastError: nil, isSynced: false)
    }

    // MARK: - the keys

    func testTheLegacyKeyIsTheLast24CharactersOfTheToken() {
        XCTAssertEqual(QueueOwnership.legacyKey(token: "abcdefghijklmnopqrstuvwxyz0123456789"), "mnopqrstuvwxyz0123456789")
        XCTAssertEqual(QueueOwnership.legacyKey(token: "short"), "short")
        XCTAssertEqual(QueueOwnership.legacyKey(token: ""), "")
    }

    func testANewRowIsKeyedByTheUserNotTheToken() {
        XCTAssertEqual(QueueOwnership.keyForNewRow(who(user: "user-1", token: token("AAAA"))), "u:user-1")
        // Same key before and after a token refresh — the whole point.
        XCTAssertEqual(QueueOwnership.keyForNewRow(who(user: "user-1", token: token("BBBB"))), "u:user-1")
        // Only while the user id is not known yet does it fall back, so a row is never written without an owner.
        XCTAssertEqual(QueueOwnership.keyForNewRow(who(user: nil, token: token("AAAA"))), QueueOwnership.legacyKey(token: token("AAAA")))
        XCTAssertEqual(QueueOwnership.keyForNewRow(who(user: "", token: token("AAAA"))), QueueOwnership.legacyKey(token: token("AAAA")))
    }

    func testATokenSuffixCanNeverLookLikeAUserKey() {
        // Token suffixes are base64url ([A-Za-z0-9_-]); a user key starts with "u:".
        XCTAssertTrue(QueueOwnership.isLegacy(QueueOwnership.legacyKey(token: token("abc_-DEF"))))
        XCTAssertFalse(QueueOwnership.isLegacy("u:user-1"))
    }

    // MARK: - ownership

    func testARowSurvivesTheTokenBeingRefreshed() {
        let r = row("u:user-1", hoursAfterLogin: 1)
        XCTAssertTrue(QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: who(token: token("AAAA"))))
        XCTAssertTrue(QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: who(token: token("ZZZZ"))))
    }

    func testAnotherUsersRowIsNeverOwned() {
        let r = row("u:user-2", hoursAfterLogin: 1)
        XCTAssertFalse(QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: who(token: token("AAAA"), start: t0)))
        XCTAssertNil(QueueOwnership.migratedKey(rowKey: r.userKey, createdAt: r.createdAt, identity: who(token: token("AAAA"), start: t0)))
    }

    // MARK: - migrating rows queued by older builds

    func testALegacyRowThatStillMatchesTheCurrentTokenIsMigrated() {
        let tok = token("AAAA")
        let r = row(QueueOwnership.legacyKey(token: tok), hoursAfterLogin: 0.2)
        // Even with no idea when the login began, a matching token suffix is proof.
        XCTAssertTrue(QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: who(token: tok, start: nil)))
        XCTAssertEqual(QueueOwnership.migratedKey(rowKey: r.userKey, createdAt: r.createdAt, identity: who(token: tok, start: nil)), "u:user-1")
    }

    func testARowOrphanedByATokenRefreshIsMigratedWhenItWasQueuedDuringThisLogin() {
        // Queued under token AAAA, which has since been refreshed to BBBB: the old build lost it here.
        let r = row(QueueOwnership.legacyKey(token: token("AAAA")), hoursAfterLogin: 3)
        let now = who(token: token("BBBB"), start: t0)
        XCTAssertTrue(QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: now))
        XCTAssertEqual(QueueOwnership.migratedKey(rowKey: r.userKey, createdAt: r.createdAt, identity: now), "u:user-1")
    }

    func testARowFromBeforeThisLoginIsLeftAlone() {
        // Could be this user's earlier session — or someone else's. Not provable, so not adopted (and not deleted).
        let r = row(QueueOwnership.legacyKey(token: token("AAAA")), hoursAfterLogin: -5)
        let now = who(token: token("BBBB"), start: t0)
        XCTAssertFalse(QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: now))
        XCTAssertNil(QueueOwnership.migratedKey(rowKey: r.userKey, createdAt: r.createdAt, identity: now))
    }

    func testWithoutAKnownLoginStartOnlyTheTokenMatchCounts() {
        let r = row(QueueOwnership.legacyKey(token: token("AAAA")), hoursAfterLogin: 3)
        XCTAssertFalse(QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: who(token: token("BBBB"), start: nil)))
    }

    func testAnEmptyTokenNeverMatchesARowQueuedWithoutOne() {
        let r = row("", hoursAfterLogin: 1)
        XCTAssertFalse(QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: who(token: "", start: nil)))
    }

    func testNothingIsRewrittenUntilTheUserIdIsKnown() {
        let tok = token("AAAA")
        let r = row(QueueOwnership.legacyKey(token: tok), hoursAfterLogin: 1)
        let early = who(user: nil, token: tok, start: t0)
        XCTAssertTrue(QueueOwnership.owns(rowKey: r.userKey, createdAt: r.createdAt, identity: early))    // still sent
        XCTAssertNil(QueueOwnership.migratedKey(rowKey: r.userKey, createdAt: r.createdAt, identity: early))
    }

    // MARK: - migrating a whole queue

    func testMigratingAQueueRewritesOnlyWhatIsProvablyTheCurrentUsers() {
        let tok = token("BBBB")
        var rows = [
            row("u:user-1", hoursAfterLogin: 5),                                              // already migrated
            row(QueueOwnership.legacyKey(token: token("AAAA")), hoursAfterLogin: 4),          // orphaned, this login
            row(QueueOwnership.legacyKey(token: tok), hoursAfterLogin: 3),                    // matches the current token
            row(QueueOwnership.legacyKey(token: token("OLD1")), hoursAfterLogin: -30),        // an earlier login
            row("u:user-2", hoursAfterLogin: 2),                                              // someone else's
        ]
        let ids = rows.map { $0.id }
        let changed = QueueOwnership.migrate(&rows, identity: who(token: tok, start: t0))
        XCTAssertEqual(changed, 2)
        XCTAssertEqual(rows.map { $0.userKey }, [
            "u:user-1", "u:user-1", "u:user-1", QueueOwnership.legacyKey(token: token("OLD1")), "u:user-2",
        ])
        // Nothing is lost, nothing is reordered.
        XCTAssertEqual(rows.map { $0.id }, ids)
    }

    func testMigratingTwiceChangesNothingMore() {
        let tok = token("BBBB")
        var rows = [row(QueueOwnership.legacyKey(token: token("AAAA")), hoursAfterLogin: 4)]
        let identity = who(token: tok, start: t0)
        XCTAssertEqual(QueueOwnership.migrate(&rows, identity: identity), 1)
        let after = rows.map { $0.userKey }
        XCTAssertEqual(QueueOwnership.migrate(&rows, identity: identity), 0)
        XCTAssertEqual(rows.map { $0.userKey }, after)
    }

    func testAMigratedRowIsStillTheirsAfterAnotherRefresh() {
        var rows = [row(QueueOwnership.legacyKey(token: token("AAAA")), hoursAfterLogin: 4)]
        QueueOwnership.migrate(&rows, identity: who(token: token("BBBB"), start: t0))
        // Hours later the token has rotated twice more — the old code lost the row here.
        XCTAssertTrue(QueueOwnership.owns(rowKey: rows[0].userKey, createdAt: rows[0].createdAt, identity: who(token: token("DDDD"), start: t0)))
    }

    func testTheNextUserNeverInheritsTheLastUsersMigratedRows() {
        var rows = [row(QueueOwnership.legacyKey(token: token("AAAA")), hoursAfterLogin: 4)]
        QueueOwnership.migrate(&rows, identity: who(user: "user-1", token: token("BBBB"), start: t0))
        // user-2 signs in later (a new login session, a new token).
        let second = who(user: "user-2", token: token("CCCC"), start: at(10))
        XCTAssertFalse(QueueOwnership.owns(rowKey: rows[0].userKey, createdAt: rows[0].createdAt, identity: second))
    }

    // MARK: - how far back a stale-sensitive queue adopts

    func testTheAdoptionFloorIsTheLoginStartOrTheQueuesOwnWindowWhicheverIsLater() {
        let now = at(100)
        XCTAssertNil(QueueOwnership.adoptionFloor(sessionStart: nil, window: 12 * 3600, now: now))
        XCTAssertEqual(QueueOwnership.adoptionFloor(sessionStart: t0, window: nil, now: now), t0)
        // Logged in 100 h ago, window 12 h: nothing older than 12 h is adopted.
        XCTAssertEqual(QueueOwnership.adoptionFloor(sessionStart: t0, window: 12 * 3600, now: now), at(88))
        // Logged in 2 h ago: the login start is the later bound.
        XCTAssertEqual(QueueOwnership.adoptionFloor(sessionStart: at(98), window: 12 * 3600, now: now), at(98))
    }

    func testAStalePunchStaysOnTheDeviceUnsent() {
        // An orphaned check-out from 30 h ago, same login: the server would stamp it with the time it ARRIVES.
        let now = at(100)
        let floor = QueueOwnership.adoptionFloor(sessionStart: t0, window: AttendanceSyncPolicy.legacyAdoptionWindow, now: now)
        let identity = who(token: token("BBBB"), start: floor)
        let stale = row(QueueOwnership.legacyKey(token: token("AAAA")), hoursAfterLogin: 70, kind: "checkout")
        let recent = row(QueueOwnership.legacyKey(token: token("AAAA")), hoursAfterLogin: 95, kind: "checkout")
        XCTAssertFalse(QueueOwnership.owns(rowKey: stale.userKey, createdAt: stale.createdAt, identity: identity))
        XCTAssertTrue(QueueOwnership.owns(rowKey: recent.userKey, createdAt: recent.createdAt, identity: identity))
        XCTAssertEqual(AttendanceSyncPolicy.legacyAdoptionWindow, 12 * 3600)
    }

    // MARK: - rows saved by older builds still load

    func testARowSavedWithAnOldTokenKeyStillDecodesAndKeepsItsKey() throws {
        let json = """
        {"id":"7B2F1C0E-0000-4000-8000-000000000001","idempotencyKey":"att-ci-1","userKey":"mnopqrstuvwxyz0123456789","kind":"checkin",
         "lat":18.5,"lng":73.8,"selfieUrl":null,"battery":80,"createdAt":780000000,"attempt":2,"lastError":"x","isSynced":false}
        """
        let r = try JSONDecoder().decode(PendingAttendance.self, from: Data(json.utf8))
        XCTAssertEqual(r.userKey, "mnopqrstuvwxyz0123456789")
        XCTAssertTrue(QueueOwnership.isLegacy(r.userKey))
        // And a migrated key survives a save and load.
        var moved = [r]
        QueueOwnership.migrate(&moved, identity: who(token: "…" + "mnopqrstuvwxyz0123456789", start: nil))
        let back = try JSONDecoder().decode(PendingAttendance.self, from: JSONEncoder().encode(moved[0]))
        XCTAssertEqual(back.userKey, "u:user-1")
    }
}
