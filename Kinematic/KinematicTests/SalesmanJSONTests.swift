//
//  SalesmanJSONTests.swift
//  KinematicTests
//
//  The readers for GET /salesman/outlets, GET /salesman/outlets/{id}/outstanding and the replies of the create
//  calls: they take the `{ success, data }` envelope or the bare payload, tolerate numbers sent as strings, skip one
//  unreadable row instead of failing the list, and never throw.
//

import XCTest
@testable import Kinematic

@MainActor
final class SalesmanJSONTests: XCTestCase {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: - Outlets

    func testOutletsAreReadFromTheSuccessEnvelope() {
        let outlets = SalesmanJSON.outlets(fromData: data("""
        {"success":true,"data":[
          {"id":"o-1","name":"Sri Balaji","code":"SB01","address":"MG Road","city":"Hyderabad","phone":"9000000001",
           "distributor_id":"d-1","distributor_name":"Gomant North","outstanding_balance":12500.5},
          {"id":"o-2","name":"Lakshmi Stores","code":null,"address":null,"city":null,"phone":null,
           "distributor_id":null,"distributor_name":null,"outstanding_balance":0}
        ]}
        """))
        XCTAssertEqual(outlets.count, 2)
        XCTAssertEqual(outlets[0].id, "o-1")
        XCTAssertEqual(outlets[0].name, "Sri Balaji")
        XCTAssertEqual(outlets[0].code, "SB01")
        XCTAssertEqual(outlets[0].address, "MG Road")
        XCTAssertEqual(outlets[0].city, "Hyderabad")
        XCTAssertEqual(outlets[0].phone, "9000000001")
        XCTAssertEqual(outlets[0].distributorId, "d-1")
        XCTAssertEqual(outlets[0].distributorName, "Gomant North")
        XCTAssertEqual(outlets[0].outstandingBalance, 12500.5)
        XCTAssertNil(outlets[1].code)
        XCTAssertNil(outlets[1].distributorId)
        XCTAssertEqual(outlets[1].outstandingBalance, 0)
    }

