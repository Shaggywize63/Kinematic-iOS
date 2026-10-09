//
//  RupeeTargetsTests.swift
//  KinematicTests
//
//  Sales / Collection rupee targets: what the "My targets" card shows (progress bar held at 100% with the true
//  percentage beside it, "No target set"), how the amount field is read and checked, ₹ in Indian grouping, the
//  24-hour delete window, when the card appears at all (only for a client that configured types), and decoding
//  the server's JSON. A client without rupee targets must see nothing new — most tests pin that.
//

import XCTest
@testable import Kinematic

final class RupeeTargetsTests: XCTestCase {

    private let sales = RupeeTargetType(key: "sales", label: "Sales", metric: "sales_amount", period: "monthly", unit: "INR")
    private let collection = RupeeTargetType(key: "collection", label: "Collection", metric: "collection_amount", period: "monthly", unit: "INR")

    private func row(_ key: String = "sales", target: Double?, achieved: Double, label: String = "Sales") -> RupeeTargetProgressRow {
        RupeeTargetProgressRow(key: key, label: label, target: target, achieved: achieved)
    }

    // MARK: - progress

    func testTheBarStopsAtFullButThePercentageIsTheTrueOne() {
        XCTAssertEqual(RupeeTargets.barFraction(achieved: 125_000, target: 500_000), 0.25, accuracy: 0.0001)
        XCTAssertEqual(RupeeTargets.percent(achieved: 125_000, target: 500_000), 25)
        // Beat the target: the bar is full, the number says how far over.
        XCTAssertEqual(RupeeTargets.barFraction(achieved: 750_000, target: 500_000), 1)
        XCTAssertEqual(RupeeTargets.percent(achieved: 750_000, target: 500_000), 150)
        XCTAssertEqual(RupeeTargets.percent(achieved: 500_000, target: 500_000), 100)
        XCTAssertTrue(RupeeTargets.isComplete(achieved: 500_000, target: 500_000))
    }

    func testJustShortOfTheTargetNeverReadsAsDone() {
        XCTAssertEqual(RupeeTargets.percent(achieved: 499_999, target: 500_000), 99)
        XCTAssertFalse(RupeeTargets.isComplete(achieved: 499_999, target: 500_000))
        XCTAssertEqual(RupeeTargets.percent(achieved: 0, target: 500_000), 0)
    }

    func testNoTargetMeansNoBarAndNoPercentage() {
        for t in [nil, 0, -5] as [Double?] {
            XCTAssertFalse(RupeeTargets.hasTarget(t))
            XCTAssertNil(RupeeTargets.percent(achieved: 1_000, target: t))
            XCTAssertEqual(RupeeTargets.barFraction(achieved: 1_000, target: t), 0)
            XCTAssertFalse(RupeeTargets.isComplete(achieved: 1_000, target: t))
        }
        XCTAssertEqual(RupeeTargets.barFraction(achieved: -10, target: 100), 0)
        XCTAssertNil(RupeeTargets.percent(achieved: .nan, target: 100))
        XCTAssertNotNil(RupeeTargets.percent(achieved: 1e300, target: 0.0001))   // no crash on absurd input
    }

    func testTheCardRowsNameTheConfiguredTypesAsTheServerDoes() {
        let progress = RupeeTargetProgress(periodStart: "2026-10-01", periodEnd: "2026-10-31", types: [
            row("collection", target: nil, achieved: 12_000, label: "Dealer collection"),
            row("sales", target: 500_000, achieved: 125_000, label: "Sales (₹)"),
        ])
        let rows = RupeeTargets.cardRows(types: [sales, collection], progress: progress)
        // The server's order of TYPES, the server's label from the progress answer.
        XCTAssertEqual(rows.map { $0.key }, ["sales", "collection"])
        XCTAssertEqual(rows.map { $0.label }, ["Sales (₹)", "Dealer collection"])
        XCTAssertEqual(rows[0].trailingText, "25%")
        XCTAssertEqual(rows[0].detailText, "₹1,25,000 of ₹5,00,000")
        XCTAssertTrue(rows[0].showsBar)
        XCTAssertEqual(rows[1].trailingText, "No target set")
        XCTAssertEqual(rows[1].detailText, "₹12,000 so far")
        XCTAssertFalse(rows[1].showsBar)
    }

