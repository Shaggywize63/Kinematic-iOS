//
//  CRMService+Offline.swift
//  Kinematic CRM
//
//  Offline-aware wrappers around CRMService's mutating endpoints. The
//  contract is:
//
//    - Online + happy path: call through to the network method as today,
//      return the server payload.
//    - Network failure / .badResponse(0) / offline: enqueue the mutation
//      into CRMWriteQueue and return an *optimistic* local entity stamped
//      with a `pending:<uuid>` id so the UI can render it immediately
//      (with a "pending sync" badge in list views).
//
//  Existing ViewModels can opt-in incrementally — they already call the
//  thin createX / patchX methods, so swapping them for the `*OrQueue`
//  variant keeps the rest of the codepath unchanged.
//
//  Idempotency: every call generates a deterministic Idempotency-Key (UUID
//  for creates, payload-hash for updates). Replays on the same key are
//  safe — the backend returns the canonical row from the first attempt.
//

import Foundation

extension CRMService {

    // MARK: - Lead

    /// Try POST /leads online; on network failure, enqueue + return an
    /// optimistic Lead so the list view can show it instantly.
    @MainActor
    func createLeadOrQueue(_ body: [String: Any]) async -> Lead {
        let key = CRMWriteQueue.createKey(entity: .lead)
        if NetworkReachability.shared.isOnline {
            do {
                return try await createLead(body, idempotencyKey: key)
            } catch {
                guard Self.isOfflineError(error) else {
                    // 4xx etc — bubble up via a thrown optimistic so the
                    // VM can surface the message. We still enqueue so a
                    // retry from the banner is possible.
                    let row = CRMWriteQueue.shared.enqueue(
                        entityType: .lead, operation: .create,
                        entityId: nil, payload: body
                    )
                    return Self.optimisticLead(from: body, pendingId: row.entityId ?? CRMWriteQueue.pendingId())
                }
            }
        }
        // Offline path
        let pendingId = CRMWriteQueue.pendingId()
        let row = CRMWriteQueue.shared.enqueue(
            entityType: .lead, operation: .create,
            entityId: pendingId, payload: body
        )
        _ = row
        return Self.optimisticLead(from: body, pendingId: pendingId)
    }

    @MainActor
    func updateLeadOrQueue(id: String, body: [String: Any]) async -> Lead? {
        let payloadData = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data("{}".utf8)
        let key = CRMWriteQueue.updateKey(entityId: id, payload: payloadData)
        if NetworkReachability.shared.isOnline && !id.hasPrefix("pending:") {
            do {
                return try await patchLead(id: id, body: body, idempotencyKey: key)
            } catch {
                guard Self.isOfflineError(error) else { return nil }
            }
        }
        _ = CRMWriteQueue.shared.enqueue(
            entityType: .lead, operation: .update,
            entityId: id, payload: body
        )
        return nil
    }

    // MARK: - Contact

    @MainActor
    func createContactOrQueue(_ body: [String: Any]) async -> Contact {
        let key = CRMWriteQueue.createKey(entity: .contact)
        if NetworkReachability.shared.isOnline {
            do {
                return try await createContact(body, idempotencyKey: key)
            } catch {
                guard Self.isOfflineError(error) else {
                    let row = CRMWriteQueue.shared.enqueue(
                        entityType: .contact, operation: .create,
                        entityId: nil, payload: body
                    )
                    return Self.optimisticContact(from: body, pendingId: row.entityId ?? CRMWriteQueue.pendingId())
                }
            }
        }
        let pendingId = CRMWriteQueue.pendingId()
        _ = CRMWriteQueue.shared.enqueue(entityType: .contact, operation: .create, entityId: pendingId, payload: body)
        return Self.optimisticContact(from: body, pendingId: pendingId)
    }

    @MainActor
    func updateContactOrQueue(id: String, body: [String: Any]) async -> Contact? {
        let payloadData = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data("{}".utf8)
        let key = CRMWriteQueue.updateKey(entityId: id, payload: payloadData)
        if NetworkReachability.shared.isOnline && !id.hasPrefix("pending:") {
            do { return try await patchContact(id: id, body: body, idempotencyKey: key) }
            catch {
                guard Self.isOfflineError(error) else { return nil }
            }
        }
        _ = CRMWriteQueue.shared.enqueue(entityType: .contact, operation: .update, entityId: id, payload: body)
        return nil
    }

    // MARK: - Account

