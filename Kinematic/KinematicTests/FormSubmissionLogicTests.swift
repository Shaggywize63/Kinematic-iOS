//
//  FormSubmissionLogicTests.swift
//  KinematicTests
//
//  The pure rules behind "My Reports" (a field executive's own filled-form entries): how a stored answer becomes
//  a readable string, which answers are editable, and how one submission becomes the plain-text report the share
//  sheet sends. Also pins the Codable decoding of the three backend shapes (list / detail / export) so a field
//  the server omits never breaks the whole response.
//

import XCTest
@testable import Kinematic

final class FormSubmissionLogicTests: XCTestCase {

    // MARK: numberText

    func testNumberTextDropsTrailingZeroOnWholeNumbers() {
        XCTAssertEqual(FormSubmissionLogic.numberText(12), "12")
        XCTAssertEqual(FormSubmissionLogic.numberText(12.0), "12")
        XCTAssertEqual(FormSubmissionLogic.numberText(0), "0")
    }

    func testNumberTextKeepsDecimals() {
        XCTAssertEqual(FormSubmissionLogic.numberText(12.5), "12.5")
    }

    // MARK: displayValue precedence (mirrors the backend)

    func testDisplayValuePrefersTextThenNumberThenBool() {
        XCTAssertEqual(FormSubmissionLogic.displayValue(valueText: "Hello", valueNumber: 9, valueBool: true), "Hello")
        XCTAssertEqual(FormSubmissionLogic.displayValue(valueText: nil, valueNumber: 9, valueBool: true), "9")
        XCTAssertEqual(FormSubmissionLogic.displayValue(valueText: "  ", valueNumber: nil, valueBool: false), "No")
        XCTAssertEqual(FormSubmissionLogic.displayValue(valueText: nil, valueNumber: nil, valueBool: true), "Yes")
        XCTAssertEqual(FormSubmissionLogic.displayValue(valueText: nil, valueNumber: nil, valueBool: nil), "")
    }

    // MARK: answerText (export mixed value)

    func testAnswerTextForEachScalar() {
        XCTAssertEqual(FormSubmissionLogic.answerText(.string("Open")), "Open")
        XCTAssertEqual(FormSubmissionLogic.answerText(.number(42)), "42")
        XCTAssertEqual(FormSubmissionLogic.answerText(.number(4.5)), "4.5")
        XCTAssertEqual(FormSubmissionLogic.answerText(.bool(true)), "Yes")
        XCTAssertEqual(FormSubmissionLogic.answerText(.bool(false)), "No")
        XCTAssertEqual(FormSubmissionLogic.answerText(.null), "")
        XCTAssertEqual(FormSubmissionLogic.answerText(nil), "")
    }

    func testAnswerTextJoinsArrays() {
        XCTAssertEqual(FormSubmissionLogic.answerText(.array([.string("A"), .string("B"), .null])), "A, B")
    }

    // MARK: isEditable

    func testImageAndLayoutTypesAreNotEditable() {
        for t in ["photo", "image", "camera", "signature", "file", "card_scan", "planogram", "PHOTO", "Signature"] {
            XCTAssertFalse(FormSubmissionLogic.isEditable(qtype: t), "\(t) should be read-only")
        }
        XCTAssertFalse(FormSubmissionLogic.isEditable(qtype: "section"))
        XCTAssertFalse(FormSubmissionLogic.isEditable(qtype: "heading"))
    }

    func testTextTypesAndUnknownAreEditable() {
        for t in ["text", "textarea", "number", "email", "phone", "select", "rating"] {
            XCTAssertTrue(FormSubmissionLogic.isEditable(qtype: t), "\(t) should be editable")
        }
        XCTAssertTrue(FormSubmissionLogic.isEditable(qtype: nil))
        XCTAssertTrue(FormSubmissionLogic.isEditable(qtype: ""))
        XCTAssertTrue(FormSubmissionLogic.isEditable(qtype: "brand_new_future_type"))
    }

    // MARK: headline / submitter

    func testHeadlineFallsBackToFormTitleWhenNoRefOrDate() {
        XCTAssertEqual(FormSubmissionLogic.headline(refNo: "SRPR2627-1", submittedAt: "2026-11-02T10:00:00Z", formTitle: "Visit"),
                       "SRPR2627-1 · 02 Nov 2026")
        XCTAssertEqual(FormSubmissionLogic.headline(refNo: nil, submittedAt: nil, formTitle: "Store Audit"), "Store Audit")
        XCTAssertEqual(FormSubmissionLogic.headline(refNo: nil, submittedAt: nil, formTitle: nil), "Form submission")
    }

    func testSubmitterLine() {
        XCTAssertEqual(FormSubmissionLogic.submitterLine(FormSubmitter(id: "1", name: "Asha Rao", employeeId: "EMP-204")),
                       "Asha Rao (EMP-204)")
        XCTAssertEqual(FormSubmissionLogic.submitterLine(FormSubmitter(id: "1", name: "Asha Rao", employeeId: nil)), "Asha Rao")
        XCTAssertNil(FormSubmissionLogic.submitterLine(FormSubmitter(id: "1", name: "  ", employeeId: "X")))
        XCTAssertNil(FormSubmissionLogic.submitterLine(nil))
    }