    func testATypeTheProgressAnswerOmitsShowsZeroAndNoTarget() {
        let progress = RupeeTargetProgress(periodStart: "2026-10-01", periodEnd: "2026-10-31", types: [row("sales", target: 100, achieved: 10)])
        let rows = RupeeTargets.cardRows(types: [sales, collection], progress: progress)
        XCTAssertEqual(rows[1].achieved, 0)
        XCTAssertEqual(rows[1].trailingText, "No target set")
    }

    func testWhenTheProgressCannotBeFetchedTheLabelsShowButNotMadeUpNumbers() {
        let rows = RupeeTargets.cardRows(types: [sales, collection], progress: nil)
        XCTAssertEqual(rows.map { $0.label }, ["Sales", "Collection"])
        for r in rows {
            XCTAssertFalse(r.hasProgress)
            XCTAssertEqual(r.trailingText, "—")
            XCTAssertEqual(r.detailText, "Progress unavailable right now")
            XCTAssertFalse(r.showsBar)
            XCTAssertNil(r.percent)
        }
    }

    func testTheCardAppearsOnlyForAClientWithTypesAndNotWhereHidden() {
        XCTAssertTrue(RupeeTargets.cardVisible(types: [sales], homeVisible: true))
        XCTAssertFalse(RupeeTargets.cardVisible(types: [], homeVisible: true))          // no rupee targets: nothing new
        XCTAssertFalse(RupeeTargets.cardVisible(types: [sales], homeVisible: false))    // home.my_targets == false
        XCTAssertFalse(RupeeTargets.cardVisible(types: [], homeVisible: false))
    }

    func testTheMonthIsNamedFromThePeriodStart() {
        XCTAssertEqual(RupeeTargets.monthTitle(periodStart: "2026-10-01"), "October 2026")
        XCTAssertEqual(RupeeTargets.monthTitle(periodStart: "2027-02-01T00:00:00Z"), "February 2027")
        XCTAssertNil(RupeeTargets.monthTitle(periodStart: nil))
        XCTAssertNil(RupeeTargets.monthTitle(periodStart: "soon"))
    }

    func testTheButtonsAndConfirmationsReadInPlainWords() {
        XCTAssertEqual(RupeeTargets.logButtonTitle(key: "sales", label: "Sales"), "Log sale")
        XCTAssertEqual(RupeeTargets.logButtonTitle(key: "collection", label: "Collection"), "Log collection")
        XCTAssertEqual(RupeeTargets.logButtonTitle(key: "visits", label: "Visits"), "Log visits")
        XCTAssertEqual(RupeeTargets.confirmation(forKey: "sales", label: "Sales"), "Sale logged")
        XCTAssertEqual(RupeeTargets.confirmation(forKey: "collection", label: "Collection"), "Collection logged")
        XCTAssertEqual(RupeeTargets.confirmation(forKey: "visits", label: "Visits"), "Visits logged")
    }

    // MARK: - rupees

    func testRupeesAreInIndianGroupingWithPaiseOnlyWhenThereAreSome() {
        XCTAssertEqual(RupeeTargets.inr(125_000), "₹1,25,000")
        XCTAssertEqual(RupeeTargets.inr(0), "₹0")
        XCTAssertEqual(RupeeTargets.inr(999), "₹999")
        XCTAssertEqual(RupeeTargets.inr(10_000_000), "₹1,00,00,000")
        XCTAssertEqual(RupeeTargets.inr(1_000_000_000), "₹1,00,00,00,000")
        XCTAssertEqual(RupeeTargets.inr(1250.5), "₹1,250.50")
        XCTAssertEqual(RupeeTargets.inr(99.99), "₹99.99")
        XCTAssertEqual(RupeeTargets.inr(-4_500), "-₹4,500")
        XCTAssertEqual(RupeeTargets.inr(.nan), "₹0")
        XCTAssertEqual(RupeeTargets.inr(.infinity), "₹0")
    }

