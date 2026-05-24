//
//  CRMSyncEngine.swift
//  Kinematic CRM
//
//  Drains CRMWriteQueue oldest-first. Stops on the first network error so
//  we don't burn battery on a flat link; permanent (4xx) errors are
//  recorded once and skipped on subsequent passes. 5xx + network errors
//  keep retrying with exponential backoff until `maxAttempts`.
//
//  Triggers:
//    - NetworkReachability offline → online transition
//    - Pull-to-refresh on any CRM list view (best-effort)
//    - scenePhase .active in KinematicApp
//    - Manual "Retry" tap from the offline banner
//
//  Side effects:
//    - On a successful create, the queue row's `entityId` is rewritten
//      from `pending:<uuid>` to the real server uuid so any optimistic
//      list rows can be deduped on the next refresh.
//

import Foundation

@MainActor
final class CRMSyncEngine {
    static let shared = CRMSyncEngine()

    private let queue = CRMWriteQueue.shared
    private let api = CRMService.shared

    /// Hard cap so a permanently broken row never blocks the rest of the
    /// queue. Field-tested: 5 retries spread across reachability events is
    /// enough to ride out a coffee-shop captive portal without spamming.
    let maxAttempts = 5

    /// Currently flushing? Guarded so multiple reachability events can't
    /// fire overlapping flushes.
    private(set) var isFlushing = false

    private init() {}

    // MARK: - Public API

    /// Drain the CRM queue oldest-first. Returns once it hits a network
    /// error, runs out of work, or exhausts retry attempts.
    @discardableResult
    func flushQueue() async -> (synced: Int, failed: Int) {
        guard !isFlushing else { return (0, 0) }
        isFlushing = true
        defer { isFlushing = false }

        var synced = 0
        var failed = 0
        // Snapshot to iterate; the queue may grow underneath us if other
        // mutations come in mid-flush, but they'll be picked up next pass.
        let pending = queue.pendingForCurrentUser()
            .filter { !$0.permanentFailure && $0.attempt < maxAttempts }
            .sorted { $0.createdAt < $1.createdAt }

        for row in pending {
            do {
                try await dispatch(row)
                synced += 1
            } catch let CRMSyncError.permanent(message) {
                queue.recordError(row.id, error: message, permanent: true)
                failed += 1
                // Permanent errors don't stop the flush — keep draining.
            } catch let CRMSyncError.transient(message) {
                queue.recordError(row.id, error: message, permanent: false)
                // Transient = treat the link as flaky. Stop here so we
                // don't keep punching at a flat network.
                return (synced, failed + 1)
            } catch {
                queue.recordError(row.id, error: error.localizedDescription, permanent: false)
                return (synced, failed + 1)
            }
        }
        return (synced, failed)
    }

    /// Convenience proxy so NetworkReachability can drain distribution
    /// without holding a DistributionViewModel reference. Reuses the same
    /// methods DistributionViewModel.flushQueue uses.
    func flushDistribution() async {
        let cache = OrderCache.shared
        let dist = DistributionAPI.shared
        let p = cache.pendingForCurrentUser()
        for row in p.orders {
            do {
                _ = try await dist.submitOrder(row.input, idempotencyKey: row.idempotencyKey)
                cache.markOrderSynced(row.id)
            } catch { cache.recordOrderError(row.id, error: error.localizedDescription) }
        }
        for row in p.payments {
            do {
                _ = try await dist.submitPayment(row.input, idempotencyKey: row.idempotencyKey)
                cache.markPaymentSynced(row.id)
            } catch { cache.recordPaymentError(row.id, error: error.localizedDescription) }
        }
        for row in p.returns {
            do {
                _ = try await dist.submitReturn(row.input, idempotencyKey: row.idempotencyKey)
                cache.markReturnSynced(row.id)
            } catch { cache.recordReturnError(row.id, error: error.localizedDescription) }
        }
    }

    /// Manual retry from the offline-banner sheet. Resets attempt count so
    /// permanently-failed rows get one more shot.
    func retry(_ id: UUID) async {
        queue.resetForRetry(id)
        await flushQueue()
    }

    // MARK: - Dispatch

