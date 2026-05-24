//
//  CRMReadCache.swift
//  Kinematic CRM
//
//  Disk-persisted read cache for CRM list endpoints. Mirrors the OutletCache
//  pattern but adds JSON-on-disk persistence so the UI survives offline
//  cold-launches. Each entity gets its own file per user (last 24 chars of
//  the access token) to prevent cross-user leakage on re-login.
//
//  Usage:
//    let rows = CRMReadCache.shared.load(.leads, as: [Lead].self)
//    CRMReadCache.shared.save(.leads, rows: leads)
//    let lastFetch = CRMReadCache.shared.lastFetchedAt(.leads)
//
//  Each save() is fire-and-forget — writes are funneled onto a background
//  serial queue so the calling actor never blocks on disk I/O. Reads are
//  synchronous (they're tiny — every list endpoint returns at most a few
//  hundred rows and the JSON file caps out well under 100 KB).
//

import Foundation
import Combine

@MainActor
final class CRMReadCache: ObservableObject {
    static let shared = CRMReadCache()

    /// One slot per cacheable list endpoint. The raw value becomes the file
    /// name suffix so adding a new slot never collides with an existing one.
    enum Entity: String, CaseIterable {
        case leads
        case contacts
        case accounts
        case deals
        case activities
    }

    private let ioQueue = DispatchQueue(label: "com.kinematic.crmreadcache", qos: .utility)
    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Per-entity in-memory record of the last successful fetch time. Used
    /// by the UI to render an "Offline · last synced X ago" sub-header.
    @Published private(set) var lastFetchedAt: [Entity: Date] = [:]

    private init() { hydrateTimestamps() }

    // ── File layout ──────────────────────────────────────────────────
    private func file(for entity: Entity, userKey: String) -> URL {
        // Filename: crm_<entity>_<userKey>.json — userKey isolation prevents
        // logged-in user A from seeing logged-in user B's cached leads.
        docs.appendingPathComponent("crm_\(entity.rawValue)_\(userKey).json")
    }

    private func tsFile(for entity: Entity, userKey: String) -> URL {
        docs.appendingPathComponent("crm_\(entity.rawValue)_\(userKey)_ts.json")
    }

    static func userKey() -> String { String(Session.sharedToken.suffix(24)) }

    // ── Save ────────────────────────────────────────────────────────
    /// Persist `rows` for `entity` keyed to the current user. Caller passes
    /// the typed array (e.g. `[Lead]`) — Codable handles the rest.
    func save<T: Encodable>(_ entity: Entity, rows: T) {
        let key = Self.userKey()
        let url = file(for: entity, userKey: key)
        let tsUrl = tsFile(for: entity, userKey: key)
        let now = Date()
        lastFetchedAt[entity] = now
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(rows) else { return }
            try? data.write(to: url, options: .atomic)
            if let tsData = try? JSONEncoder().encode(now) {
                try? tsData.write(to: tsUrl, options: .atomic)
            }
        }
    }

    // ── Load ────────────────────────────────────────────────────────
    /// Returns the cached rows for `entity` scoped to the current user, or
    /// nil if no cache exists yet (cold install / fresh login).
    func load<T: Decodable>(_ entity: Entity, as type: T.Type) -> T? {
        let url = file(for: entity, userKey: Self.userKey())
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Most recent successful fetch time for `entity` (current user). Reads
    /// the on-disk timestamp the first time it's asked, then keeps a hot
    /// copy in `lastFetchedAt`.
    func lastFetched(_ entity: Entity) -> Date? {
        if let cached = lastFetchedAt[entity] { return cached }
        let url = tsFile(for: entity, userKey: Self.userKey())
        guard let data = try? Data(contentsOf: url),
              let date = try? JSONDecoder().decode(Date.self, from: data) else { return nil }
        lastFetchedAt[entity] = date
        return date
    }

    /// Wipe every CRM cache for every user. Hook this from logout / org
    /// switch so the next session starts from a clean slate.
    func invalidateAll() {
        lastFetchedAt.removeAll()
        let fm = FileManager.default
        let docs = self.docs
        ioQueue.async {
            guard let contents = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else { return }
            for url in contents where url.lastPathComponent.hasPrefix("crm_") {
                try? fm.removeItem(at: url)
            }
        }
    }

    // ── Internal ────────────────────────────────────────────────────
    private func hydrateTimestamps() {
        // Pre-populate the @Published map for the current user so the UI's
        // "last synced" labels render on first paint without a disk hop.
        let key = Self.userKey()
        for e in Entity.allCases {
            let url = tsFile(for: e, userKey: key)
            if let data = try? Data(contentsOf: url),
               let date = try? JSONDecoder().decode(Date.self, from: data) {
                lastFetchedAt[e] = date
            }
        }
    }
}
