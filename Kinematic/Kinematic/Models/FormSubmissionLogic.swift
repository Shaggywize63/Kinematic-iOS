//
//  FormSubmissionLogic.swift
//  Kinematic
//
//  Pure, unit-tested rules for a rep's own filled-form entries (see MyFormSubmissionsView). No SwiftUI, no
//  network: just how a stored answer becomes a readable string, which answers a rep may edit, and how one
//  submission is turned into the plain-text report the iOS share sheet sends. Never throws, never crashes.
//
//  Mirrors the backend's own display precedence (value_text → value_number → value_bool) so the app shows the
//  same text the server records in its edit history.
//

import Foundation

enum FormSubmissionLogic {

    /// Question types whose answer is a picture / file, never free text — so they are shown but NOT editable.
    /// Matches the backend's `IMAGE_QTYPES` set (forms.controller.ts) plus layout-only types.
    static let imageQTypes: Set<String> = ["photo", "image", "camera", "signature", "file", "card_scan", "planogram"]
    static let layoutQTypes: Set<String> = ["section", "heading", "divider", "info", "label"]

    /// A number the way the server prints it: a whole number has no ".0", everything else keeps its decimals.
    static func numberText(_ n: Double) -> String {
        guard n.isFinite else { return "" }
        if n == n.rounded() && abs(n) < 1e15 { return String(Int(n)) }
        return String(n)
    }

    /// The display string of a stored answer, in the backend's precedence: non-blank text wins, then a number,
    /// then a boolean ("Yes" / "No"); "" when the answer is empty.
    static func displayValue(valueText: String?, valueNumber: Double?, valueBool: Bool?) -> String {
        if let t = valueText?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let n = valueNumber { return numberText(n) }
        if let b = valueBool { return b ? "Yes" : "No" }
        return ""
    }

    /// Convenience over a decoded answer.
    static func displayValue(_ a: FormSubmissionAnswer) -> String {
        displayValue(valueText: a.valueText, valueNumber: a.valueNumber, valueBool: a.valueBool)
    }

    /// The display string of a single export value (a mixed scalar). Arrays join with commas; objects / null → "".
    static func answerText(_ v: AnyJSON?) -> String {
        switch v {
        case .some(.string(let s)): return s
        case .some(.number(let n)): return numberText(n)
        case .some(.bool(let b)): return b ? "Yes" : "No"
        case .some(.array(let a)):
            return a.map { answerText($0) }.filter { !$0.isEmpty }.joined(separator: ", ")
        case .some(.object), .some(.null), .none: return ""
        }
    }

