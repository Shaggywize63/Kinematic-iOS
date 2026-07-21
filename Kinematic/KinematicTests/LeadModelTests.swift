//
//  LeadModelTests.swift
//  KinematicTests
//
//  Decode / encode round-trip + computed-property coverage for `Lead`.
//

import XCTest
@testable import Kinematic

@MainActor
final class LeadModelTests: XCTestCase {

    private let representativeJSON = """
    {
      "id": "lead-123",
      "org_id": "org-1",
      "first_name": "Asha",
      "last_name": "Rao",
      "email": "asha@example.com",
      "phone": "+919876543210",
      "alternate_mobiles": ["+919000000001", "+919000000002"],
      "company": "Tiscon Dealer",
      "title": "Owner",
      "source": "walk_in",
      "status": "new",
      "score": 85.5,
      "owner_id": "user-9",
      "owner_name": "Rep One",
      "assigned_to": "user-9",
      "created_by": "user-1",
      "tags": ["hot", "north"],
      "custom_fields": {"budget": "500000", "vip": true},
      "notes": "Follow up next week",
      "is_b2c": false,
      "address_line1": "12 MG Road",
      "address_line2": "Suite 4",
      "city": "Pune",
      "state": "Maharashtra",
      "postal_code": "411001",
      "country": "India",
      "marketing_consent": true,
      "whatsapp_consent": false,
      "latitude": 18.52,
      "longitude": 73.85,
      "created_at": "2026-01-02T10:00:00Z",
      "updated_at": "2026-01-03T10:00:00Z"
    }
    """

    func testDecodeMapsSnakeCaseFields() throws {
        let lead = try TestFixtures.lead(json: representativeJSON)
        XCTAssertEqual(lead.id, "lead-123")
        XCTAssertEqual(lead.orgId, "org-1")
        XCTAssertEqual(lead.firstName, "Asha")
        XCTAssertEqual(lead.lastName, "Rao")
        XCTAssertEqual(lead.email, "asha@example.com")
        XCTAssertEqual(lead.score, 85.5)
        XCTAssertEqual(lead.ownerId, "user-9")
        XCTAssertEqual(lead.assignedTo, "user-9")
        XCTAssertEqual(lead.createdBy, "user-1")
        XCTAssertEqual(lead.isB2c, false)
        XCTAssertEqual(lead.city, "Pune")
        XCTAssertEqual(lead.postalCode, "411001")
        XCTAssertEqual(lead.latitude, 18.52)
        XCTAssertEqual(lead.longitude, 73.85)
        XCTAssertEqual(lead.tags?.count, 2)
        XCTAssertEqual(lead.alternateMobiles?.count, 2)
        XCTAssertEqual(lead.alternateMobiles?.first, "+919000000001")
    }

    func testDecodeCustomFieldsPreservesTypes() throws {
        let lead = try TestFixtures.lead(json: representativeJSON)
        // String custom field keeps its scalar-string convenience value.
        XCTAssertEqual(lead.customFields?["budget"]?.value, "500000")
        XCTAssertEqual(lead.customFields?["budget"]?.raw, .string("500000"))
        // Bool custom field: probed as Bool, not a number.
        XCTAssertEqual(lead.customFields?["vip"]?.raw, .bool(true))
        XCTAssertEqual(lead.customFields?["vip"]?.value, "true")
    }

    func testEncodeDecodeRoundTripIsStable() throws {
        let lead = try TestFixtures.lead(json: representativeJSON)
        let data = try JSONEncoder().encode(lead)
        let again = try JSONDecoder().decode(Lead.self, from: data)
        XCTAssertEqual(lead, again)
    }

    func testDisplayNameCombinesFirstAndLast() throws {
        let lead = try TestFixtures.lead(json: representativeJSON)
        XCTAssertEqual(lead.displayName, "Asha Rao")
    }

    func testDisplayNameFallsBackToEmailThenPlaceholder() throws {
        let emailOnly = try TestFixtures.lead(json: #"{"id":"x","email":"only@e.com"}"#)
        XCTAssertEqual(emailOnly.displayName, "only@e.com")

        let firstOnly = try TestFixtures.lead(json: #"{"id":"x","first_name":"Sam"}"#)
        XCTAssertEqual(firstOnly.displayName, "Sam")

        let bare = try TestFixtures.lead(json: #"{"id":"x"}"#)
        XCTAssertEqual(bare.displayName, "Unnamed Lead")
    }

    func testFullAddressJoinsPresentPartsInOrder() throws {
        let lead = try TestFixtures.lead(json: representativeJSON)
        XCTAssertEqual(lead.fullAddress, "12 MG Road, Suite 4, Pune, Maharashtra, 411001, India")
    }

    func testFullAddressSkipsMissingAndEmptyParts() throws {
        let partial = try TestFixtures.lead(json: #"{"id":"x","city":"Delhi","country":"India"}"#)
        XCTAssertEqual(partial.fullAddress, "Delhi, India")

        let none = try TestFixtures.lead(json: #"{"id":"x"}"#)
        XCTAssertNil(none.fullAddress)
    }
}