    // MARK: - the amount field

    private func ok(_ text: String) -> Double? {
        if case .ok(let v) = RupeeTargets.parseAmount(text) { return v }
        return nil
    }

    func testAnAmountIsAPositiveNumberOfAtMostTwoDecimals() {
        XCTAssertEqual(ok("125000"), 125_000)
        XCTAssertEqual(ok("  99.5 "), 99.5)
        XCTAssertEqual(ok("0.01"), 0.01)
        XCTAssertEqual(ok("1250.75"), 1250.75)
        XCTAssertEqual(ok("5."), 5)
        XCTAssertEqual(ok(".5"), 0.5)
        XCTAssertEqual(ok("1000000000"), 1_000_000_000)    // the ceiling itself is allowed
    }

    func testThingsPeoplePasteAreUnderstood() {
        XCTAssertEqual(ok("₹1,25,000"), 125_000)
        XCTAssertEqual(ok("1,250"), 1250)               // thousands comma
        XCTAssertEqual(ok("1,250.50"), 1250.5)
        XCTAssertEqual(ok("12,50"), 12.5)               // a decimal comma
        XCTAssertEqual(ok("12 500"), 12_500)
    }

    func testBadAmountsSayWhatIsWrong() {
        XCTAssertEqual(RupeeTargets.parseAmount(""), .empty)
        XCTAssertEqual(RupeeTargets.parseAmount("   "), .empty)
        XCTAssertEqual(RupeeTargets.parseAmount("abc"), .notANumber)
        XCTAssertEqual(RupeeTargets.parseAmount("."), .notANumber)
        XCTAssertEqual(RupeeTargets.parseAmount("1.2.3"), .notANumber)
        XCTAssertEqual(RupeeTargets.parseAmount("-50"), .notANumber)
        XCTAssertEqual(RupeeTargets.parseAmount("1e5"), .notANumber)
        XCTAssertEqual(RupeeTargets.parseAmount("0"), .notPositive)
        XCTAssertEqual(RupeeTargets.parseAmount("0.00"), .notPositive)
        XCTAssertEqual(RupeeTargets.parseAmount("1.234"), .tooManyDecimals)
        XCTAssertEqual(RupeeTargets.parseAmount("1000000000.01"), .tooLarge)
        XCTAssertEqual(RupeeTargets.parseAmount("99999999999"), .tooLarge)
        XCTAssertEqual(RupeeTargets.message(for: .empty), "Enter the amount.")
        XCTAssertEqual(RupeeTargets.message(for: .notANumber), "Enter a valid amount.")
        XCTAssertEqual(RupeeTargets.message(for: .notPositive), "The amount must be more than zero.")
        XCTAssertEqual(RupeeTargets.message(for: .tooManyDecimals), "Use at most 2 decimal places.")
        XCTAssertEqual(RupeeTargets.message(for: .tooLarge), "The amount can't be more than ₹1,00,00,00,000.")
        XCTAssertNil(RupeeTargets.message(for: .ok(5)))
    }

    func testTheNoteIsTrimmedAndCutAt500() {
        XCTAssertNil(RupeeTargets.cleanNote("   \n "))
        XCTAssertEqual(RupeeTargets.cleanNote("  Sharma Agro, part payment "), "Sharma Agro, part payment")
        XCTAssertEqual(RupeeTargets.cleanNote(String(repeating: "x", count: 900))?.count, 500)
    }

