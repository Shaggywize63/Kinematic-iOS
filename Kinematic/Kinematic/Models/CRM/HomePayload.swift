//
//  HomePayload.swift
//  Kinematic CRM
//
//  Mirrors /api/v1/crm/home — the daily-mission aggregator that
//  composes today's target + near-to-close leads + top-3 next actions
//  (with rules-based reasoning) + today's activity stats + a
//  productivity playbook into a single payload. HomeView reads this
//  top-to-bottom; the backend pushes a refresh on every Home tab focus.
//

import Foundation

struct HomePayload: Codable, Hashable {
    let todayTarget: HomeTarget?
    let nearToClose: [HomeNearLead]
    let nextActions: [HomeNextAction]
    let todayActivity: HomeActivityStats?
    let productivityTips: [String]

    enum CodingKeys: String, CodingKey {
        case todayTarget = "today_target"
        case nearToClose = "near_to_close"
        case nextActions = "next_actions"
        case todayActivity = "today_activity"
        case productivityTips = "productivity_tips"
    }
}

struct HomeTarget: Codable, Hashable {
    let hasTarget: Bool
    let achieved: Int
    let target: Int
    let progressPct: Int
    let remaining: Int
    let headline: String?

    enum CodingKeys: String, CodingKey {
        case hasTarget = "has_target"
        case achieved, target, remaining, headline
        case progressPct = "progress_pct"
    }
}

struct HomeNearLead: Codable, Hashable, Identifiable {
    let id: String
    let name: String?
    let score: Int?
    let scoreGrade: String?
    let lifecycleStage: String?
    let status: String?
    let lastActivityAt: String?
    let daysSinceTouch: Int?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case id, name, score, status, reason
        case scoreGrade = "score_grade"
        case lifecycleStage = "lifecycle_stage"
        case lastActivityAt = "last_activity_at"
        case daysSinceTouch = "days_since_touch"
    }
}

struct HomeNextAction: Codable, Hashable, Identifiable {
    let leadId: String
    let leadName: String?
    let action: String?
    let label: String?
    let reason: String?
    let urgency: String?
    let deeplinkPath: String?
    let score: Int?
    let scoreGrade: String?

    /// Identifiable conformance — leadId is unique enough across the
    /// top-3 cards the Home view renders.
    var id: String { leadId }

    enum CodingKeys: String, CodingKey {
        case leadId = "lead_id"
        case leadName = "lead_name"
        case action, label, reason, urgency, score
        case deeplinkPath = "deeplink_path"
        case scoreGrade = "score_grade"
    }
}

struct HomeActivityStats: Codable, Hashable {
    let total: Int
    let byType: [String: Int]
    let lastActivityAt: String?

    enum CodingKeys: String, CodingKey {
        case total
        case byType = "by_type"
        case lastActivityAt = "last_activity_at"
    }
}