    // MARK: sortedAnswers

    func testSortedAnswersOrderBySortOrderThenLabelMissingLast() {
        let answers = [
            FormExportAnswer(fieldId: "c", label: "Charlie", type: "text", sortOrder: nil, value: nil, gps: nil, photos: nil),
            FormExportAnswer(fieldId: "b", label: "Bravo", type: "text", sortOrder: 2, value: nil, gps: nil, photos: nil),
            FormExportAnswer(fieldId: "a", label: "Alpha", type: "text", sortOrder: 1, value: nil, gps: nil, photos: nil),
        ]
        let order = FormSubmissionLogic.sortedAnswers(answers).map { $0.fieldId }
        XCTAssertEqual(order, ["a", "b", "c"])
    }

    // MARK: photoURLs dedupe + prefer signed

    func testPhotoURLsDedupeAndPreferSigned() {
        let export = FormSubmissionExport(
            submissionId: "s1", refNo: "R-1", formTitle: "F", templateId: nil, activityName: nil, accountName: nil,
            submitter: nil, submittedAt: nil, outletName: nil, address: nil,
            answers: [
                FormExportAnswer(fieldId: "p", label: "Photo", type: "photo", sortOrder: 1, value: nil, gps: nil,
                                 photos: [SignedPhoto(url: "stored://a", signed: "https://signed/a")]),
            ],
            photos: [SignedPhoto(url: "stored://a", signed: "https://signed/a")],
            exportedAt: nil
        )
        // The same stored URL appears submission-level and under an answer → one entry, the signed link.
        XCTAssertEqual(FormSubmissionLogic.photoURLs(export), ["https://signed/a"])
    }

    // MARK: exportText

    func testExportTextIsAReadableReport() {
        let export = FormSubmissionExport(
            submissionId: "s1",
            refNo: "SRPR2627-1",
            formTitle: "Retailer Visit",
            templateId: "t1",
            activityName: nil,
            accountName: "Acme Steel",
            submitter: FormSubmitter(id: "u1", name: "Asha Rao", employeeId: "EMP-204"),
            submittedAt: "2026-11-02T10:15:30Z",
            outletName: "MG Road Store",
            address: "12 MG Road",
            answers: [
                FormExportAnswer(fieldId: "q2", label: "Stock level", type: "number", sortOrder: 2, value: .number(7), gps: nil, photos: nil),
                FormExportAnswer(fieldId: "q1", label: "Shelf clean?", type: "select", sortOrder: 1, value: .string("Yes"), gps: nil, photos: nil),
                FormExportAnswer(fieldId: "q3", label: "Shelf photo", type: "photo", sortOrder: 3, value: .null, gps: nil,
                                 photos: [SignedPhoto(url: "stored://x", signed: "https://signed/x")]),
            ],
            photos: [SignedPhoto(url: "stored://x", signed: "https://signed/x")],
            exportedAt: "2026-11-02T10:20:00Z"
        )
        let text = FormSubmissionLogic.exportText(export)

        XCTAssertTrue(text.hasPrefix("Retailer Visit"), text)
        XCTAssertTrue(text.contains("Form No: SRPR2627-1"), text)
        XCTAssertTrue(text.contains("Submitted: 02 Nov 2026"), text)
        XCTAssertTrue(text.contains("By: Asha Rao (EMP-204)"), text)
        XCTAssertTrue(text.contains("Outlet: MG Road Store"), text)
        XCTAssertTrue(text.contains("Account: Acme Steel"), text)
        // Answers emitted in sort order: Shelf clean? (1) before Stock level (2).
        let shelfIdx = text.range(of: "Shelf clean?")!.lowerBound
        let stockIdx = text.range(of: "Stock level")!.lowerBound
        XCTAssertLessThan(shelfIdx, stockIdx)
        XCTAssertTrue(text.contains("1. Shelf clean?: Yes"), text)
        XCTAssertTrue(text.contains("2. Stock level: 7"), text)
        XCTAssertTrue(text.contains("3. Shelf photo: [1 photo]"), text)
        XCTAssertTrue(text.contains("https://signed/x"), text)
    }

