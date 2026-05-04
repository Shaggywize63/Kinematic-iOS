//
//  CRMService+Phase2.swift
//  Kinematic CRM
//
//  Extends CRMService with the Phase-2 endpoints: states/cities (location
//  management), products + deal line-items. Kept in a separate file to
//  avoid touching the original service surface.
//

import Foundation

extension CRMService {
    // MARK: States + Cities
    func listStates() async throws -> [CrmState] {
        try await getList("/api/v1/crm/states")
    }
    func citiesForState(_ stateId: String) async throws -> [CrmCity] {
        try await getList("/api/v1/crm/states/\(stateId)/cities")
    }
    func listCities(stateId: String? = nil) async throws -> [CrmCity] {
        var q: [String: String] = [:]
        if let stateId { q["state_id"] = stateId }
        return try await getList("/api/v1/crm/cities", query: q)
    }

    // MARK: Products
    func listProducts(search: String? = nil, categoryId: String? = nil) async throws -> [Product] {
        var q: [String: String] = [:]
        if let search { q["q"] = search }
        if let categoryId { q["category_id"] = categoryId }
        return try await getList("/api/v1/crm/products", query: q)
    }
    func getProduct(id: String) async throws -> Product { try await getOne("/api/v1/crm/products/\(id)") }

    // MARK: Deal line-items
    func dealLineItems(dealId: String) async throws -> [DealLineItem] {
        try await getList("/api/v1/crm/deals/\(dealId)/line-items")
    }
}

// MARK: - Generic helpers used only here (private to file)
private extension CRMService {
    func getList<T: Codable>(_ path: String, query: [String: String] = [:]) async throws -> [T] {
        // Use the raw URLSession to avoid coupling to private members.
        let url = try Self.buildURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        Self.applyHeaders(to: &req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.validate(resp)
        return try Self.decodeListEnvelope(T.self, from: data)
    }

    func getOne<T: Codable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let url = try Self.buildURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        Self.applyHeaders(to: &req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.validate(resp)
        return try Self.decodeEnvelope(T.self, from: data)
    }
}

// Static helpers so we don't poke at the file-scoped helpers in CRMService.swift.
private extension CRMService {
    static var baseHostURL: URL { URL(string: "https://kinematic-production.up.railway.app")! }

    static func buildURL(path: String, query: [String: String]) throws -> URL {
        var components = URLComponents(url: baseHostURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw CRMServiceError.server("Bad URL") }
        return url
    }

    static func applyHeaders(to req: inout URLRequest) {
        let token = Session.sharedToken.isEmpty
            ? (UserDefaults.standard.string(forKey: "auth_token") ?? "")
            : Session.sharedToken
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw CRMServiceError.badResponse(0) }
        if !(200..<300).contains(http.statusCode) {
            throw CRMServiceError.badResponse(http.statusCode)
        }
    }

    static func decodeListEnvelope<T: Codable>(_ type: T.Type, from data: Data) throws -> [T] {
        let decoder = JSONDecoder()
        if let env = try? decoder.decode(APIEnvelope<[T]>.self, from: data), let p = env.data {
            return p
        }
        if let raw = try? decoder.decode([T].self, from: data) { return raw }
        throw CRMServiceError.decodeFailed("Expected list of \(T.self)")
    }

    static func decodeEnvelope<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        if let env = try? decoder.decode(APIEnvelope<T>.self, from: data), let p = env.data {
            return p
        }
        if let raw = try? decoder.decode(T.self, from: data) { return raw }
        throw CRMServiceError.decodeFailed("Expected \(T.self)")
    }
}
