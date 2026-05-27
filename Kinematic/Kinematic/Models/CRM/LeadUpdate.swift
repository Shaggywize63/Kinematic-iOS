//
//  LeadUpdate.swift
//  Kinematic CRM
//
//  Mirrors a row of crm_lead_updates from the kinematic backend. Each
//  update is an append-only free-text note posted via
//  `POST /api/v1/crm/leads/:id/updates`, and feeds two things downstream:
//    1. the denormalised latest_update snapshot on crm_leads (rendered in
//       the leads list row preview),
//    2. the lead-scoring v2 engagement signals (updates_30d, BANT match,
//       recent_touch) computed in leadScoring.service.ts.
//

import Foundation

struct LeadUpdate: Codable, Identifiable, Hashable {
    let id: String
    let leadId: String?
    let authorId: String?
    let authorName: String?
    let body: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case leadId = "lead_id"
        case authorId = "author_id"
        case authorName = "author_name"
        case body
        case createdAt = "created_at"
    }
}
