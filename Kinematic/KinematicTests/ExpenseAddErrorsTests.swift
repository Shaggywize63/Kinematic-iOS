//
//  ExpenseAddErrorsTests.swift
//  KinematicTests
//
//  "API error" when adding an expense. The pieces that decide what a person sees and what is sent:
//    - the server's own sentence is shown, but production's stock "Internal server error" (and a proxy's HTML page)
//      is replaced by a plain line for the status;
//    - a request that never got an answer (offline, timed out) and a 2xx the app cannot read each say what to do;
//    - amounts are read the way people type them ("1,250.50", "99,50", "₹ 300") instead of "needs an amount";
//    - a scanned receipt date is used only when it is a real day;
//    - the claim body never carries a key the server does not need (no nulls, no odometer fields on a plain line).
//

import XCTest
@testable import Kinematic

final class ExpenseAddErrorsTests: XCTestCase {

    // MARK: - what the person is told

    func testTheServersSentenceIsShownAsIs() {
        let sentence = "Expense 2: date must be a real day written as YYYY-MM-DD"
        XCTAssertEqual(ExpenseErrors.message(serverMessage: sentence, status: 400), sentence)
        XCTAssertEqual(ExpensesAPIError.http(400, sentence).errorDescription, sentence)
    }

    func testProductionsStockTextBecomesAPlainLine() {
        XCTAssertEqual(ExpenseErrors.message(serverMessage: "Internal server error", status: 500), "The server had a problem. Try again in a moment.")
        XCTAssertEqual(ExpenseErrors.message(serverMessage: "  internal SERVER error ", status: 500), "The server had a problem. Try again in a moment.")
        XCTAssertEqual(ExpenseErrors.message(serverMessage: "<html><body>502 Bad Gateway</body></html>", status: 502), "The server had a problem. Try again in a moment.")
        XCTAssertEqual(ExpenseErrors.message(serverMessage: "Bad Gateway", status: 502), "The server had a problem. Try again in a moment.")
        XCTAssertEqual(ExpensesAPIError.http(500, "Internal server error").errorDescription, "The server had a problem. Try again in a moment.")
    }

    func testEveryStatusWithoutAMessageHasAPlainLine() {
        XCTAssertTrue(ExpenseErrors.message(serverMessage: nil, status: 400).contains("aren't valid"))
        XCTAssertTrue(ExpenseErrors.message(serverMessage: nil, status: 409).contains("conflicts"))
        XCTAssertTrue(ExpenseErrors.message(serverMessage: nil, status: 415).contains("HEIC"))
        XCTAssertTrue(ExpenseErrors.message(serverMessage: nil, status: 429).contains("Too many"))
        XCTAssertTrue(ExpenseErrors.message(serverMessage: nil, status: 504).contains("too long"))
        XCTAssertEqual(ExpenseErrors.message(serverMessage: nil, status: 418), "Request failed (418)")
    }

    func testARequestThatGotNoAnswerSaysWhatToDo() {
        XCTAssertTrue(ExpenseErrors.transportMessage(.notConnectedToInternet).contains("No internet"))
        XCTAssertTrue(ExpenseErrors.transportMessage(.networkConnectionLost).contains("No internet"))
        let timeout = ExpenseErrors.transportMessage(.timedOut)
        XCTAssertTrue(timeout.contains("timed out"))
        XCTAssertTrue(timeout.contains("so you don't add it twice"))
        XCTAssertTrue(ExpenseErrors.transportMessage(.cannotFindHost).contains("reach the server"))
        XCTAssertEqual(ExpensesAPIError.network("No internet connection.").errorDescription, "No internet connection.")
    }

    func testAnUnreadableSuccessWarnsThatItMayHaveBeenSaved() {
        let text = ExpensesAPIError.unreadable.errorDescription ?? ""
        XCTAssertTrue(text.contains("may have been saved"))
        XCTAssertTrue(text.contains("claims list"))
    }

    // MARK: - numbers the way people type them

    func testAmountsAreReadTheWayPeopleWriteThem() {
        let cases: [(String, Double)] = [
            ("120", 120), ("99.5", 99.5), ("1,250.50", 1250.5), ("99,50", 99.5), ("1,250", 1250), ("12,34,567", 1234567),
            ("1.250,75", 1250.75), ("₹ 300", 300), ("Rs. 45.5", 45.5), ("INR 1,000", 1000), ("  72 ", 72), ("٣٠٠", 300), ("1.250.000", 1250000),
        ]
        for (raw, want) in cases { XCTAssertEqual(ExpenseNumber.parse(raw), want, "\(raw)") }
    }

    func testNonNumbersAreNotAmounts() {
        for raw in ["", "  ", "abc", "1e5x", "--5", "12 apples", "NaN", "Infinity"] { XCTAssertNil(ExpenseNumber.parse(raw), "\(raw)") }
    }