    /// Whether a rep may edit this answer as text. Pictures / files and layout-only rows are read-only; everything
    /// else (text, number, email, phone, select, …) is a free-text edit per the PATCH contract. A nil / unknown
    /// type is treated as editable so a new text type is never accidentally locked.
    static func isEditable(qtype: String?) -> Bool {
        let q = (qtype ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        if imageQTypes.contains(q) { return false }
        if layoutQTypes.contains(q) { return false }
        return true
    }

    static func isEditable(_ a: FormSubmissionAnswer) -> Bool { isEditable(qtype: a.question?.qtype) }

    /// The best label for an answer row: the question's label, else its field id, else "Field".
    static func label(for a: FormSubmissionAnswer) -> String {
        let l = (a.question?.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !l.isEmpty { return l }
        let f = (a.fieldId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return f.isEmpty ? "Field" : f
    }

    /// The headline for a submission wherever it is named: "<ref> · <day>" with a form-title fallback.
    /// (The ref/date formatting itself lives in — and is tested in — `FormRefDisplay`.)
    static func headline(refNo: String?, submittedAt: String?, formTitle: String?) -> String {
        let t = FormRefDisplay.title(refNo: refNo, submittedAt: submittedAt)
        if !t.isEmpty { return t }
        let title = (formTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Form submission" : title
    }

    /// Count the photos across every answer plus the submission-level set (deduped by stored URL).
    static func photoCount(answers: [FormSubmissionAnswer]?, submissionPhotos: [SignedPhoto]?) -> Int {
        var urls = Set<String>()
        for p in submissionPhotos ?? [] { urls.insert(p.url) }
        for a in answers ?? [] { for p in a.photos ?? [] { urls.insert(p.url) } }
        return urls.count
    }

    /// The plain-text report the share sheet sends for ONE submission. Deterministic and order-stable (answers
    /// are emitted in `sort_order`, then by label) so it is unit-testable and reads the same every time.
    static func exportText(_ e: FormSubmissionExport) -> String {
        var lines: [String] = []

        let title = (e.formTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(title.isEmpty ? "Form submission" : title)

        if let ref = e.refNo?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty {
            lines.append("Form No: \(ref)")
        }
        let day = FormRefDisplay.dayText(e.submittedAt)
        if !day.isEmpty { lines.append("Submitted: \(day)") }

        if let who = submitterLine(e.submitter) { lines.append("By: \(who)") }
        if let outlet = e.outletName?.trimmingCharacters(in: .whitespacesAndNewlines), !outlet.isEmpty {
            lines.append("Outlet: \(outlet)")
        }
        if let account = e.accountName?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty {
            lines.append("Account: \(account)")
        }
        if let addr = e.address?.trimmingCharacters(in: .whitespacesAndNewlines), !addr.isEmpty {
            lines.append("Address: \(addr)")
        }

        let answers = sortedAnswers(e.answers ?? [])
        if !answers.isEmpty {
            lines.append("")
            lines.append("Answers")
            for (i, a) in answers.enumerated() {
                let label = (a.label ?? a.fieldId ?? "Field").trimmingCharacters(in: .whitespacesAndNewlines)
                let value = answerText(a.value)
                let photoCount = a.photos?.count ?? 0
                var row = "\(i + 1). \(label.isEmpty ? "Field" : label): "
                if value.isEmpty && photoCount > 0 {
                    row += "[\(photoCount) photo\(photoCount == 1 ? "" : "s")]"
                } else {
                    row += value.isEmpty ? "—" : value
                    if photoCount > 0 { row += "  [\(photoCount) photo\(photoCount == 1 ? "" : "s")]" }
                }
                lines.append(row)
            }
        }

        let urls = photoURLs(e)
        if !urls.isEmpty {
            lines.append("")
            lines.append("Photos (\(urls.count)):")
            for u in urls { lines.append(u) }
        }

        return lines.joined(separator: "\n")
    }

    /// "Asha Rao (EMP-204)", "Asha Rao", or nil when there is no name.
    static func submitterLine(_ s: FormSubmitter?) -> String? {
        guard let s = s else { return nil }
        let name = (s.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let emp = (s.employeeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return emp.isEmpty ? name : "\(name) (\(emp))"
    }

    /// Export answers in a stable order: by `sort_order` (missing sorts last), then by label, then field id.
    static func sortedAnswers(_ answers: [FormExportAnswer]) -> [FormExportAnswer] {
        answers.enumerated().sorted { lhs, rhs in
            let lo = lhs.element.sortOrder ?? Int.max
            let ro = rhs.element.sortOrder ?? Int.max
            if lo != ro { return lo < ro }
            let ll = (lhs.element.label ?? lhs.element.fieldId ?? "")
            let rl = (rhs.element.label ?? rhs.element.fieldId ?? "")
            if ll != rl { return ll < rl }
            return lhs.offset < rhs.offset   // stable: keep original order on a full tie
        }.map { $0.element }
    }

    /// Every signed photo link in the export, deduped by stored URL, submission-level first then per answer.
    static func photoURLs(_ e: FormSubmissionExport) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ p: SignedPhoto) {
            guard !seen.contains(p.url) else { return }
            seen.insert(p.url)
            out.append(p.renderURL)
        }
        for p in e.photos ?? [] { add(p) }
        for a in sortedAnswers(e.answers ?? []) { for p in a.photos ?? [] { add(p) } }
        return out
    }
}
