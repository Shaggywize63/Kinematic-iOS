// QueueOwnership — whose a row in an offline queue is, as pure functions so it is unit-tested
// (see KinematicTests/QueueOwnershipTests).
//
// The offline queues (attendance, distribution orders / payments / returns) tag every row with an owner so a
// re-login under another account never sends the previous user's pending writes. They used to key on the last
// 24 characters of the ACCESS TOKEN — but that token is replaced by every silent refresh (about hourly), so a
// row queued earlier no longer matched its own user and was never sent again.
//
// Rows are now keyed by the stable user id ("u:<id>"). Rows queued by older builds still carry a token suffix
// ("legacy" keys; a token suffix is base64url and can never start with "u:"), and are carried over like this:
//   * a legacy key equal to the CURRENT token's suffix is certainly the current user's;
//   * a legacy key that no longer matches (the token was refreshed since) is the current user's only when the
//     row was created at or after the start of the current login session — nobody else was signed in then;
//   * everything else (older than this login, older than a queue's own staleness window, or no way to tell) is
//     left exactly as it is — not adopted, not deleted — rather than risk sending one person's punches or
//     orders under another account, or replaying a punch days late.

import Foundation

/// A queued row that remembers its owner.
protocol QueueOwned {
    var userKey: String { get set }
    var createdAt: Date { get }
}

enum QueueOwnership {
    static let userPrefix = "u:"

    /// Who is signed in right now, as far as the queues care.
    struct Identity: Equatable {
        /// The stable user id (nil only before the profile has loaded).
        var userId: String?
        /// The current access token ("" when signed out).
        var token: String
        /// The earliest creation time at which a legacy row that no longer matches the token may be adopted
        /// (the start of the current login session, or later — see `adoptionFloor`). nil = none may.
        var sessionStart: Date?
    }

    /// The key older builds wrote: the last 24 characters of the access token.
    static func legacyKey(token: String) -> String { String(token.suffix(24)) }

    static func userKey(userId: String) -> String { userPrefix + userId }

    static func isLegacy(_ key: String) -> Bool { !key.hasPrefix(userPrefix) }

    /// The key a NEW row gets. Falls back to the token suffix only while the user id is not known yet, so a
    /// row is never written without an owner.
    static func keyForNewRow(_ identity: Identity) -> String {
        if let id = identity.userId, !id.isEmpty { return userKey(userId: id) }
        return legacyKey(token: identity.token)
    }

    /// Is this row the signed-in user's? Read-only, so it is safe to call while a view is drawing.
    static func owns(rowKey: String, createdAt: Date, identity: Identity) -> Bool {
        if let id = identity.userId, !id.isEmpty, rowKey == userKey(userId: id) { return true }
        guard isLegacy(rowKey) else { return false }               // somebody else's user key
        if !identity.token.isEmpty, rowKey == legacyKey(token: identity.token) { return true }
        if let start = identity.sessionStart, createdAt >= start { return true }
        return false
    }

    /// The user key a legacy row should be rewritten to, or nil to leave it alone (already migrated, someone
    /// else's, not provably the current user's, or no user id to write yet).
    static func migratedKey(rowKey: String, createdAt: Date, identity: Identity) -> String? {
        guard isLegacy(rowKey), let id = identity.userId, !id.isEmpty else { return nil }
        return owns(rowKey: rowKey, createdAt: createdAt, identity: identity) ? userKey(userId: id) : nil
    }

    /// Rewrite every legacy row the current user provably owns to the stable key. Nothing is ever removed or
    /// reordered, and running it again changes nothing. Returns how many rows changed.
    @discardableResult
    static func migrate<R: QueueOwned>(_ rows: inout [R], identity: Identity) -> Int {
        var changed = 0
        for i in rows.indices {
            if let key = migratedKey(rowKey: rows[i].userKey, createdAt: rows[i].createdAt, identity: identity) {
                rows[i].userKey = key
                changed += 1
            }
        }
        return changed
    }

    /// The earliest creation time at which a legacy row that no longer matches the token may be adopted: the
    /// start of the current login session — or, for a queue whose rows go stale (an attendance punch replayed
    /// days late would stamp the wrong time, or close the wrong shift), no further back than `window`.
    /// nil = unknown, so nothing unmatched is adopted.
    static func adoptionFloor(sessionStart: Date?, window: TimeInterval?, now: Date) -> Date? {
        guard let start = sessionStart else { return nil }
        guard let window = window else { return start }
        return max(start, now.addingTimeInterval(-window))
    }

    /// The signed-in identity, read from the session. `adoptionWindow` limits how old an adopted row may be
    /// (nil = any age within this login session).
    static func currentIdentity(adoptionWindow: TimeInterval? = nil, now: Date = Date()) -> Identity {
        Identity(userId: Session.currentUser?.id,
                 token: Session.sharedToken,
                 sessionStart: adoptionFloor(sessionStart: Session.sessionStartedAt, window: adoptionWindow, now: now))
    }
}
