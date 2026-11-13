//
//  FormSubmissionModels.swift
//  Kinematic
//
//  The shapes a field executive's OWN filled-form entries come back in, and the pure logic for showing and
//  exporting them. Backs "My Reports" (MyFormSubmissionsView): a rep lists the forms they have submitted — each
//  named by its backend reference (the "form number", e.g. SRPR2627-1) — opens one to read the answers and the
//  photos, edits their own text / outlet, and exports one to share or save.
//
//  Backend contract (base `/api/v1/forms`, shared with the web dashboard + Android):
//   • GET  /forms/submissions?page=&limit=   → own submissions, newest first, paginated.
//   • GET  /forms/submissions/:id            → one submission + form_responses[] (+ signed photos).
//   • PATCH /forms/submissions/:id           → edit own { responses?, outlet_name?, address? }.
//   • GET  /forms/submissions/:id/export     → a self-contained export (7-day signed photo URLs).
//
//  Everything here decodes LENIENTLY: a column the server omits, or a join that degraded to null, must never
//  fail the whole response. `FormSubmissionLogic` is pure (no SwiftUI, no network) so it is unit-tested.
//

import Foundation

// MARK: - Shared leaf types

/// A stored private-bucket photo plus its renderable signed link (`signed` is null when signing missed).
struct SignedPhoto: Codable, Hashable, Identifiable {
    let url: String
    let signed: String?

    /// The link to actually render: the signed one when present, else the raw stored URL.
    var renderURL: String { (signed?.isEmpty == false) ? signed! : url }
    var id: String { url }
}

/// The `{ page, limit, total, totalPages }` envelope the list endpoint wraps its rows in.
struct FormSubmissionPagination: Codable, Hashable {
    let page: Int?
    let limit: Int?
    let total: Int?
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case page, limit, total
        case totalPages = "totalPages"
    }
}

// MARK: - List

/// One row of the rep's own submissions list. The form's title arrives nested under `builder_forms(title)`.
struct FormSubmissionSummary: Codable, Identifiable, Hashable {
    let id: String
    /// The "form number" — prefix + financial-year code + running number, e.g. "SRPR2627-1".
    let refNo: String?
    let submittedAt: String?
    let templateId: String?
    let outletName: String?
    let address: String?
    private let builderForms: TitleOnly?

    /// The form's title (from the joined `builder_forms`), or nil.
    var formTitle: String? { builderForms?.title }

    struct TitleOnly: Codable, Hashable { let title: String? }

    enum CodingKeys: String, CodingKey {
        case id, address
        case refNo = "ref_no"
        case submittedAt = "submitted_at"
        case templateId = "template_id"
        case outletName = "outlet_name"
        case builderForms = "builder_forms"
    }
}

/// `{ data: [...], pagination: {...} }` — the paginated body the list endpoint returns under `data`.
struct FormSubmissionPage: Codable {
    let data: [FormSubmissionSummary]
    let pagination: FormSubmissionPagination?
}

// MARK: - Detail

/// A question's definition as joined onto a stored answer (`builder_questions`).
struct FormQuestionMeta: Codable, Hashable {
    let id: String?
    let label: String?
    let qtype: String?
    let qOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id, label, qtype
        case qOrder = "q_order"
    }
}

/// One stored answer. The value is split across three columns on the row (text / number / bool); the display
/// string is resolved by `FormSubmissionLogic.displayValue`. Photos arrive pre-signed.
struct FormSubmissionAnswer: Codable, Hashable, Identifiable {
    let id: String?
    let fieldId: String?
    let valueText: String?
    let valueNumber: Double?
    let valueBool: Bool?
    let gps: String?
    let photos: [SignedPhoto]?
    let question: FormQuestionMeta?

    var identity: String { id ?? fieldId ?? UUID().uuidString }
    var identityForList: String { fieldId ?? id ?? "" }

    enum CodingKeys: String, CodingKey {
        case id, gps, photos
        case fieldId = "field_id"
        case valueText = "value_text"
        case valueNumber = "value_number"
        case valueBool = "value_bool"
        case question = "builder_questions"
    }
}

/// A full submission: the row, the resolved form title, every answer, and the submission-level signed photos.
struct FormSubmissionDetail: Codable, Identifiable {
    let id: String
    let refNo: String?
    let submittedAt: String?
    let templateId: String?
    let outletName: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let checkInAt: String?
    let checkOutAt: String?
    private let builderForms: FormSubmissionSummary.TitleOnly?
    let responses: [FormSubmissionAnswer]?
    let photos: [SignedPhoto]?

    var formTitle: String? { builderForms?.title }

    enum CodingKeys: String, CodingKey {
        case id, address, latitude, longitude, photos
        case refNo = "ref_no"
        case submittedAt = "submitted_at"
        case templateId = "template_id"
        case outletName = "outlet_name"
        case checkInAt = "check_in_at"
        case checkOutAt = "check_out_at"
        case builderForms = "builder_forms"
        case responses = "form_responses"
    }
}

// MARK: - Export

/// Who filled a form, as the export reports it.
struct FormSubmitter: Codable, Hashable {
    let id: String?
    let name: String?
    let employeeId: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case employeeId = "employee_id"
    }
}

/// One answer in the structured export: label + type + the single mixed value + any signed photos.
struct FormExportAnswer: Codable, Hashable, Identifiable {
    let fieldId: String?
    let label: String?
    let type: String?
    let sortOrder: Int?
    /// Mixed scalar (string / number / bool / null), decoded tolerantly.
    let value: AnyJSON?
    let gps: String?
    let photos: [SignedPhoto]?

    var id: String { fieldId ?? label ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case label, type, value, gps, photos
        case fieldId = "field_id"
        case sortOrder = "sort_order"
    }
}

/// The self-contained export payload for one submission (7-day signed photo URLs).
struct FormSubmissionExport: Codable, Identifiable {
    let submissionId: String?
    let refNo: String?
    let formTitle: String?
    let templateId: String?
    let activityName: String?
    let accountName: String?
    let submitter: FormSubmitter?
    let submittedAt: String?
    let outletName: String?
    let address: String?
    let answers: [FormExportAnswer]?
    let photos: [SignedPhoto]?
    let exportedAt: String?

    var id: String { submissionId ?? refNo ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case submitter, answers, photos
        case submissionId = "submission_id"
        case refNo = "ref_no"
        case formTitle = "form_title"
        case templateId = "template_id"
        case activityName = "activity_name"
        case accountName = "account_name"
        case submittedAt = "submitted_at"
        case outletName = "outlet_name"
        case address
        case exportedAt = "exported_at"
    }
}

// MARK: - Edit request (PATCH)

/// One answer in an edit — only the fields the rep may change (`field_id` + `value`).
struct FormSubmissionEditAnswer: Encodable {
    let fieldId: String
    let value: String?

    enum CodingKeys: String, CodingKey {
        case value
        case fieldId = "field_id"
    }
}

/// The PATCH body: any of the three editable parts. Nils are not encoded, so an untouched part is left alone.
struct FormSubmissionEditRequest: Encodable {
    var responses: [FormSubmissionEditAnswer]? = nil
    var outletName: String? = nil
    var address: String? = nil

    enum CodingKeys: String, CodingKey {
        case responses, address
        case outletName = "outlet_name"
    }

    /// Nothing to send: no answers changed and neither scalar touched.
    var isEmpty: Bool {
        (responses?.isEmpty ?? true) && outletName == nil && address == nil
    }
}