    private func dispatch(_ row: PendingCRMMutation) async throws {
        let body = (try? JSONSerialization.jsonObject(with: row.payload, options: [])) as? [String: Any] ?? [:]
        do {
            switch (row.entityType, row.operation, row.variant) {

            // ── Leads
            case (.lead, .create, _):
                let lead = try await api.createLead(body)
                queue.markSynced(row.id, realEntityId: lead.id)

            case (.lead, .update, _):
                guard let eid = row.entityId, !eid.hasPrefix("pending:") else {
                    // Update against a still-pending create — must wait.
                    throw CRMSyncError.transient("Waiting on prior create")
                }
                _ = try await api.patchLead(id: eid, body: body)
                queue.markSynced(row.id)

            // ── Contacts
            case (.contact, .create, _):
                let c = try await api.createContact(body)
                queue.markSynced(row.id, realEntityId: c.id)

            case (.contact, .update, _):
                guard let eid = row.entityId, !eid.hasPrefix("pending:") else {
                    throw CRMSyncError.transient("Waiting on prior create")
                }
                _ = try await api.patchContact(id: eid, body: body)
                queue.markSynced(row.id)

            // ── Accounts
            case (.account, .create, _):
                let a = try await api.createAccount(body)
                queue.markSynced(row.id, realEntityId: a.id)

            case (.account, .update, _):
                guard let eid = row.entityId, !eid.hasPrefix("pending:") else {
                    throw CRMSyncError.transient("Waiting on prior create")
                }
                _ = try await api.patchAccount(id: eid, body: body)
                queue.markSynced(row.id)

            // ── Deals
            case (.deal, .create, _):
                let d = try await api.createDeal(body)
                queue.markSynced(row.id, realEntityId: d.id)

            case (.deal, .update, "move-stage"):
                guard let eid = row.entityId, !eid.hasPrefix("pending:"),
                      let stageId = body["stage_id"] as? String else {
                    throw CRMSyncError.transient("Missing stage_id")
                }
                _ = try await api.moveDealStage(id: eid, stageId: stageId)
                queue.markSynced(row.id)

            case (.deal, .update, "win"):
                guard let eid = row.entityId, !eid.hasPrefix("pending:") else {
                    throw CRMSyncError.transient("Waiting on prior create")
                }
                let amount = body["amount"] as? Double
                let reason = body["reason"] as? String
                _ = try await api.winDeal(id: eid, amount: amount, reason: reason)
                queue.markSynced(row.id)

            case (.deal, .update, "lose"):
                guard let eid = row.entityId, !eid.hasPrefix("pending:"),
                      let reason = body["reason"] as? String else {
                    throw CRMSyncError.transient("Missing lose reason")
                }
                _ = try await api.loseDeal(id: eid, reason: reason)
                queue.markSynced(row.id)

            case (.deal, .update, _):
                guard let eid = row.entityId, !eid.hasPrefix("pending:") else {
                    throw CRMSyncError.transient("Waiting on prior create")
                }
                _ = try await api.patchDeal(id: eid, body: body)
                queue.markSynced(row.id)

            // ── Activities
            case (.activity, .create, _):
                let a = try await api.createActivity(body)
                queue.markSynced(row.id, realEntityId: a.id)

            case (.activity, .update, _):
                // CRMService doesn't expose a patchActivity yet — treat as
                // permanent so the row stops blocking the queue rather than
                // looping forever. Surfaced in the banner so the user can
                // delete it manually.
                throw CRMSyncError.permanent("Activity updates not supported offline")
            }
        } catch let CRMSyncError.transient(message) {
            throw CRMSyncError.transient(message)
        } catch let CRMSyncError.permanent(message) {
            throw CRMSyncError.permanent(message)
        } catch let CRMServiceError.badResponse(code) where (400..<500).contains(code) && code != 408 && code != 429 {
            // 4xx (except 408 Request Timeout, 429 Too Many Requests) means
            // the request will never succeed as-is — record permanently.
            throw CRMSyncError.permanent("HTTP \(code)")
        } catch let CRMServiceError.server(message) {
            // Server explicitly rejected — treat as permanent so we don't
            // hammer the same broken payload forever.
            throw CRMSyncError.permanent(message)
        } catch {
            // Network / 5xx / decode = transient.
            throw CRMSyncError.transient(error.localizedDescription)
        }
    }
}

/// Sync-engine internal error classification. Permanent → row stops
/// retrying; transient → flush halts and waits for the next reachability
/// event to pick up where we left off.
enum CRMSyncError: Error {
    case permanent(String)
    case transient(String)
}
