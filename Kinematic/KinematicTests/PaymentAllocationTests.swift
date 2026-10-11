//
//  PaymentAllocationTests.swift
//  KinematicTests
//
//  How a collected payment is applied (auto-allocate vs on account), what is sent and stored for it, the checks on
//  the Collect Payment form, the "where will it go" estimate, how the server's reply is summarised, and ₹ formatting.
//

import XCTest
@testable import Kinematic

@MainActor
final class PaymentAllocationTests: XCTestCase {

    private let base = PaymentInput(outlet_id: "o-1", mode: "cash", amount: 500, reference: nil, cheque_bank: nil,
                                    cheque_date: nil, cheque_image_url: nil, applied_to_invoices: nil, gps: nil)

    private func body(_ input: PaymentInput) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(input)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            XCTFail("the body is not a JSON object")
            return [:]
        }
        return dict
    }

    private func inv(_ id: String, _ no: String, _ date: String?, _ balance: Double?) -> OpenInvoice {
        OpenInvoice(invoiceId: id, invoiceNo: no, invoiceDate: date, balance: balance)
    }

    // MARK: - The payload: auto-allocate by default, or on account

    func testAutoAllocateSendsAutoAllocateTrueAndNoInvoices() throws {
        let p = PaymentAllocation.payload(choice: .autoAllocate)
        XCTAssertEqual(p.autoAllocate, true)
        XCTAssertNil(p.applied)
        let json = try body(PaymentAllocation.applyTo(base, payload: p))
        XCTAssertEqual(json["auto_allocate"] as? Bool, true)
        XCTAssertNil(json["applied_to_invoices"])
    }

    func testOnAccountSendsAutoAllocateFalseAndNoInvoices() throws {
        let p = PaymentAllocation.payload(choice: .onAccount)
        XCTAssertEqual(p.autoAllocate, false)
        XCTAssertNil(p.applied)
        let json = try body(PaymentAllocation.applyTo(base, payload: p))
        // An explicit false must reach the wire — only nil is left out.
        XCTAssertNotNil(json["auto_allocate"])
        XCTAssertEqual(json["auto_allocate"] as? Bool, false)
        XCTAssertNil(json["applied_to_invoices"])
    }

    func testAPaymentThatNeverChoseSendsNoAutoAllocateKeyAtAll() throws {
        let json = try body(base)
        XCTAssertNil(json["auto_allocate"])
        XCTAssertNil(json["applied_to_invoices"])
    }

    func testAManualAllocationWinsAndSuppressesAutoAllocate() throws {
        let manual = [AppliedInvoice(invoice_id: "i-1", amount: 300), AppliedInvoice(invoice_id: "i-2", amount: 200)]
        let p = PaymentAllocation.payload(choice: .autoAllocate, manual: manual)
        XCTAssertNil(p.autoAllocate)
        XCTAssertEqual(p.applied, manual)
        let json = try body(PaymentAllocation.applyTo(base, payload: p))
        XCTAssertNil(json["auto_allocate"])
        XCTAssertEqual((json["applied_to_invoices"] as? [Any])?.count, 2)
    }

    func testJunkManualEntriesAreDroppedLeavingTheChoiceInForce() {
        let junk = [AppliedInvoice(invoice_id: "", amount: 10), AppliedInvoice(invoice_id: "i-1", amount: 0)]
        let p = PaymentAllocation.payload(choice: .onAccount, manual: junk)
        XCTAssertEqual(p.autoAllocate, false)
        XCTAssertNil(p.applied)
    }

    func testApplyingAPayloadKeepsEverythingElse() throws {
        let original = PaymentInput(outlet_id: "o-9", mode: "upi", amount: 99.5, reference: "T1", cheque_bank: "SBI",
                                    cheque_date: "2026-10-01", cheque_image_url: "https://x/c.jpg", applied_to_invoices: nil,
                                    gps: GeoPoint(lat: 12.9, lng: 77.5))
        let out = PaymentAllocation.applyTo(original, payload: PaymentAllocation.payload(choice: .autoAllocate))
        XCTAssertEqual(out.outlet_id, "o-9")
        XCTAssertEqual(out.mode, "upi")
        XCTAssertEqual(out.amount, 99.5)
        XCTAssertEqual(out.reference, "T1")
        XCTAssertEqual(out.cheque_bank, "SBI")
        XCTAssertEqual(out.cheque_date, "2026-10-01")
        XCTAssertEqual(out.cheque_image_url, "https://x/c.jpg")
        XCTAssertEqual(out.gps?.lat, 12.9)
        XCTAssertEqual(out.auto_allocate, true)
    }

    func testTheInvoiceNumberOnAnAllocationIsOnlySentWhenKnown() throws {
        let encoder = JSONEncoder()
        let withNo = try JSONSerialization.jsonObject(with: encoder.encode(AppliedInvoice(invoice_id: "i-1", amount: 1, invoice_no: "INV-1")))
        let without = try JSONSerialization.jsonObject(with: encoder.encode(AppliedInvoice(invoice_id: "i-1", amount: 1)))
        XCTAssertEqual((withNo as? [String: Any])?["invoice_no"] as? String, "INV-1")
        XCTAssertNil((without as? [String: Any])?["invoice_no"])
    }

    func testTheSameValueAlwaysEncodesToTheSameBytesWithSortedKeys() throws {
        // The server compares a replay's body with the first attempt's; a queued write is re-encoded in a later
        // process, so the bytes must not depend on dictionary ordering.
        let input = PaymentAllocation.applyTo(
            PaymentInput(outlet_id: "o-1", mode: "upi", amount: 99.5, reference: "T1", cheque_bank: nil, cheque_date: nil,
                         cheque_image_url: nil, applied_to_invoices: nil, gps: GeoPoint(lat: 12.9, lng: 77.5)),
            payload: PaymentAllocation.payload(choice: .autoAllocate))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(input)
        let second = try encoder.encode(input)
        XCTAssertEqual(first, second)
        let text = String(decoding: first, as: UTF8.self)
        XCTAssertEqual(text, #"{"amount":99.5,"auto_allocate":true,"gps":{"lat":12.9,"lng":77.5},"mode":"upi","outlet_id":"o-1","reference":"T1"}"#)
    }

    // MARK: - The queue row

    func testTheChoiceAndTheOutletNameSurviveTheOfflineQueue() throws {
        let input = PaymentAllocation.applyTo(base, payload: PaymentAllocation.payload(choice: .onAccount))
        let row = PendingPayment(id: UUID(), idempotencyKey: "pay-1", userKey: "u:user-1", input: input,
                                 createdAt: Date(timeIntervalSince1970: 800_000_000), attempt: 0, lastError: nil,
                                 isSynced: false, outletName: "Sri Balaji")
        let data = try JSONEncoder().encode([row])
        let back = try JSONDecoder().decode([PendingPayment].self, from: data)
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].input.auto_allocate, false)
        XCTAssertEqual(back[0].outletName, "Sri Balaji")
        XCTAssertEqual(back[0].idempotencyKey, "pay-1")
    }

    func testRowsQueuedBeforeThisChangeStillLoadAndAreSentAsTheyAlwaysWere() throws {
        let legacy = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","idempotencyKey":"pay-1","userKey":"u:user-1",
          "input":{"outlet_id":"o-1","mode":"cash","amount":120.5},
          "createdAt":800000000,"attempt":2,"lastError":"HTTP 503: x","isSynced":false}]
        """
        let rows = try JSONDecoder().decode([PendingPayment].self, from: Data(legacy.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].input.auto_allocate)
        XCTAssertNil(rows[0].input.applied_to_invoices)
        XCTAssertNil(rows[0].outletName)
        XCTAssertEqual(rows[0].attempt, 2)
        XCTAssertEqual(rows[0].input.amount, 120.5)
        XCTAssertEqual(DistributionQueuePolicy.item(for: rows[0]).title, "Payment")
    }

    // MARK: - The amount

    func testAValidAmountIsReadToThePaisa() {
        XCTAssertEqual(PaymentAllocation.parseAmount("500"), 500)
        XCTAssertEqual(PaymentAllocation.parseAmount(" 1250.5 "), 1250.5)
        XCTAssertEqual(PaymentAllocation.parseAmount("10.456"), 10.46)
        XCTAssertEqual(PaymentAllocation.parseAmount("100000000"), 100_000_000)
    }

    func testZeroNegativeEmptyJunkAndAbsurdAmountsAreRefused() {
        for text in ["", " ", "0", "0.00", "0.004", "-5", "abc", "1.2.3", ".", "NaN", "Infinity", "100000001", "1e400"] {
            XCTAssertNil(PaymentAllocation.parseAmount(text), "'\(text)'")
            XCTAssertNotNil(PaymentAllocation.amountError(text), "'\(text)'")
        }
        XCTAssertNil(PaymentAllocation.amountError("500"))
        XCTAssertNil(PaymentAllocation.amountError("100000000"))
    }

    func testEachBadAmountGetsItsOwnMessage() {
        XCTAssertEqual(PaymentAllocation.amountError(""), "Enter a valid amount")
        XCTAssertEqual(PaymentAllocation.amountError("abc"), "Enter a valid amount")
        XCTAssertEqual(PaymentAllocation.amountError("0"), "Amount must be more than zero")
        XCTAssertEqual(PaymentAllocation.amountError("-3"), "Amount must be more than zero")
        XCTAssertEqual(PaymentAllocation.amountError("100000001"), "Amount is too large")
    }

    func testTheAmountBoxKeepsDigitsAndOneDecimalPoint() {
        XCTAssertEqual(PaymentAllocation.sanitizeAmountInput("12a3"), "123")
        XCTAssertEqual(PaymentAllocation.sanitizeAmountInput("1,5"), "1.5")
        XCTAssertEqual(PaymentAllocation.sanitizeAmountInput("1.2.3"), "1.23")
        XCTAssertEqual(PaymentAllocation.sanitizeAmountInput("₹ 500"), "500")
        XCTAssertEqual(PaymentAllocation.sanitizeAmountInput(""), "")
        XCTAssertEqual(PaymentAllocation.sanitizeAmountInput("-5"), "5")
    }

    // MARK: - The form

    func testAnOutletIsNeededBeforeAnythingElse() {
        XCTAssertEqual(PaymentAllocation.validate(outletId: "", amountText: "500", mode: "cash", hasChequeImage: false), "Choose an outlet first")
        XCTAssertEqual(PaymentAllocation.validate(outletId: nil, amountText: "500", mode: "cash", hasChequeImage: false), "Choose an outlet first")
        XCTAssertEqual(PaymentAllocation.validate(outletId: "  ", amountText: "500", mode: "cash", hasChequeImage: false), "Choose an outlet first")
    }

    func testTheAmountMustBeMoreThanZero() {
        XCTAssertEqual(PaymentAllocation.validate(outletId: "o-1", amountText: "0", mode: "cash", hasChequeImage: false), "Amount must be more than zero")
        XCTAssertEqual(PaymentAllocation.validate(outletId: "o-1", amountText: "", mode: "cash", hasChequeImage: false), "Enter a valid amount")
    }

    func testAChequeNeedsItsPhotoOtherModesDoNotAndNothingNeedsTheNetwork() {
        XCTAssertEqual(PaymentAllocation.validate(outletId: "o-1", amountText: "500", mode: "cheque", hasChequeImage: false), "Cheque image is required")
        XCTAssertNil(PaymentAllocation.validate(outletId: "o-1", amountText: "500", mode: "cheque", hasChequeImage: true))
        for mode in ["cash", "upi", "credit_adjustment"] {
            XCTAssertNil(PaymentAllocation.validate(outletId: "o-1", amountText: "500", mode: mode, hasChequeImage: false), mode)
        }
    }

    // MARK: - The "where will it go" estimate

    func testTheAmountFillsTheOldestInvoiceFirstAndTheRestGoesToTheNext() {
        let invoices = [inv("i-new", "INV-2", "2026-10-05", 400), inv("i-old", "INV-1", "2026-09-01", 300)]
        let p = PaymentAllocation.preview(amount: 500, invoices: invoices)
        XCTAssertEqual(p.lines.map { $0.invoiceNo }, ["INV-1", "INV-2"])
        XCTAssertEqual(p.lines.map { $0.amount }, [300, 200])
        XCTAssertEqual(p.onAccount, 0)
    }

    func testWhateverExceedsTheOpenInvoicesStaysOnAccount() {
        let p = PaymentAllocation.preview(amount: 1000, invoices: [inv("i-1", "INV-1", "2026-09-01", 300)])
        XCTAssertEqual(p.lines.map { $0.amount }, [300])
        XCTAssertEqual(p.onAccount, 700)
    }

    func testASmallPaymentLandsOnTheFirstInvoiceOnly() {
        let p = PaymentAllocation.preview(amount: 50, invoices: [inv("i-1", "INV-1", "2026-09-01", 300), inv("i-2", "INV-2", "2026-09-02", 100)])
        XCTAssertEqual(p.lines.count, 1)
        XCTAssertEqual(p.lines[0].amount, 50)
        XCTAssertEqual(p.onAccount, 0)
    }

    func testNoOpenInvoicesMeansEverythingIsOnAccount() {
        let p = PaymentAllocation.preview(amount: 250, invoices: [])
        XCTAssertTrue(p.lines.isEmpty)
        XCTAssertEqual(p.onAccount, 250)
    }

    func testInvoicesWithNoBalanceAreSkippedAndPaisaDoNotDrift() {
        let p = PaymentAllocation.preview(amount: 0.3, invoices: [
            inv("i-0", "INV-0", "2026-08-01", 0),
            inv("i-n", "INV-N", "2026-08-02", nil),
            inv("i-1", "INV-1", "2026-09-01", 0.1),
            inv("i-2", "INV-2", "2026-09-02", 0.2),
        ])
        XCTAssertEqual(p.lines.map { $0.invoiceNo }, ["INV-1", "INV-2"])
        XCTAssertEqual(p.lines.map { $0.amount }, [0.1, 0.2])
        XCTAssertEqual(p.onAccount, 0)
    }

    func testAZeroNegativeOrNonNumberAmountPreviewsNothing() {
        for amount in [0.0, -5.0, Double.nan] {
            let p = PaymentAllocation.preview(amount: amount, invoices: [inv("i-1", "INV-1", "2026-09-01", 300)])
            XCTAssertTrue(p.lines.isEmpty)
            XCTAssertEqual(p.onAccount, 0)
        }
    }

    func testInvoicesOnTheSameDayKeepTheServersOrderAndUndatedOnesGoLast() {
        let p = PaymentAllocation.preview(amount: 30, invoices: [
            inv("i-undated", "INV-U", nil, 10),
            inv("i-b", "INV-B", "2026-09-01", 10),
            inv("i-a", "INV-A", "2026-09-01", 10),
        ])
        XCTAssertEqual(p.lines.map { $0.invoiceNo }, ["INV-B", "INV-A", "INV-U"])
    }

    // MARK: - What the server did

    func testTheReplySaysWhereTheMoneyWent() {
        let reply = #"{"success":true,"data":{"id":"p1","payment_no":"PAY-1","amount":500,"applied_to_invoices":[{"invoice_id":"i-1","invoice_no":"INV-1","amount":300}]}}"#
        XCTAssertEqual(PaymentAllocation.summary(fromReplyData: Data(reply.utf8)), "₹300.00 → INV-1 · ₹200.00 on account")
    }

    func testAFullyAllocatedPaymentHasNoOnAccountPart() {
        let reply = #"{"data":{"amount":500,"applied_to_invoices":[{"invoice_id":"i-1","invoice_no":"INV-1","amount":300},{"invoice_id":"i-2","invoice_no":"INV-2","amount":200}]}}"#
        XCTAssertEqual(PaymentAllocation.summary(fromReplyData: Data(reply.utf8)), "₹300.00 → INV-1 · ₹200.00 → INV-2")
    }

    func testAPaymentKeptOnAccountSaysSo() {
        let reply = #"{"data":{"amount":500,"applied_to_invoices":[]}}"#
        XCTAssertEqual(PaymentAllocation.summary(fromReplyData: Data(reply.utf8)), "₹500.00 on account")
    }

    func testAReplyWithoutAnAllocationListOrAnUnreadableOneSaysNothing() {
        XCTAssertNil(PaymentAllocation.summary(fromReplyData: Data(#"{"data":{"amount":500}}"#.utf8)))
        XCTAssertNil(PaymentAllocation.summary(fromReplyData: Data("not json".utf8)))
        XCTAssertNil(PaymentAllocation.summary(fromReplyData: nil))
    }

    func testAnAllocationWithoutAnInvoiceNumberShowsTheStartOfItsId() {
        let reply = #"{"data":{"amount":100,"applied_to_invoices":[{"invoice_id":"12345678-aaaa-bbbb-cccc-123456789012","amount":100}]}}"#
        XCTAssertEqual(PaymentAllocation.summary(fromReplyData: Data(reply.utf8)), "₹100.00 → 12345678")
    }

    // MARK: - ₹ formatting

    func testRupeesUseIndianGroupingAndTwoDecimals() {
        XCTAssertEqual(DistributionMoney.rupees(12500.5), "₹12,500.50")
        XCTAssertEqual(DistributionMoney.rupees(1234567.891), "₹12,34,567.89")
        XCTAssertEqual(DistributionMoney.rupees(5), "₹5.00")
        XCTAssertEqual(DistributionMoney.rupees(0), "₹0.00")
        XCTAssertEqual(DistributionMoney.rupees(1000), "₹1,000.00")
    }

    func testRupeesCanDropThePaisa() {
        XCTAssertEqual(DistributionMoney.rupees(12500, decimals: false), "₹12,500")
        XCTAssertEqual(DistributionMoney.rupees(12499.5, decimals: false), "₹12,500")
        XCTAssertEqual(DistributionMoney.rupees(0, decimals: false), "₹0")
    }

    func testRupeesNeverShowNaNOrAMinusOnZero() {
        XCTAssertEqual(DistributionMoney.rupees(nil), "₹0.00")
        XCTAssertEqual(DistributionMoney.rupees(Double.nan), "₹0.00")
        XCTAssertEqual(DistributionMoney.rupees(Double.infinity), "₹0.00")
        XCTAssertEqual(DistributionMoney.rupees(-0.001), "₹0.00")
        XCTAssertEqual(DistributionMoney.rupees(-50), "-₹50.00")
    }

    func testIndianDigitGrouping() {
        XCTAssertEqual(DistributionMoney.groupIndian("999"), "999")
        XCTAssertEqual(DistributionMoney.groupIndian("1000"), "1,000")
        XCTAssertEqual(DistributionMoney.groupIndian("100000"), "1,00,000")
        XCTAssertEqual(DistributionMoney.groupIndian("1234567"), "12,34,567")
        XCTAssertEqual(DistributionMoney.groupIndian("12345678901"), "12,34,56,78,901")
    }
}