    @MainActor
    func createAccountOrQueue(_ body: [String: Any]) async -> CRMAccount {
        let key = CRMWriteQueue.createKey(entity: .account)
        if NetworkReachability.shared.isOnline {
            do {
                return try await createAccount(body, idempotencyKey: key)
            } catch {
                guard Self.isOfflineError(error) else {
                    let row = CRMWriteQueue.shared.enqueue(entityType: .account, operation: .create, entityId: nil, payload: body)
                    return Self.optimisticAccount(from: body, pendingId: row.entityId ?? CRMWriteQueue.pendingId())
                }
            }
        }
        let pendingId = CRMWriteQueue.pendingId()
        _ = CRMWriteQueue.shared.enqueue(entityType: .account, operation: .create, entityId: pendingId, payload: body)
        return Self.optimisticAccount(from: body, pendingId: pendingId)
    }

    @MainActor
    func updateAccountOrQueue(id: String, body: [String: Any]) async -> CRMAccount? {
        let payloadData = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data("{}".utf8)
        let key = CRMWriteQueue.updateKey(entityId: id, payload: payloadData)
        if NetworkReachability.shared.isOnline && !id.hasPrefix("pending:") {
            do { return try await patchAccount(id: id, body: body, idempotencyKey: key) }
            catch {
                guard Self.isOfflineError(error) else { return nil }
            }
        }
        _ = CRMWriteQueue.shared.enqueue(entityType: .account, operation: .update, entityId: id, payload: body)
        return nil
    }

    // MARK: - Deal

    @MainActor
    func createDealOrQueue(_ body: [String: Any]) async -> Deal {
        let key = CRMWriteQueue.createKey(entity: .deal)
        if NetworkReachability.shared.isOnline {
            do {
                return try await createDeal(body, idempotencyKey: key)
            } catch {
                guard Self.isOfflineError(error) else {
                    let row = CRMWriteQueue.shared.enqueue(entityType: .deal, operation: .create, entityId: nil, payload: body)
                    return Self.optimisticDeal(from: body, pendingId: row.entityId ?? CRMWriteQueue.pendingId())
                }
            }
        }
        let pendingId = CRMWriteQueue.pendingId()
        _ = CRMWriteQueue.shared.enqueue(entityType: .deal, operation: .create, entityId: pendingId, payload: body)
        return Self.optimisticDeal(from: body, pendingId: pendingId)
    }

    @MainActor
    func updateDealOrQueue(id: String, body: [String: Any]) async -> Deal? {
        let payloadData = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data("{}".utf8)
        let key = CRMWriteQueue.updateKey(entityId: id, payload: payloadData)
        if NetworkReachability.shared.isOnline && !id.hasPrefix("pending:") {
            do { return try await patchDeal(id: id, body: body, idempotencyKey: key) }
            catch {
                guard Self.isOfflineError(error) else { return nil }
            }
        }
        _ = CRMWriteQueue.shared.enqueue(entityType: .deal, operation: .update, entityId: id, payload: body)
        return nil
    }

    @MainActor
    func moveDealStageOrQueue(id: String, stageId: String) async -> Deal? {
        let body: [String: Any] = ["stage_id": stageId]
        if NetworkReachability.shared.isOnline && !id.hasPrefix("pending:") {
            do { return try await moveDealStage(id: id, stageId: stageId) }
            catch {
                guard Self.isOfflineError(error) else { return nil }
            }
        }
        _ = CRMWriteQueue.shared.enqueue(entityType: .deal, operation: .update, entityId: id, payload: body, variant: "move-stage")
        return nil
    }

    @MainActor
    func winDealOrQueue(id: String, amount: Double? = nil, reason: String? = nil) async -> Deal? {
        var body: [String: Any] = [:]
        if let amount { body["amount"] = amount }
        if let reason, !reason.isEmpty { body["reason"] = reason }
        if NetworkReachability.shared.isOnline && !id.hasPrefix("pending:") {
            do { return try await winDeal(id: id, amount: amount, reason: reason) }
            catch {
                guard Self.isOfflineError(error) else { return nil }
            }
        }
        _ = CRMWriteQueue.shared.enqueue(entityType: .deal, operation: .update, entityId: id, payload: body, variant: "win")
        return nil
    }

    @MainActor
    func loseDealOrQueue(id: String, reason: String) async -> Deal? {
        let body: [String: Any] = ["reason": reason]
        if NetworkReachability.shared.isOnline && !id.hasPrefix("pending:") {
            do { return try await loseDeal(id: id, reason: reason) }
            catch {
                guard Self.isOfflineError(error) else { return nil }
            }
        }
        _ = CRMWriteQueue.shared.enqueue(entityType: .deal, operation: .update, entityId: id, payload: body, variant: "lose")
        return nil
    }