    // MARK: - Decoding the three backend shapes

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testDecodeListPage() throws {
        let json = """
        {
          "data": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "ref_no": "SRPR2627-1",
              "submitted_at": "2026-11-02T10:15:30Z",
              "template_id": "t1",
              "outlet_name": "MG Road Store",
              "address": null,
              "user_id": "u1",
              "builder_forms": { "title": "Retailer Visit" }
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "ref_no": null,
              "submitted_at": "2026-11-01T09:00:00Z",
              "template_id": "t2",
              "builder_forms": null
            }
          ],
          "pagination": { "page": 1, "limit": 20, "total": 2, "totalPages": 1 }
        }
        """
        let page = try decode(FormSubmissionPage.self, json)
        XCTAssertEqual(page.data.count, 2)
        XCTAssertEqual(page.data[0].refNo, "SRPR2627-1")
        XCTAssertEqual(page.data[0].formTitle, "Retailer Visit")
        XCTAssertEqual(page.data[0].outletName, "MG Road Store")
        XCTAssertNil(page.data[1].refNo)
        XCTAssertNil(page.data[1].formTitle)       // builder_forms null → nil, not a decode failure
        XCTAssertEqual(page.pagination?.total, 2)
    }

    func testDecodeDetailWithMixedAnswerColumnsAndSignedPhotos() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "ref_no": "SRPR2627-1",
          "submitted_at": "2026-11-02T10:15:30Z",
          "template_id": "t1",
          "outlet_name": "MG Road Store",
          "address": "12 MG Road",
          "latitude": 12.9,
          "longitude": 77.5,
          "org_id": "o1",
          "builder_forms": { "title": "Retailer Visit" },
          "form_responses": [
            {
              "id": "r1", "field_id": "q1",
              "value_text": "Yes", "value_number": null, "value_bool": null,
              "builder_questions": { "id": "q1", "label": "Shelf clean?", "qtype": "select", "q_order": 1 }
            },
            {
              "id": "r2", "field_id": "q2",
              "value_text": null, "value_number": 7, "value_bool": null,
              "builder_questions": { "id": "q2", "label": "Stock level", "qtype": "number", "q_order": 2 }
            },
            {
              "id": "r3", "field_id": "q3",
              "photo_url": "stored://x",
              "photo_urls": ["stored://x"],
              "photos": [ { "url": "stored://x", "signed": "https://signed/x" } ],
              "builder_questions": { "id": "q3", "label": "Shelf photo", "qtype": "photo", "q_order": 3 }
            }
          ],
          "photos": [ { "url": "stored://x", "signed": "https://signed/x" } ]
        }
        """
        let detail = try decode(FormSubmissionDetail.self, json)
        XCTAssertEqual(detail.formTitle, "Retailer Visit")
        XCTAssertEqual(detail.responses?.count, 3)
        let q1 = detail.responses![0]
        XCTAssertEqual(FormSubmissionLogic.displayValue(q1), "Yes")
        XCTAssertTrue(FormSubmissionLogic.isEditable(q1))
        let q2 = detail.responses![1]
        XCTAssertEqual(FormSubmissionLogic.displayValue(q2), "7")
        let q3 = detail.responses![2]
        XCTAssertFalse(FormSubmissionLogic.isEditable(q3))       // photo → read-only
        XCTAssertEqual(q3.photos?.first?.renderURL, "https://signed/x")
        XCTAssertEqual(FormSubmissionLogic.photoCount(answers: detail.responses, submissionPhotos: detail.photos), 1)
    }

    func testDecodeExportWithMixedValuesAndSign() throws {
        let json = """
        {
          "submission_id": "11111111-1111-1111-1111-111111111111",
          "ref_no": "SRPR2627-1",
          "form_title": "Retailer Visit",
          "template_id": "t1",
          "activity_name": null,
          "account_name": "Acme Steel",
          "submitter": { "id": "u1", "name": "Asha Rao", "employee_id": "EMP-204" },
          "submitted_at": "2026-11-02T10:15:30Z",
          "outlet_name": "MG Road Store",
          "address": "12 MG Road",
          "answers": [
            { "field_id": "q1", "label": "Shelf clean?", "type": "select", "sort_order": 1, "value": "Yes", "gps": null, "photos": [] },
            { "field_id": "q2", "label": "Stock level", "type": "number", "sort_order": 2, "value": 7, "gps": null, "photos": [] },
            { "field_id": "q4", "label": "Agreed?", "type": "checkbox", "sort_order": 4, "value": true, "gps": null, "photos": [] },
            { "field_id": "q3", "label": "Shelf photo", "type": "photo", "sort_order": 3, "value": null, "gps": null,
              "photos": [ { "url": "stored://x", "signed": "https://signed/x" } ] }
          ],
          "photos": [ { "url": "stored://x", "signed": "https://signed/x" } ],
          "exported_at": "2026-11-02T10:20:00Z",
          "signed_url_ttl_seconds": 604800
        }
        """
        let export = try decode(FormSubmissionExport.self, json)
        XCTAssertEqual(export.refNo, "SRPR2627-1")
        XCTAssertEqual(export.submitter?.employeeId, "EMP-204")
        XCTAssertEqual(export.answers?.count, 4)
        XCTAssertEqual(FormSubmissionLogic.answerText(export.answers?[2].value), "Yes")   // bool true → Yes
        let text = FormSubmissionLogic.exportText(export)
        XCTAssertTrue(text.contains("4. Agreed?: Yes"), text)
        XCTAssertTrue(text.contains("3. Shelf photo: [1 photo]"), text)
    }
}
