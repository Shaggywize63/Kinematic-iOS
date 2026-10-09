//
//  SessionCleanupTests.swift
//  KinematicTests
//
//  What a sign-out leaves behind: nothing that belongs to the person who signed out. `SessionCleanup` lists the
//  persisted keys that are theirs (the picked client, the location filter, the cached Home / Route payloads, the
//  remembered owner-assignment setting) and empties the shared URL cache; everything else on the phone is left
//  alone. `keysToClear(existing:)` is the whole decision.
//

import XCTest
@testable import Kinematic

@MainActor
final class SessionCleanupTests: XCTestCase {

    /// Runs `body` with a UserDefaults of its own (never `.standard`), removed afterwards.
    private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "SessionCleanupTests." + UUID().uuidString
        guard let d = UserDefaults(suiteName: name) else { return XCTFail("could not make a test UserDefaults") }
        defer { d.removePersistentDomain(forName: name) }
        try body(d)
    }

    // MARK: - which keys

    func testTheListNamesTheKeysThatBelongToThePersonWhoSignedOut() {
        XCTAssertEqual(SessionCleanup.userDefaultsKeys, [
            "kinematic_selected_client",
            "crm.location.state",
            "crm.location.city",
            "cached_mobile_home_payload",
            "cached_route_plan_payload",
        ])
        XCTAssertEqual(SessionCleanup.userDefaultsKeyPrefixes, ["lead_owner_admin_only."])
    }

    func testTheKeysTheOwnersCodeUsesAreTheOnesInTheList() {
        // One source of truth: these constants are what CRMClientScope / CRMLocationStore / the repository read and write.
        XCTAssertEqual(CRMClientScope.storageKey, "kinematic_selected_client")
        XCTAssertEqual(CRMLocationStore.stateKey, "crm.location.state")
        XCTAssertEqual(CRMLocationStore.cityKey, "crm.location.city")
        XCTAssertEqual(SessionCleanup.mobileHomeCacheKey, "cached_mobile_home_payload")
        XCTAssertEqual(SessionCleanup.routePlanCacheKey, "cached_route_plan_payload")
        XCTAssertTrue(OwnerAssignmentCache.key(userId: "u1", clientId: "c1")!.hasPrefix(SessionCleanup.userDefaultsKeyPrefixes[0]))
    }

    func testTheFixedKeysAreAlwaysListedEvenWhenNothingIsSet() {
        XCTAssertEqual(SessionCleanup.keysToClear(existing: []), SessionCleanup.userDefaultsKeys)
    }

    func testEveryOwnerAssignmentEntryIsListedOnceAndTheRestOfThePhoneIsLeftAlone() {
        let existing = [
            "lead_owner_admin_only.u2.c9",
            "app_theme", "current_user", "kinematic_project", "crm.tour.seen",
            "lead_owner_admin_only.u1.c1",
            "kinematic_selected_client",          // also a fixed key: listed once
            "lead_owner_admin_only.u1.c1",        // repeated: listed once
            "not_lead_owner_admin_only.u1.c1",    // the prefix must be at the start
        ]
        let keys = SessionCleanup.keysToClear(existing: existing)
        XCTAssertEqual(keys, SessionCleanup.userDefaultsKeys + ["lead_owner_admin_only.u1.c1", "lead_owner_admin_only.u2.c9"])
        XCTAssertEqual(Set(keys).count, keys.count)
        for kept in ["app_theme", "current_user", "kinematic_project", "crm.tour.seen", "not_lead_owner_admin_only.u1.c1"] {
            XCTAssertFalse(keys.contains(kept), kept)
        }
    }

    // MARK: - applying it

    func testClearingRemovesThePersonsKeysAndNothingElse() {
        withSuite { d in
            for key in SessionCleanup.userDefaultsKeys { d.set("theirs", forKey: key) }
            OwnerAssignmentCache.write(true, key: OwnerAssignmentCache.key(userId: "u1", clientId: "c1"), in: d)
            OwnerAssignmentCache.write(false, key: OwnerAssignmentCache.key(userId: "u2", clientId: "c2"), in: d)
            d.set("dark", forKey: "app_theme")
            d.set(true, forKey: "crm.tour.seen")

            SessionCleanup.clearPersistedUserState(in: d)

            for key in SessionCleanup.userDefaultsKeys { XCTAssertNil(d.object(forKey: key), key) }
            XCTAssertNil(OwnerAssignmentCache.read(key: OwnerAssignmentCache.key(userId: "u1", clientId: "c1"), in: d))
            XCTAssertNil(OwnerAssignmentCache.read(key: OwnerAssignmentCache.key(userId: "u2", clientId: "c2"), in: d))
            XCTAssertEqual(d.string(forKey: "app_theme"), "dark")
            XCTAssertEqual(d.bool(forKey: "crm.tour.seen"), true)
        }
    }

    func testClearingWhenNothingIsSetIsHarmless() {
        withSuite { d in
            SessionCleanup.clearPersistedUserState(in: d)
            SessionCleanup.clearPersistedUserState(in: d)
            for key in SessionCleanup.userDefaultsKeys { XCTAssertNil(d.object(forKey: key), key) }
        }
    }

    func testTheRealSelectedClientAndLocationPicksAreGoneAfterTheWipe() {
        // The real accessors read the real keys: after the wipe no X-Client-Id / ?city= is sent for the next person.
        let std = UserDefaults.standard
        let saved = SessionCleanup.userDefaultsKeys.map { (key: $0, value: std.object(forKey: $0)) }
        defer { for s in saved { if let v = s.value { std.set(v, forKey: s.key) } else { std.removeObject(forKey: s.key) } } }

        CRMClientScope.setSelectedClientId("12345678-1234-1234-1234-1234567890ab")
        std.set("Maharashtra", forKey: CRMLocationStore.stateKey)
        std.set("Pune", forKey: CRMLocationStore.cityKey)
        XCTAssertNotNil(CRMClientScope.selectedClientId())

        SessionCleanup.clearPersistedUserState()

        XCTAssertNil(CRMClientScope.selectedClientId())
        XCTAssertNil(std.string(forKey: CRMLocationStore.stateKey))
        XCTAssertNil(std.string(forKey: CRMLocationStore.cityKey))
    }

    func testTheSharedUrlCacheIsEmptied() throws {
        let cache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0, directory: nil)
        let url = try XCTUnwrap(URL(string: "https://api.kinematicapp.com/api/v1/crm/settings"))
        let request = URLRequest(url: url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                     headerFields: ["Content-Type": "application/json"]))
        cache.storeCachedResponse(CachedURLResponse(response: response, data: Data("{}".utf8)), for: request)
        XCTAssertNotNil(cache.cachedResponse(for: request))

        SessionCleanup.clearTransientCaches(urlCache: cache)

        XCTAssertNil(cache.cachedResponse(for: request))
    }

    // MARK: - the requests never read the cache

    func testTheExpensePolicyRequestNeverReadsTheLocalCache() throws {
        // A stored or revalidated entry is keyed by URL alone, so it could answer for the wrong person.
        let req = try ExpensesAPI.shared.makeRequest("/expenses/policy", method: "GET")
        XCTAssertEqual(req.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(req.url?.path, "/api/v1/expenses/policy")
        XCTAssertEqual(req.httpMethod, "GET")
    }
}
