//
//  CRMClientScopeTests.swift
//  KinematicTests
//
//  The active client scope must round-trip a valid UUID through
//  UserDefaults.standard and reject non-UUID legacy values.
//
//  CRMClientScope reads/writes `UserDefaults.standard` under the
//  "kinematic_selected_client" key, so each test saves and restores that key
//  to avoid leaking state into the host app's defaults.
//

import XCTest
@testable import Kinematic

@MainActor
final class CRMClientScopeTests: XCTestCase {

    private let key = "kinematic_selected_client"

    /// Run `body` with a clean value for the scope key, restoring whatever was
    /// there before (belt-and-braces isolation for `UserDefaults.standard`).
    private func withCleanDefaults(_ body: () -> Void) {
        let saved = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        body()
    }

    func testValidLowercaseUUIDRoundTrips() {
        withCleanDefaults {
            let uuid = "12345678-1234-1234-1234-1234567890ab"
            CRMClientScope.setSelectedClientId(uuid)
            XCTAssertEqual(CRMClientScope.selectedClientId(), uuid)
        }
    }

    func testUppercaseUUIDAccepted() {
        withCleanDefaults {
            let uuid = UUID().uuidString // uppercased canonical form
            CRMClientScope.setSelectedClientId(uuid)
            XCTAssertEqual(CRMClientScope.selectedClientId(), uuid)
        }
    }

    func testNonUUIDLegacyStringRejected() {
        withCleanDefaults {
            CRMClientScope.setSelectedClientId("Kinematic")
            XCTAssertNil(CRMClientScope.selectedClientId())
        }
    }

    func testMalformedUUIDRejected() {
        withCleanDefaults {
            CRMClientScope.setSelectedClientId("not-a-uuid-1234")
            XCTAssertNil(CRMClientScope.selectedClientId())
        }
    }

    func testEmptyStringClearsSelection() {
        withCleanDefaults {
            CRMClientScope.setSelectedClientId("11111111-1111-1111-1111-111111111111")
            CRMClientScope.setSelectedClientId("")
            XCTAssertNil(CRMClientScope.selectedClientId())
        }
    }

    func testNilClearsSelection() {
        withCleanDefaults {
            CRMClientScope.setSelectedClientId("11111111-1111-1111-1111-111111111111")
            CRMClientScope.setSelectedClientId(nil)
            XCTAssertNil(CRMClientScope.selectedClientId())
        }
    }

    func testMissingKeyReturnsNil() {
        withCleanDefaults {
            XCTAssertNil(CRMClientScope.selectedClientId())
        }
    }
}
