//
//  ContactEditingTests.swift
//  KinematicTests
//
//  The contact screens' pure logic: the edit request body (a business contact never sends consumer-only keys,
//  a blank city is left out, the Company rides along only when changed), the delete confirmation wording, the
//  company line on a contact row and the account detail's contacts header.
//

import XCTest
import Foundation
@testable import Kinematic

final class ContactEditingTests: XCTestCase {

    private func contact(_ json: String) throws -> Contact {
        try JSONDecoder().decode(Contact.self, from: Data(json.utf8))
    }

    private func business() -> ContactEditDraft {
        var d = ContactEditDraft()
        d.firstName = "Asha"
        d.lastName = "Rao"
        d.email = "asha@acme.test"
        d.phone = "9000000001"
        d.mobile = "9000000002"
        d.title = "Buyer"
        d.department = "Purchase"
        d.isB2C = false
        // Leftovers a business contact's form may still hold must never be sent.
        d.city = "Pune"
        d.gender = "female"
        d.marketingConsent = true
        return d
    }

    private func consumer() -> ContactEditDraft {
        var d = ContactEditDraft()
        d.firstName = "Ravi"
        d.lastName = "Iyer"
        d.isB2C = true
        d.dateOfBirth = "1990-05-01"
        d.gender = "male"
        d.addressLine1 = "12 MG Road"
        d.city = "Pune"
        d.state = "Maharashtra"
        d.postalCode = "411001"
        d.country = "India"
        d.preferredContactMethod = "whatsapp"
        d.loyaltyTier = "gold"
        d.referralSource = "friend"
        d.marketingConsent = true
        d.whatsappConsent = false
        return d
    }

    private func patch(_ d: ContactEditDraft, companyEditable: Bool = false, selected: String = "", original: String? = nil) -> [String: Any] {
        ContactEditBody.patch(d, companyEditable: companyEditable, selectedCompanyId: selected, originalCompanyId: original)
    }

    // MARK: - edit body

    func testABusinessContactSendsOnlyItsOwnKeys() {
        let body = patch(business())
        XCTAssertEqual(
            Set(body.keys),
            ["first_name", "last_name", "email", "phone", "mobile", "is_b2c", "title", "department"]
        )
        XCTAssertEqual(body["is_b2c"] as? Bool, false)
        XCTAssertEqual(body["title"] as? String, "Buyer")
        XCTAssertEqual(body["department"] as? String, "Purchase")
        for key in ContactEditBody.consumerOnlyKeys { XCTAssertNil(body[key], key) }
    }

    func testAConsumerContactSendsTheConsumerKeys() {
        let body = patch(consumer())
        XCTAssertEqual(body["is_b2c"] as? Bool, true)
        XCTAssertEqual(body["date_of_birth"] as? String, "1990-05-01")
        XCTAssertEqual(body["gender"] as? String, "male")
        XCTAssertEqual(body["address_line1"] as? String, "12 MG Road")
        XCTAssertEqual(body["city"] as? String, "Pune")
        XCTAssertEqual(body["state"] as? String, "Maharashtra")
        XCTAssertEqual(body["postal_code"] as? String, "411001")
        XCTAssertEqual(body["country"] as? String, "India")
        XCTAssertEqual(body["preferred_contact_method"] as? String, "whatsapp")
        XCTAssertEqual(body["loyalty_tier"] as? String, "gold")
        XCTAssertEqual(body["referral_source"] as? String, "friend")
        XCTAssertEqual(body["marketing_consent"] as? Bool, true)
        XCTAssertEqual(body["whatsapp_consent"] as? Bool, false)
        // The business-only keys stay home.
        XCTAssertNil(body["title"])
        XCTAssertNil(body["department"])
    }

    func testABlankCityIsOmittedNeverNull() {
        var d = consumer()
        d.city = ""
        XCTAssertNil(patch(d)["city"])
        XCTAssertFalse(patch(d).keys.contains("city"))
        d.city = "   "
        XCTAssertFalse(patch(d).keys.contains("city"))
        // The other blanks still clear their field.
        d.state = ""
        XCTAssertTrue(patch(d)["state"] is NSNull)
    }

    func testBlankCommonFieldsClearTheirValueAndValuesAreTrimmed() {
        var d = business()
        d.email = ""
        d.firstName = "  Asha "
        let body = patch(d)
        XCTAssertTrue(body["email"] is NSNull)
        XCTAssertEqual(body["first_name"] as? String, "Asha")
    }