    func testABareArrayAndANumericStringBalanceAreAccepted() {
        let outlets = SalesmanJSON.outlets(fromData: data(#"[{"id":"o-1","name":"A","outstanding_balance":"1,250.50"}]"#))
        XCTAssertEqual(outlets.count, 1)
        XCTAssertEqual(outlets[0].outstandingBalance, 1250.5)
    }

    func testTheListMayAlsoSitUnderOutletsOrItems() {
        XCTAssertEqual(SalesmanJSON.outlets(fromData: data(#"{"data":{"outlets":[{"id":"o-1"}]}}"#)).map { $0.id }, ["o-1"])
        XCTAssertEqual(SalesmanJSON.outlets(fromData: data(#"{"items":[{"id":"o-2"}]}"#)).map { $0.id }, ["o-2"])
    }

    func testARowWithoutAnIdOrThatIsNotAnObjectIsSkippedAndTheRestLoad() {
        let outlets = SalesmanJSON.outlets(fromData: data(#"{"data":[{"name":"no id"}, 7, null, {"id":"o-9","name":"ok"}]}"#))
        XCTAssertEqual(outlets.map { $0.id }, ["o-9"])
    }

    func testANumericIdReadsAsItsText() {
        XCTAssertEqual(SalesmanJSON.outlets(fromData: data(#"[{"id":42,"name":"  Shop  "}]"#)).map { $0.id }, ["42"])
        XCTAssertEqual(SalesmanJSON.outlets(fromData: data(#"[{"id":42,"name":"  Shop  "}]"#)).first?.name, "Shop")
    }

    func testUnreadableOutletRepliesGiveAnEmptyList() {
        XCTAssertTrue(SalesmanJSON.outlets(fromData: nil).isEmpty)
        XCTAssertTrue(SalesmanJSON.outlets(fromData: Data()).isEmpty)
        XCTAssertTrue(SalesmanJSON.outlets(fromData: data("not json")).isEmpty)
        XCTAssertTrue(SalesmanJSON.outlets(fromData: data(#"{"success":true,"data":null}"#)).isEmpty)
        XCTAssertTrue(SalesmanJSON.outlets(fromData: data("\"oops\"")).isEmpty)
        XCTAssertTrue(SalesmanJSON.outlets(fromData: data(#"{"success":false,"error":"x"}"#)).isEmpty)
    }

    // MARK: - Outstanding

    func testOutstandingIsReadFromTheSuccessEnvelope() throws {
        let o = try XCTUnwrap(SalesmanJSON.outstanding(fromData: data("""
        {"success":true,"data":{"outlet_id":"o-1","outlet_name":"Sri Balaji","balance":700,"credit_limit":null,
         "open_invoices":[
           {"invoice_id":"i-1","invoice_no":"INV-1","invoice_date":"2026-09-01","due_date":"2026-09-30","total":500,"paid":100,"balance":400},
           {"invoice_id":"i-2","invoice_no":"INV-2","invoice_date":"2026-10-01","due_date":null,"total":300,"paid":0,"balance":300}
        ]}}
        """)))
        XCTAssertEqual(o.outletId, "o-1")
        XCTAssertEqual(o.outletName, "Sri Balaji")
        XCTAssertEqual(o.balance, 700)
        XCTAssertNil(o.creditLimit)
        XCTAssertEqual(o.openInvoices.map { $0.invoiceNo }, ["INV-1", "INV-2"])
        XCTAssertEqual(o.openInvoices[0].dueDate, "2026-09-30")
        XCTAssertEqual(o.openInvoices[0].paid, 100)
        XCTAssertEqual(o.openInvoices[0].balance, 400)
        XCTAssertNil(o.openInvoices[1].dueDate)
    }

    func testOutstandingWithoutTheEnvelopeAndWithACreditLimitIsReadToo() throws {
        let o = try XCTUnwrap(SalesmanJSON.outstanding(fromData: data(#"{"outlet_id":"o-1","balance":"250.00","credit_limit":100000,"open_invoices":[]}"#)))
        XCTAssertEqual(o.balance, 250)
        XCTAssertEqual(o.creditLimit, 100000)
        XCTAssertTrue(o.openInvoices.isEmpty)
    }

    func testAnOutstandingReplyWithNoInvoiceListStillLoadsAndBadInvoicesAreSkipped() throws {
        let none = try XCTUnwrap(SalesmanJSON.outstanding(fromData: data(#"{"data":{"outlet_id":"o-1","balance":0}}"#)))
        XCTAssertTrue(none.openInvoices.isEmpty)
        let some = try XCTUnwrap(SalesmanJSON.outstanding(fromData: data(#"{"data":{"balance":5,"open_invoices":[{"invoice_no":"no id"},{"invoice_id":"i-1","balance":5}]}}"#)))
        XCTAssertEqual(some.openInvoices.map { $0.invoiceId }, ["i-1"])
    }

    func testAnOutstandingReplyThatIsNotAnObjectIsUnreadable() {
        XCTAssertNil(SalesmanJSON.outstanding(fromData: nil))
        XCTAssertNil(SalesmanJSON.outstanding(fromData: data("[1,2]")))
        XCTAssertNil(SalesmanJSON.outstanding(fromData: data("\"x\"")))
        XCTAssertNil(SalesmanJSON.outstanding(fromData: data("not json")))
    }

    func testTheOutstandingResultHelpers() {
        let loaded = OutstandingResult.loaded(OutletOutstanding(balance: 5))
        XCTAssertEqual(loaded.loadedValue?.balance, 5)
        XCTAssertFalse(loaded.isOffline)
        XCTAssertNil(OutstandingResult.offline.loadedValue)
        XCTAssertTrue(OutstandingResult.offline.isOffline)
        XCTAssertNil(OutstandingResult.unavailable.loadedValue)
        XCTAssertFalse(OutstandingResult.unavailable.isOffline)
    }

    // MARK: - Replies of the create calls

    func testTheReferenceIsTheOrderPaymentOrReturnNumber() {
        XCTAssertEqual(SalesmanJSON.reference(fromData: data(#"{"success":true,"message":"Payment recorded","data":{"id":"p1","payment_no":"PAY-000123","status":"cleared"}}"#)), "PAY-000123")
        XCTAssertEqual(SalesmanJSON.reference(fromData: data(#"{"success":true,"data":{"order_no":"ORD-9"}}"#)), "ORD-9")
        XCTAssertEqual(SalesmanJSON.reference(fromData: data(#"{"data":{"return_no":"RET-2"}}"#)), "RET-2")
    }

    func testNoReferenceWhenTheReplyHasNoneOrCannotBeRead() {
        XCTAssertNil(SalesmanJSON.reference(fromData: data(#"{"success":true,"data":{"id":"x"}}"#)))
        XCTAssertNil(SalesmanJSON.reference(fromData: data("not json")))
        XCTAssertNil(SalesmanJSON.reference(fromData: nil))
    }

    func testThePaymentReplyListsWhereTheMoneyWent() throws {
        let reply = try XCTUnwrap(SalesmanJSON.paymentReply(fromData: data(#"""
        {"success":true,"data":{"payment_no":"PAY-1","amount":"500","applied_to_invoices":[
          {"invoice_id":"i-1","invoice_no":"INV-1","amount":300},
          {"invoice_id":"i-2","amount":0},
          {"amount":10},
          "junk"
        ]}}
        """#)))
        XCTAssertEqual(reply.paymentNo, "PAY-1")
        XCTAssertEqual(reply.amount, 500)
        // The zero amount, the entry with no invoice and the junk entry are dropped.
        XCTAssertEqual(reply.applied, [PaymentReplyLine(invoiceId: "i-1", invoiceNo: "INV-1", amount: 300)])
    }
}
