//
//  MarketingVisit.swift
//  Kinematic CRM
//
//  Mirrors the ad-hoc "Marketing Visit" wire shape from the backend
//  (/api/v1/crm/marketing-visits/*). A marketing visit is modelled on top of
//  a `crm_activities` row: a `type:'meeting'` activity carrying
//  `metadata.kind='marketing_visit'` plus a `metadata.visit` block with the
//  GPS Start → End coordinates / timestamps. We only decode the fields the
//  iOS flow needs; every other activity column is ignored by Codable.
//

import Foundation

/// One marketing-visit activity row. `status` is "planned" while the visit is
/// in progress and "completed" once ended.
struct MarketingVisit: Codable, Identifiable, Hashable {
    let id: String
    let subject: String?
    let leadId: String?
    let status: String?
    let dueAt: String?
    let completedAt: String?
    let outcome: String?
    let metadata: MarketingVisitMeta?

    enum CodingKeys: String, CodingKey {
        case id, subject, status, outcome, metadata
        case leadId = "lead_id"
        case dueAt = "due_at"
        case completedAt = "completed_at"
    }

    /// True while the visit is still open (rep hasn't tapped "End Visit").
    var isInProgress: Bool { (status ?? "").lowercased() == "planned" }

    /// Best-effort lead name parsed from the subject ("Marketing Visit — Name")
    /// for list cards when the full lead row hasn't been fetched yet.
    var leadNameFromSubject: String {
        guard let s = subject, !s.isEmpty else { return "Lead" }
        // The backend subject uses an em dash separator.
        if let r = s.range(of: "—") {
            let tail = s[r.upperBound...].trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { return tail }
        }
        return s
    }

    /// The nested visit detail, if present.
    var detail: MarketingVisitDetail? { metadata?.visit }
}

/// The `metadata` jsonb block on a marketing-visit activity.
struct MarketingVisitMeta: Codable, Hashable {
    let kind: String?
    let visit: MarketingVisitDetail?
}

/// The `metadata.visit` block — GPS Start → End coordinates + timestamps.
struct MarketingVisitDetail: Codable, Hashable {
    let phase: String?
    let startedAt: String?
    let startLat: Double?
    let startLng: Double?
    let endedAt: String?
    let endLat: Double?
    let endLng: Double?
    let purpose: String?
    let nextFollowupAt: String?

    enum CodingKeys: String, CodingKey {
        case phase, purpose
        case startedAt = "started_at"
        case startLat = "start_lat"
        case startLng = "start_lng"
        case endedAt = "ended_at"
        case endLat = "end_lat"
        case endLng = "end_lng"
        case nextFollowupAt = "next_followup_at"
    }
}

/// Response of the start / end endpoints: `{ visit, lead }`. `lead` can be
/// null on end (when the linked lead couldn't be re-read), so it's optional.
struct MarketingVisitResult: Codable {
    let visit: MarketingVisit
    let lead: Lead?
}

/// ISO-timestamp → short human string for the visit cards. Parses both
/// fractional-second (`…56.789Z`, what `Date().toISOString()` emits) and
/// plain internet-datetime strings, falling back to "" on anything it can't
/// read so a card never shows a raw timestamp.
enum MarketingVisitDate {
    private static let parserFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let parserPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, h:mm a"
        return f
    }()

    static func short(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        guard let date = parserFrac.date(from: iso) ?? parserPlain.date(from: iso) else { return "" }
        return display.string(from: date)
    }

    /// Date → RFC-3339 string the backend's `isoDate` validator accepts
    /// (`z.string().datetime({ offset: true })`). Produces e.g.
    /// "2026-10-02T12:34:56Z".
    static func iso(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