    func testARetryOfTheSameEntryHasTheSameKeyAndAnEditedOneDoesNot() {
        let a = RupeeTargets.idempotencyKey(attempt: "S1", kind: "sales", amount: 1250.5, leadId: "L1", note: "x")
        XCTAssertEqual(a, RupeeTargets.idempotencyKey(attempt: "S1", kind: "sales", amount: 1250.5, leadId: "L1", note: "x"))
        XCTAssertNotEqual(a, RupeeTargets.idempotencyKey(attempt: "S1", kind: "sales", amount: 1250.51, leadId: "L1", note: "x"))
        XCTAssertNotEqual(a, RupeeTargets.idempotencyKey(attempt: "S1", kind: "collection", amount: 1250.5, leadId: "L1", note: "x"))
        XCTAssertNotEqual(a, RupeeTargets.idempotencyKey(attempt: "S1", kind: "sales", amount: 1250.5, leadId: nil, note: "x"))
        XCTAssertNotEqual(a, RupeeTargets.idempotencyKey(attempt: "S1", kind: "sales", amount: 1250.5, leadId: "L1", note: nil))
        XCTAssertNotEqual(a, RupeeTargets.idempotencyKey(attempt: "S2", kind: "sales", amount: 1250.5, leadId: "L1", note: "x"))
        XCTAssertTrue(a.hasPrefix("tgt-S1-"))
    }

    // MARK: - failures

    func testALostConnectionSaysSoAndOtherFailuresSayWhatTheServerSaid() {
        let offline = "No connection — check your network and try again."
        XCTAssertEqual(RupeeTargets.failureMessage(urlErrorCode: .notConnectedToInternet, serverMessage: nil, fallback: "x"), offline)
        XCTAssertEqual(RupeeTargets.failureMessage(urlErrorCode: .timedOut, serverMessage: nil, fallback: "x"), offline)
        XCTAssertEqual(RupeeTargets.failureMessage(urlErrorCode: .networkConnectionLost, serverMessage: "ignored", fallback: "x"), offline)
        XCTAssertEqual(RupeeTargets.failureMessage(urlErrorCode: nil, serverMessage: "Sales targets are not switched on.", fallback: "x"),
                       "Sales targets are not switched on.")
        XCTAssertEqual(RupeeTargets.failureMessage(urlErrorCode: nil, serverMessage: "  ", fallback: "Try again"), "Try again")
        XCTAssertEqual(RupeeTargets.failureMessage(urlErrorCode: .cancelled, serverMessage: nil, fallback: "Try again"), "Try again")
        XCTAssertEqual(RupeeTargets.failureMessage(for: URLError(.notConnectedToInternet), fallback: "x"), offline)
        XCTAssertEqual(RupeeTargets.failureMessage(for: CRMServiceError.server("TARGET_ENTRIES_NOT_ENABLED"), fallback: "x"), "TARGET_ENTRIES_NOT_ENABLED")
    }

