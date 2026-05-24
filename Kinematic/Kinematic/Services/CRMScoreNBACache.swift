//
//  CRMScoreNBACache.swift
//  Kinematic CRM
//
//  Disk-persisted per-entity cache for AI-derived Lead Score and Next Best
//  Action payloads. Mirrors the CRMReadCache pattern (token-suffix user key,
//  background serial queue, per-user JSON files) so logged-in user A never
//  sees user B's stashed AI output after re-login.
//
//  Goal: stop computing Lead Score / NBA on every detail-screen open. The
//  detail viewmodels now read from this cache on appear and only hit the
//  recompute endpoint when the rep explicitly taps Refresh. Cuts hot-screen
//  API hits by ~one request per Lead and ~one per Deal detail visit.
//

import Foundation

@MainActor
final class CRMScoreNBACache {
    static let shared = CRMScoreNBACache()

    /// Decoded snapshot of a cached LeadScore plus the wall-clock time we
    /// fetched it. UI uses `fetchedAt` to render the "Last computed 2h ago"
    /// subtitle on the score card.
    struct CachedScore: Codable {
        let score: LeadScore
        let fetchedAt: Date
    }

    /// Decoded snapshot of a cached NextBestAction. We persist the entire
    /// payload (not just action+reason) so the card has access to confidence
    /// + suggested template fields when offline.
    struct CachedNBA: Codable {
        let action: NextBestAction
        let fetchedAt: Date
    }

    private let ioQueue = DispatchQueue(label: "com.kinematic.crmscorenbacache", qos: .utility)
    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private init() {}

    // ── File layout ──────────────────────────────────────────────────
    // crm_score_<leadId>_<userKey>.json
    // crm_nba_deal_<dealId>_<userKey>.json
    // crm_nba_lead_<leadId>_<userKey>.json
    private static func userKey() -> String { String(Session.sharedToken.suffix(24)) }

    private func scoreFile(leadId: String) -> URL {
        docs.appendingPathComponent("crm_score_\(leadId)_\(Self.userKey()).json")
    }

    private func nbaFile(dealId: String? = nil, leadId: String? = nil) -> URL {
        if let dealId {
            return docs.appendingPathComponent("crm_nba_deal_\(dealId)_\(Self.userKey()).json")
        }
        return docs.appendingPathComponent("crm_nba_lead_\(leadId ?? "")_\(Self.userKey()).json")
    }

    // ── Score ───────────────────────────────────────────────────────
    func saveScore(leadId: String, score: LeadScore, fetchedAt: Date = Date()) {
        let url = scoreFile(leadId: leadId)
        let snapshot = CachedScore(score: score, fetchedAt: fetchedAt)
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadScore(leadId: String) -> CachedScore? {
        let url = scoreFile(leadId: leadId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedScore.self, from: data)
    }

    // ── NBA ─────────────────────────────────────────────────────────
    func saveNBA(dealId: String? = nil, leadId: String? = nil, action: NextBestAction, fetchedAt: Date = Date()) {
        let url = nbaFile(dealId: dealId, leadId: leadId)
        let snapshot = CachedNBA(action: action, fetchedAt: fetchedAt)
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadNBA(dealId: String? = nil, leadId: String? = nil) -> CachedNBA? {
        let url = nbaFile(dealId: dealId, leadId: leadId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedNBA.self, from: data)
    }

    // ── Invalidation ────────────────────────────────────────────────
    /// Wipe every cached score + NBA file for every user. Hooked from logout
    /// alongside CRMReadCache.invalidateAll().
    func invalidateAll() {
        let fm = FileManager.default
        let docs = self.docs
        ioQueue.async {
            guard let contents = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else { return }
            for url in contents {
                let name = url.lastPathComponent
                if name.hasPrefix("crm_score_") || name.hasPrefix("crm_nba_") {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }
}