    func testALineWithACommaAmountCanBeSavedAndIsSentAsANumber() {
        var f = ExpenseLineFields(category: "food", itemDate: "2026-10-05")
        f.amount = "1,250.50"
        XCTAssertTrue(f.canSave(byVehicle: false))
        XCTAssertEqual(f.toInput().amount, 1250.5)
        f.amount = "99,50"
        XCTAssertEqual(f.toInput().amount, 99.5)
        f.amount = "₹ 300"
        XCTAssertEqual(f.effectiveAmount(mileageRate: 12), 300)
        f.amount = "0"
        XCTAssertFalse(f.canSave(byVehicle: false))
    }

    func testOdometerReadingsAcceptACommaToo() {
        var f = ExpenseLineFields(category: "mileage", itemDate: "2026-10-05")
        f.vehicleType = "bike"; f.odometerStart = "12,450.5"; f.odometerEnd = "12,500"
        XCTAssertEqual(f.odometerKm, 49.5)
    }

    // MARK: - days

    func testOnlyARealDayIsAccepted() {
        XCTAssertEqual(ExpenseNumber.validDay("2026-10-31"), "2026-10-31")
        XCTAssertEqual(ExpenseNumber.validDay("2028-02-29"), "2028-02-29")
        XCTAssertNil(ExpenseNumber.validDay("2026-02-31"))
        XCTAssertNil(ExpenseNumber.validDay("2027-02-29"))
        XCTAssertNil(ExpenseNumber.validDay("2026-13-01"))
        XCTAssertNil(ExpenseNumber.validDay("2569-10-05"))     // a Buddhist-calendar year
        XCTAssertNil(ExpenseNumber.validDay("05/10/2026"))
        XCTAssertNil(ExpenseNumber.validDay(nil))
    }

    func testAScannedDateIsUsedOnlyWhenItIsARealDay() {
        let blank = ExpenseLineFields(category: "food", itemDate: "2026-10-01")
        let good = ExpenseReceiptFields(merchant: nil, txn_date: "2026-10-05", amount: 10, currency: nil, tax_amount: nil, category: nil)
        XCTAssertEqual(blank.withScan(good, receiptUrl: "u").itemDate, "2026-10-05")
        let bad = ExpenseReceiptFields(merchant: nil, txn_date: "2026-02-30", amount: 10, currency: nil, tax_amount: nil, category: nil)
        XCTAssertEqual(blank.withScan(bad, receiptUrl: "u").itemDate, "2026-10-01")
        let words = ExpenseReceiptFields(merchant: nil, txn_date: "5 Oct 2026", amount: 10, currency: nil, tax_amount: nil, category: nil)
        XCTAssertEqual(blank.withScan(words, receiptUrl: "u").itemDate, "2026-10-01")
    }

    // MARK: - what is sent

    private func json(_ input: ExpenseClaimInput) throws -> [String: Any] {
        let data = try JSONEncoder().encode(input)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testAPlainLineCarriesNoNullsAndNoOdometerFields() throws {
        var f = ExpenseLineFields(category: "food", itemDate: "2026-10-05")
        f.amount = "120"; f.merchant = "Cafe"
        let body = try json(ExpenseClaimInput(title: nil, items: [f.toInput()]))
        XCTAssertNil(body["title"])
        XCTAssertNil(body["clarification"])
        XCTAssertNil(body["form_submission_id"])
        let line = try XCTUnwrap((body["items"] as? [[String: Any]])?.first)
        XCTAssertEqual(line["category"] as? String, "food")
        XCTAssertEqual(line["amount"] as? Double, 120)
        XCTAssertEqual(line["item_date"] as? String, "2026-10-05")
        for key in ["vehicle_type", "odometer_start", "odometer_end", "odometer_start_photo_url", "odometer_end_photo_url",
                    "supplier_gstin", "gst_rate", "account_id", "id", "receipt_url"] {
            XCTAssertNil(line[key], key)
        }
        XCTAssertFalse(line.values.contains { $0 is NSNull })
    }

    func testAConnectedB2BSaveWithNoEntryClearsTheLinkWithAnExplicitNull() throws {
        let cleared = try json(ExpenseClaimInput(title: nil, clarification: "Client visit", clearFormSubmission: true, items: []))
        XCTAssertTrue(cleared["form_submission_id"] is NSNull)
        XCTAssertEqual(cleared["clarification"] as? String, "Client visit")
        let linked = try json(ExpenseClaimInput(title: nil, form_submission_id: "abc", items: []))
        XCTAssertEqual(linked["form_submission_id"] as? String, "abc")
        let untouched = try json(ExpenseClaimInput(title: nil, items: []))
        XCTAssertNil(untouched["form_submission_id"])
    }
}