    // MARK: - the 24-hour delete window

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func stamp(hoursAgo: Double) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: now.addingTimeInterval(-hoursAgo * 3600))
    }

    func testAnEntryCanBeDeletedForTwentyFourHours() {
        XCTAssertTrue(RupeeTargets.canDelete(createdAt: stamp(hoursAgo: 0.1), entryUserId: "u1", currentUserId: "u1", now: now))
        XCTAssertTrue(RupeeTargets.canDelete(createdAt: stamp(hoursAgo: 23.9), entryUserId: "u1", currentUserId: "u1", now: now))
        XCTAssertFalse(RupeeTargets.canDelete(createdAt: stamp(hoursAgo: 24), entryUserId: "u1", currentUserId: "u1", now: now))
        XCTAssertFalse(RupeeTargets.canDelete(createdAt: stamp(hoursAgo: 25), entryUserId: "u1", currentUserId: "u1", now: now))
        XCTAssertFalse(RupeeTargets.canDelete(createdAt: stamp(hoursAgo: 24 * 9), entryUserId: "u1", currentUserId: "u1", now: now))
        XCTAssertEqual(RupeeTargets.deleteWindow, 24 * 3600)
    }

    func testOnlyTheOwnerIsOfferedTheDelete() {
        XCTAssertFalse(RupeeTargets.canDelete(createdAt: stamp(hoursAgo: 1), entryUserId: "u2", currentUserId: "u1", now: now))
        // The list is the caller's own, so an entry that names no owner is theirs.
        XCTAssertTrue(RupeeTargets.canDelete(createdAt: stamp(hoursAgo: 1), entryUserId: nil, currentUserId: "u1", now: now))
        XCTAssertTrue(RupeeTargets.canDelete(createdAt: stamp(hoursAgo: 1), entryUserId: "u1", currentUserId: nil, now: now))
    }

    func testAnEntryWhoseTimeCannotBeReadIsNotOfferedTheDelete() {
        XCTAssertFalse(RupeeTargets.canDelete(createdAt: nil, entryUserId: "u1", currentUserId: "u1", now: now))
        XCTAssertFalse(RupeeTargets.canDelete(createdAt: "yesterday", entryUserId: "u1", currentUserId: "u1", now: now))
        XCTAssertFalse(RupeeTargets.canDelete(createdAt: "2026-10-09", entryUserId: "u1", currentUserId: "u1", now: now))   // a bare date is no moment
    }

    func testAPhoneClockSlightlyBehindTheServerStillOffersTheDelete() {
        let ahead = ISO8601DateFormatter().string(from: now.addingTimeInterval(120))
        XCTAssertTrue(RupeeTargets.canDelete(createdAt: ahead, entryUserId: "u1", currentUserId: "u1", now: now))
    }

    func testTimestampsAreReadTheWayTheDatabaseSendsThem() {
        let utc = Date(timeIntervalSince1970: 1_791_533_730)      // 2026-10-09 08:15:30 UTC
        XCTAssertEqual(RupeeTargets.parseTimestamp("2026-10-09T08:15:30Z"), utc)
        XCTAssertEqual(RupeeTargets.parseTimestamp("2026-10-09T08:15:30+00:00"), utc)
        XCTAssertEqual(RupeeTargets.parseTimestamp("2026-10-09T08:15:30+00"), utc)                 // a bare offset
        XCTAssertEqual(RupeeTargets.parseTimestamp("2026-10-09 08:15:30+00"), utc)                 // a space for the T
        XCTAssertEqual(RupeeTargets.parseTimestamp("2026-10-09T08:15:30"), utc)                    // no offset: UTC
        XCTAssertEqual(RupeeTargets.parseTimestamp("2026-10-09T13:45:30+05:30"), utc)
        // Fractions of a second, down to the microseconds Postgres sends.
        XCTAssertEqual(try XCTUnwrap(RupeeTargets.parseTimestamp("2026-10-09T08:15:30.123Z")).timeIntervalSince1970, 1_791_533_730.123, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(RupeeTargets.parseTimestamp("2026-10-09T08:15:30.123456+00:00")).timeIntervalSince1970, 1_791_533_730.123, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(RupeeTargets.parseTimestamp("2026-10-09T08:15:30.5Z")).timeIntervalSince1970, 1_791_533_730.5, accuracy: 0.001)
        XCTAssertNil(RupeeTargets.parseTimestamp("2026-10-09"))
        XCTAssertNil(RupeeTargets.parseTimestamp("not a time at all"))
        XCTAssertNil(RupeeTargets.parseTimestamp(nil))
        XCTAssertNil(RupeeTargets.parseTimestamp(""))
    }

    // MARK: - decoding what the server sends

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testTheConfiguredTypesDecode() throws {
        let p = try decode(RupeeTargetTypesPayload.self, """
        {"types":[{"key":"sales","label":"Sales value","metric":"sales_amount","period":"monthly","unit":"INR"},
                  {"key":"collection","label":"Collection","metric":"collection_amount","period":"monthly","unit":"INR"}]}
        """)
        XCTAssertEqual(p.types.map { $0.key }, ["sales", "collection"])
        XCTAssertEqual(p.types[0].label, "Sales value")
        XCTAssertEqual(p.types[0].unit, "INR")
    }

    func testAClientWithoutRupeeTargetsDecodesToNoTypes() throws {
        XCTAssertTrue(try decode(RupeeTargetTypesPayload.self, #"{"types":[]}"#).types.isEmpty)
        XCTAssertTrue(try decode(RupeeTargetTypesPayload.self, "{}").types.isEmpty)
        XCTAssertTrue(try decode(RupeeTargetTypesPayload.self, #"{"types":null}"#).types.isEmpty)
        XCTAssertTrue(try decode(RupeeTargetTypesPayload.self, #"{"types":"nonsense"}"#).types.isEmpty)
    }

    func testOneUnreadableTypeIsSkippedNotTheWholeList() throws {
        let p = try decode(RupeeTargetTypesPayload.self, #"{"types":[{"label":"no key"},{"key":"sales"},42]}"#)
        XCTAssertEqual(p.types.map { $0.key }, ["sales"])
        XCTAssertEqual(p.types[0].label, "Sales")           // a missing label falls back to the usual name
    }

    func testTheMonthsProgressDecodesNumbersAndNumericStrings() throws {
        let p = try decode(RupeeTargetProgress.self, """
        {"period_start":"2026-10-01","period_end":"2026-10-31","types":[
          {"key":"sales","label":"Sales","target":500000,"achieved":125000.5,"pct":25.0,"source":"entries"},
          {"key":"collection","label":"Collection","target":null,"achieved":"12000.00","pct":null,"source":null}]}
        """)
        XCTAssertEqual(p.periodStart, "2026-10-01")
        XCTAssertEqual(p.periodEnd, "2026-10-31")
        XCTAssertEqual(p.types[0].target, 500_000)
        XCTAssertEqual(p.types[0].achieved, 125_000.5)
        XCTAssertEqual(p.types[0].source, "entries")
        XCTAssertNil(p.types[1].target)                  // no target set
        XCTAssertEqual(p.types[1].achieved, 12_000)      // a numeric string still counts
        XCTAssertNil(p.types[1].pct)
    }

    func testEntriesDecodeIncludingMicrosecondTimestamps() throws {
        let rows = try decode([RupeeTargetEntry].self, """
        [{"id":"e1","kind":"sales","amount":125000,"entry_date":"2026-10-05","lead_id":"L1","lead_name":"Sharma Agro",
          "note":"Part payment","user_id":"u1","user_name":"Asha","created_at":"2026-10-05T09:30:00.123456+00:00"},
         {"id":"e2","kind":"collection","amount":"4500.50","entry_date":"2026-10-04","lead_id":null,"lead_name":null,"note":null,
          "user_id":"u1","user_name":"Asha","created_at":"2026-10-04T09:30:00Z"}]
        """)
        XCTAssertEqual(rows.map { $0.id }, ["e1", "e2"])
        XCTAssertEqual(rows[0].amount, 125_000)
        XCTAssertEqual(rows[0].leadName, "Sharma Agro")
        XCTAssertEqual(rows[1].amount, 4_500.5)
        XCTAssertNil(rows[1].leadId)
        XCTAssertNotNil(RupeeTargets.parseTimestamp(rows[0].createdAt))
        XCTAssertEqual(ExpenseLogic.shortDate(rows[0].entryDate), "5 Oct 2026")
    }

    // MARK: - routes

    func testTheRupeeTargetEndpointsAreNotCityScoped() {
        for p in ["/api/v1/crm/targets/types", "/api/v1/crm/targets/progress", "/api/v1/crm/targets/entries", "/api/v1/crm/targets/entries/abc"] {
            XCTAssertTrue(RupeeTargets.isRupeeTargetsPath(p), p)
            XCTAssertFalse(CRMService.isCityAwareAnalyticsPath(p), p)
        }
        // The lead-count targets keep narrowing by city, exactly as before.
        for p in ["/api/v1/crm/targets/me", "/api/v1/crm/targets", "/api/v1/crm/targets/leaderboard", "/api/v1/crm/targets/levels"] {
            XCTAssertFalse(RupeeTargets.isRupeeTargetsPath(p), p)
            XCTAssertTrue(CRMService.isCityAwareAnalyticsPath(p), p)
        }
        XCTAssertTrue(CRMService.isCityAwareAnalyticsPath("/api/v1/crm/analytics/dashboard-summary"))
        XCTAssertFalse(CRMService.isCityAwareAnalyticsPath("/api/v1/crm/leads"))
    }
}