    func testTheCompanyIsSentOnlyWhenItChanged() {
        // Unchanged: no account_id.
        XCTAssertNil(patch(business(), companyEditable: true, selected: "acc-1", original: "acc-1")["account_id"])
        XCTAssertNil(patch(business(), companyEditable: true, selected: "", original: nil)["account_id"])
        // Changed: the new id.
        XCTAssertEqual(patch(business(), companyEditable: true, selected: "acc-2", original: "acc-1")["account_id"] as? String, "acc-2")
        XCTAssertEqual(patch(business(), companyEditable: true, selected: "acc-2", original: nil)["account_id"] as? String, "acc-2")
        // Cleared: an explicit null unlinks.
        XCTAssertTrue(patch(business(), companyEditable: true, selected: "", original: "acc-1")["account_id"] is NSNull)
        // Not editable (the Company row is not on screen): never sent.
        XCTAssertNil(patch(business(), companyEditable: false, selected: "acc-2", original: "acc-1")["account_id"])
    }

    func testCompanyChangeTreatsBlankAndNilAsNone() {
        XCTAssertFalse(ContactEditBody.companyChanged(selected: "", original: nil))
        XCTAssertFalse(ContactEditBody.companyChanged(selected: " ", original: ""))
        XCTAssertTrue(ContactEditBody.companyChanged(selected: "a", original: nil))
        XCTAssertTrue(ContactEditBody.companyChanged(selected: "", original: "a"))
    }

    // MARK: - delete

    func testDeleteConfirmationWording() {
        XCTAssertEqual(ContactDeletion.confirmationTitle(name: "Asha Rao"), "Delete Asha Rao?")
        XCTAssertEqual(
            ContactDeletion.confirmationMessage(name: "Asha Rao"),
            "Delete Asha Rao? It is removed from lists and can be recovered by support."
        )
        XCTAssertEqual(
            ContactDeletion.confirmationMessage(name: "  "),
            "Delete this contact? It is removed from lists and can be recovered by support."
        )
    }

    func testDeletingARowRemovesOnlyThatContactAndKeepsTheOrder() throws {
        let list = [try contact(#"{"id":"c1"}"#), try contact(#"{"id":"c2"}"#), try contact(#"{"id":"c3"}"#)]
        XCTAssertEqual(ContactDeletion.removing(id: "c2", from: list).map { $0.id }, ["c1", "c3"])
        XCTAssertEqual(ContactDeletion.removing(id: "zzz", from: list).map { $0.id }, ["c1", "c2", "c3"])
    }

    // MARK: - company on a contact row

    func testNonSparkTenantsSeeTheAccountNameLabelledAccount() throws {
        let c = try contact(#"{"id":"c1","account_id":"acc-1","account_name":" Acme Forge "}"#)
        let line = try XCTUnwrap(ContactCompanyDisplay.line(for: c, spark: false))
        XCTAssertEqual(line.label, "Account")
        XCTAssertEqual(line.name, "Acme Forge")
        XCTAssertEqual(line.id, "acc-1")
        XCTAssertEqual(line.text, "Account: Acme Forge")
    }

    func testSparkTenantsSeeItLabelledCompany() throws {
        let c = try contact(#"{"id":"c1","account_id":"acc-1","account_name":"Acme Forge"}"#)
        let line = try XCTUnwrap(ContactCompanyDisplay.line(for: c, spark: true))
        XCTAssertEqual(line.label, "Company")
        XCTAssertEqual(line.text, "Company: Acme Forge")
        XCTAssertEqual(line.id, "acc-1")
    }

    func testNothingIsShownWhenThereIsNoAccountName() throws {
        let bare = try contact(#"{"id":"c1","first_name":"Asha"}"#)
        XCTAssertNil(ContactCompanyDisplay.line(for: bare, spark: false))
        XCTAssertNil(ContactCompanyDisplay.line(for: bare, spark: true))
        let blank = try contact(#"{"id":"c2","account_id":"acc-1","account_name":"  "}"#)
        XCTAssertNil(ContactCompanyDisplay.line(for: blank, spark: false))
    }

    func testANameWithoutAnIdIsPlainText() throws {
        let c = try contact(#"{"id":"c1","account_name":"Acme Forge"}"#)
        XCTAssertNil(ContactCompanyDisplay.line(for: c, spark: false)?.id)
        XCTAssertEqual(ContactCompanyDisplay.line(for: c, spark: false)?.name, "Acme Forge")
    }

    // MARK: - account detail contacts section

    func testTheContactsHeaderShowsTheCountAndTheEmptyTextIsFixed() {
        XCTAssertEqual(AccountContactsDisplay.header(count: 3), "Contacts (3)")
        XCTAssertEqual(AccountContactsDisplay.header(count: 0), "Contacts (0)")
        XCTAssertEqual(AccountContactsDisplay.emptyText, "No contacts yet.")
    }

    func testAContactDecodesItsAccountName() throws {
        let c = try contact(#"{"id":"c1","account_id":"acc-1","account_name":"Acme Forge"}"#)
        XCTAssertEqual(c.accountName, "Acme Forge")
    }
}