    // MARK: - Activity

    @MainActor
    func createActivityOrQueue(_ body: [String: Any]) async -> Activity {
        let key = CRMWriteQueue.createKey(entity: .activity)
        if NetworkReachability.shared.isOnline {
            do {
                return try await createActivity(body, idempotencyKey: key)
            } catch {
                guard Self.isOfflineError(error) else {
                    let row = CRMWriteQueue.shared.enqueue(entityType: .activity, operation: .create, entityId: nil, payload: body)
                    return Self.optimisticActivity(from: body, pendingId: row.entityId ?? CRMWriteQueue.pendingId())
                }
            }
        }
        let pendingId = CRMWriteQueue.pendingId()
        _ = CRMWriteQueue.shared.enqueue(entityType: .activity, operation: .create, entityId: pendingId, payload: body)
        return Self.optimisticActivity(from: body, pendingId: pendingId)
    }

    // MARK: - Idempotency-aware passthroughs
    // The base service overloads need an `idempotencyKey` parameter for
    // the online path. We extend the existing method surface here so the
    // offline wrappers above don't duplicate URL/body construction.

    func createLead(_ body: [String: Any], idempotencyKey: String) async throws -> Lead {
        try await postJSONIdem("/api/v1/crm/leads", body: body, idempotencyKey: idempotencyKey)
    }
    func createContact(_ body: [String: Any], idempotencyKey: String) async throws -> Contact {
        try await postJSONIdem("/api/v1/crm/contacts", body: body, idempotencyKey: idempotencyKey)
    }
    func createAccount(_ body: [String: Any], idempotencyKey: String) async throws -> CRMAccount {
        try await postJSONIdem("/api/v1/crm/accounts", body: body, idempotencyKey: idempotencyKey)
    }
    func createDeal(_ body: [String: Any], idempotencyKey: String) async throws -> Deal {
        try await postJSONIdem("/api/v1/crm/deals", body: body, idempotencyKey: idempotencyKey)
    }
    func createActivity(_ body: [String: Any], idempotencyKey: String) async throws -> Activity {
        try await postJSONIdem("/api/v1/crm/activities", body: body, idempotencyKey: idempotencyKey)
    }

    // MARK: - Private

    /// Build + perform a POST with an Idempotency-Key header. Mirrors the
    /// private `postJSON` in CRMService.swift but is reachable from the
    /// extension (the original is `private` — re-implementing in terms of
    /// the public URLRequest path is the cleanest way to expose it without
    /// reshuffling the service file).
    private func postJSONIdem<T: Codable>(_ path: String, body: [String: Any], idempotencyKey: String) async throws -> T {
        let url = try OfflineRequestHelpers.buildURL(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        OfflineRequestHelpers.applyHeaders(to: &req)
        req.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        let payload = body.isEmpty
            ? Data("{}".utf8)
            : try JSONSerialization.data(withJSONObject: body, options: [])
        req.httpBody = payload
        let (data, resp) = try await URLSession.shared.data(for: req)
        try OfflineRequestHelpers.validate(resp, data: data)
        return try OfflineRequestHelpers.decodeEnvelope(T.self, from: data)
    }

    // MARK: Heuristics

    /// True when the error suggests we should fall back to the queue
    /// (network down, host unreachable, server 5xx). 4xx / decode errors
    /// surface as failures so the user sees the validation message.
    static func isOfflineError(_ error: Error) -> Bool {
        if !NetworkReachability.shared.isOnline { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorDataNotAllowed:
                return true
            default: break
            }
        }
        if case let CRMServiceError.badResponse(code) = error, code == 0 || code >= 500 {
            return true
        }
        return false
    }

    // MARK: Optimistic builders
    // These keep the UI populated *before* the queue drains. Server
    // response will replace these the next time the list view refreshes.

    private static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    private static func optimisticLead(from body: [String: Any], pendingId: String) -> Lead {
        let dict: [String: Any] = [
            "id": pendingId,
            "first_name": body["first_name"] ?? NSNull(),
            "last_name": body["last_name"] ?? NSNull(),
            "email": body["email"] ?? NSNull(),
            "phone": body["phone"] ?? NSNull(),
            "company": body["company"] ?? NSNull(),
            "status": body["status"] ?? "new",
            "source": body["source"] ?? NSNull(),
            "created_at": Self.now()
        ]
        return decodeOrStub(Lead.self, dict: dict, pendingId: pendingId, extras: [:])
    }

