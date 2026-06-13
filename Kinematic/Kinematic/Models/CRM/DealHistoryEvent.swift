import Foundation

/// One row from `/api/v1/crm/deals/:id/history`. Each event carries
/// its `event_type` plus whichever from/to fields are relevant — the
/// backend only populates stage columns on stage transitions and
/// amount columns on amount edits, so everything except `event_type`
/// is optional.
///
/// `id` is optional because the backend `/deals/:id/history` response
/// mixes rows from the `crm_deal_history` table (which carries a stable
/// uuid) with synthesized rollup rows (stage transitions derived from
/// `crm_activity`, create/update audit rows) that do not include an
/// `id`. Decoding the whole list used to fail with `keyNotFound("id")`
/// the moment one rollup row came back without it; this also surfaced
/// on the Lead detail screen because lead detail's auxiliary fan-out
/// pulls the converted deal's NBA + history in parallel.
///
/// `Identifiable.id` synthesizes a deterministic key from the event
/// shape so SwiftUI's ForEach still has a unique row identifier when
/// the JSON `id` is missing.
struct DealHistoryEvent: Codable, Identifiable, Hashable {
    let backendId: String?
    let eventType: String       // stage_changed | amount_changed | created | updated | won | lost | reopened | note
    let fromStage: String?
    let toStage: String?
    let fromAmount: Double?
    let toAmount: Double?
    let createdAt: String?
    /// Free-text annotation written by the backend for non-stage / non-amount
    /// edits (e.g. "Updated closed quantities: Tiscon 32mm: 0 → 5"). Optional
    /// — older rows / synthesized rollups don't carry it.
    let note: String?

    /// Stable identifier for SwiftUI lists. Falls back to a deterministic
    /// composite key (event_type + created_at + from/to fields) when the
    /// backend omits the row id on a synthesized history entry.
    var id: String {
        if let backendId, !backendId.isEmpty { return backendId }
        let ts = createdAt ?? ""
        let fs = fromStage ?? ""
        let toS = toStage ?? ""
        let fa = fromAmount.map { String($0) } ?? ""
        let ta = toAmount.map { String($0) } ?? ""
        return "\(eventType)|\(ts)|\(fs)→\(toS)|\(fa)→\(ta)|\(note ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case backendId  = "id"
        case eventType  = "event_type"
        case fromStage  = "from_stage"
        case toStage    = "to_stage"
        case fromAmount = "from_amount"
        case toAmount   = "to_amount"
        case createdAt  = "created_at"
        case note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.backendId  = try c.decodeIfPresent(String.self, forKey: .backendId)
        self.eventType  = try c.decodeIfPresent(String.self, forKey: .eventType) ?? "updated"
        self.fromStage  = try c.decodeIfPresent(String.self, forKey: .fromStage)
        self.toStage    = try c.decodeIfPresent(String.self, forKey: .toStage)
        self.fromAmount = try c.decodeIfPresent(Double.self, forKey: .fromAmount)
        self.toAmount   = try c.decodeIfPresent(Double.self, forKey: .toAmount)
        self.createdAt  = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.note       = try c.decodeIfPresent(String.self, forKey: .note)
    }
}
