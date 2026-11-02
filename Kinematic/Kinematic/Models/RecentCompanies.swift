//
//  RecentCompanies.swift
//  Kinematic
//
//  The companies a rep picked recently in the Customer / Company form question, offered first the next time the
//  picker opens. The rules (most-recent-first, one row per company, capped) are pure and unit-tested; the store only
//  adds on-device storage, kept PER USER so a phone handed to another rep (or another tenant's login) never shows the
//  previous person's companies. Only an explicit pick is recorded — a pre-filled company is not.
//  Mirrors the Android RecentCompanies.
//

import Foundation

struct RecentCompany: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
}

enum RecentCompanies {
    static let max = 8

    /// `list` with `company` moved/added to the front (a company already there is not repeated), cut to `limit`.
    static func pushed(_ list: [RecentCompany], _ company: RecentCompany, limit: Int = RecentCompanies.max) -> [RecentCompany] {
        let blank = company.id.trimmingCharacters(in: .whitespaces).isEmpty
            || company.name.trimmingCharacters(in: .whitespaces).isEmpty
        if blank { return Array(list.prefix(limit)) }
        return Array(([company] + list.filter { $0.id != company.id }).prefix(limit))
    }

    /// What is kept on the device.
    static func encode(_ list: [RecentCompany]) -> Data? { try? JSONEncoder().encode(list) }

    /// One stored row that may not be readable: it decodes to nil instead of failing the whole list.
    private struct Row: Decodable {
        let company: RecentCompany?
        init(from decoder: Decoder) throws { company = try? RecentCompany(from: decoder) }
    }

    /// The stored list; empty (never a crash) when nothing is stored or it cannot be read. Unusable rows are dropped.
    static func decode(_ data: Data?) -> [RecentCompany] {
        guard let data, let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return Array(rows.compactMap { $0.company }
            .filter { !$0.id.trimmingCharacters(in: .whitespaces).isEmpty
                   && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(max))
    }
}

struct RecentCompaniesStore {
    var defaults: UserDefaults = .standard

    private func key(_ userId: String) -> String { "recent_companies_u_\(userId)" }

    func load(userId: String) -> [RecentCompany] {
        userId.isEmpty ? [] : RecentCompanies.decode(defaults.data(forKey: key(userId)))
    }

    /// Records a pick and returns the updated list.
    @discardableResult
    func record(userId: String, _ company: RecentCompany) -> [RecentCompany] {
        if userId.isEmpty { return [] }
        let updated = RecentCompanies.pushed(load(userId: userId), company)
        if let data = RecentCompanies.encode(updated) { defaults.set(data, forKey: key(userId)) }
        return updated
    }
}