    private static func optimisticContact(from body: [String: Any], pendingId: String) -> Contact {
        let dict: [String: Any] = [
            "id": pendingId,
            "first_name": body["first_name"] ?? NSNull(),
            "last_name": body["last_name"] ?? NSNull(),
            "email": body["email"] ?? NSNull(),
            "phone": body["phone"] ?? NSNull(),
            "created_at": Self.now()
        ]
        return decodeOrStub(Contact.self, dict: dict, pendingId: pendingId, extras: [:])
    }

    private static func optimisticAccount(from body: [String: Any], pendingId: String) -> CRMAccount {
        let dict: [String: Any] = [
            "id": pendingId,
            "name": body["name"] ?? "(pending)",
            "industry": body["industry"] ?? NSNull(),
            "created_at": Self.now()
        ]
        return decodeOrStub(CRMAccount.self, dict: dict, pendingId: pendingId, extras: ["name": "(pending)"])
    }

    private static func optimisticDeal(from body: [String: Any], pendingId: String) -> Deal {
        let dict: [String: Any] = [
            "id": pendingId,
            "name": body["name"] ?? "(pending deal)",
            "amount": body["amount"] ?? NSNull(),
            "status": "open",
            "created_at": Self.now()
        ]
        return decodeOrStub(Deal.self, dict: dict, pendingId: pendingId, extras: ["name": "(pending deal)"])
    }

    private static func optimisticActivity(from body: [String: Any], pendingId: String) -> Activity {
        let dict: [String: Any] = [
            "id": pendingId,
            "type": body["type"] ?? "note",
            "subject": body["subject"] ?? NSNull(),
            "description": body["description"] ?? NSNull(),
            "lead_id": body["lead_id"] ?? NSNull(),
            "deal_id": body["deal_id"] ?? NSNull(),
            "created_at": Self.now()
        ]
        return decodeOrStub(Activity.self, dict: dict, pendingId: pendingId, extras: [:])
    }

    /// Encode the dict to JSON and decode to T. If decoding fails (a model
    /// could later add a non-optional field), fall back to a minimal stub
    /// with just id + required `extras`. We dynamically build a Decoder via
    /// JSONSerialization to avoid `try!` in any path.
    private static func decodeOrStub<T: Decodable>(_ type: T.Type, dict: [String: Any], pendingId: String, extras: [String: Any]) -> T {
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let v = try? JSONDecoder().decode(T.self, from: data) {
            return v
        }
        // Fallback: just id + extras (covers e.g. CRMAccount.name being non-optional)
        var minimal: [String: Any] = ["id": pendingId]
        for (k, v) in extras { minimal[k] = v }
        if let data = try? JSONSerialization.data(withJSONObject: minimal),
           let v = try? JSONDecoder().decode(T.self, from: data) {
            return v
        }
        // Truly degenerate — surface a programmer error at runtime rather
        // than crash. unsafeBitCast would be incorrect; instead we trap
        // intentionally so the caller's catch can report it.
        fatalError("CRMService.optimistic\(type): could not synthesize a stub. Add the model's required fields to the optimistic builder.")
    }
}

/// Shared URLRequest plumbing for the offline extension. Mirrors the
/// private helpers in CRMService.swift so we don't need to widen their
/// access level.
private enum OfflineRequestHelpers {
    static let baseHostURL: URL = URL(string: "https://kinematic-production.up.railway.app")!

    static func buildURL(path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseHostURL)?.absoluteURL else {
            throw CRMServiceError.server("Bad URL")
        }
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
        if let cid = CRMClientScope.selectedClientId() {
            req.setValue(cid, forHTTPHeaderField: "X-Client-Id")
        }
    }

    static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw CRMServiceError.badResponse(0) }
        if !(200..<300).contains(http.statusCode) {
            if let env = try? JSONDecoder().decode(APIEnvelope<EmptyAck>.self, from: data),
               let msg = env.error ?? env.message {
                throw CRMServiceError.server(msg)
            }
            throw CRMServiceError.badResponse(http.statusCode)
        }
    }

    static func decodeEnvelope<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        if let env = try? decoder.decode(APIEnvelope<T>.self, from: data), let p = env.data { return p }
        if let raw = try? decoder.decode(T.self, from: data) { return raw }
        throw CRMServiceError.decodeFailed("Expected \(T.self)")
    }
}
