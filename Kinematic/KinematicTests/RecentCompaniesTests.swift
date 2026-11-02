//
//  RecentCompaniesTests.swift
//  KinematicTests
//
//  The rules behind the Customer / Company picker's "Recent" list: most-recent-first, one row per company, capped,
//  read back safely, kept per user. Mirrors the Android RecentCompaniesTest.
//

import XCTest
@testable import Kinematic

final class RecentCompaniesTests: XCTestCase {

    private func co(_ n: Int) -> RecentCompany { RecentCompany(id: "id-\(n)", name: "Company \(n)") }

    func testANewPickGoesToTheFront() {
        let list = RecentCompanies.pushed([co(1), co(2)], co(3))
        XCTAssertEqual(list.map(\.id), ["id-3", "id-1", "id-2"])
    }

    func testPickingAListedCompanyMovesItUpNotTwice() {
        let list = RecentCompanies.pushed([co(1), co(2), co(3)], co(3))
        XCTAssertEqual(list.map(\.id), ["id-3", "id-1", "id-2"])
    }

    func testTheListIsCappedAtTheNewestEight() {
        var list: [RecentCompany] = []
        for n in 1...12 { list = RecentCompanies.pushed(list, co(n)) }
        XCTAssertEqual(list.count, RecentCompanies.max)
        XCTAssertEqual(list.first?.id, "id-12")
        XCTAssertEqual(list.last?.id, "id-5")
    }

    func testACompanyWithoutAnIdOrNameIsNeverRecorded() {
        let start = [co(1)]
        XCTAssertEqual(RecentCompanies.pushed(start, RecentCompany(id: "", name: "No id")), start)
        XCTAssertEqual(RecentCompanies.pushed(start, RecentCompany(id: "id-9", name: "  ")), start)
    }

    func testWhatIsStoredReadsBackTheSame() {
        let list = [co(2), co(1)]
        XCTAssertEqual(RecentCompanies.decode(RecentCompanies.encode(list)), list)
    }

    func testNothingStoredOrJunkReadsAsEmpty() {
        XCTAssertEqual(RecentCompanies.decode(nil), [])
        XCTAssertEqual(RecentCompanies.decode(Data()), [])
        XCTAssertEqual(RecentCompanies.decode(Data("not json".utf8)), [])
        XCTAssertEqual(RecentCompanies.decode(Data("null".utf8)), [])
    }

    func testUnusableStoredRowsAreDropped() {
        let raw = #"[{"id":"id-1","name":"Acme"},{"id":"","name":"No id"},{"id":"id-3"},null]"#
        XCTAssertEqual(RecentCompanies.decode(Data(raw.utf8)).map(\.id), ["id-1"])
    }

    func testTheStoreKeepsEachUsersListSeparate() {
        let defaults = UserDefaults(suiteName: "RecentCompaniesTests-\(UUID().uuidString)")!
        let store = RecentCompaniesStore(defaults: defaults)
        store.record(userId: "rep-a", co(1))
        store.record(userId: "rep-b", co(2))
        XCTAssertEqual(store.load(userId: "rep-a").map(\.id), ["id-1"])
        XCTAssertEqual(store.load(userId: "rep-b").map(\.id), ["id-2"])
        XCTAssertEqual(store.load(userId: ""), [])
        XCTAssertEqual(store.record(userId: "", co(3)), [])
    }
}
