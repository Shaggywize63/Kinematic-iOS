//
//  NewOutletFormTests.swift
//  KinematicTests
//
//  The "Add new outlet" form: what is required, what is sent, and how a proposal's state reads to the rep.
//

import XCTest
@testable import Kinematic

final class NewOutletFormTests: XCTestCase {

    func testANameIsRequired() {
        XCTAssertEqual(NewOutletFormLogic.problem(name: "  ", phone: ""), "Enter the outlet name")
        XCTAssertNil(NewOutletFormLogic.problem(name: "Mapusa Mart", phone: ""))
    }

    func testAPhoneIsOptionalButMustLookLikeOne() {
        XCTAssertNil(NewOutletFormLogic.problem(name: "A", phone: "98220 12345"))
        XCTAssertNil(NewOutletFormLogic.problem(name: "A", phone: "+91 (832) 245-6789"))
        XCTAssertEqual(NewOutletFormLogic.problem(name: "A", phone: "call me"), "Phone number looks invalid")
        XCTAssertEqual(NewOutletFormLogic.problem(name: "A", phone: "123"), "Phone number looks invalid")
    }

    func testInputTrimsAndDropsBlanks() {
        let i = NewOutletFormLogic.input(name: " Mapusa Mart ", owner: " ", phone: " 9822012345 ", address: "",
                                         tradeType: "off_trade", lat: 15.59, lng: 73.81)
        XCTAssertEqual(i.name, "Mapusa Mart")
        XCTAssertNil(i.owner_name)
        XCTAssertEqual(i.phone, "9822012345")
        XCTAssertNil(i.address)
        XCTAssertEqual(i.trade_type, "off_trade")
        XCTAssertEqual(i.lat, 15.59)
        XCTAssertEqual(i.lng, 73.81)
    }

    func testBlankFieldsAreLeftOutOfTheJSON() throws {
        let i = NewOutletFormLogic.input(name: "A", owner: "", phone: "", address: "", tradeType: nil, lat: nil, lng: nil)
        let data = try JSONEncoder().encode(i)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["name"])
    }

    func testStatusLineTellsTheRepWhereAProposalStands() {
        func outlet(_ status: String?, _ reason: String? = nil) -> ProposedOutlet {
            ProposedOutlet(id: "1", name: nil, store_code: nil, approval_status: status, rejection_reason: reason)
        }
        XCTAssertEqual(NewOutletFormLogic.statusLine(outlet("pending")), "Waiting for approval")
        XCTAssertEqual(NewOutletFormLogic.statusLine(outlet("approved")), "Approved")
        XCTAssertEqual(NewOutletFormLogic.statusLine(outlet("rejected", "Duplicate")), "Refused: Duplicate")
        XCTAssertEqual(NewOutletFormLogic.statusLine(outlet("rejected")), "Refused")
        XCTAssertEqual(NewOutletFormLogic.statusLine(outlet(nil)), "Waiting for approval")
    }
}
