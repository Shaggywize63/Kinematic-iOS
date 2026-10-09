//
//  SessionCleanup.swift
//  Kinematic
//
//  What a sign-out must not leave behind. The credentials and the stored profile are cleared by
//  `Session.logout()`; this lists the REST of what belongs to the person who signed out, so the next person to sign
//  in on the same phone starts from nothing of theirs:
//
//    • the client they picked on the CRM dashboard (`X-Client-Id` on every CRM call),
//    • the state / city they picked in the CRM location filter (`?city=` on the analytics calls),
//    • the cached Home and Route-plan payloads (shown instead of a fresh load when the next one fails),
//    • the last-known `owner_assignment` value remembered per user + client (`OwnerAssignmentCache`),
//    • whatever the shared URL cache still holds (an entry is keyed by URL, not by who asked).
//
//  Pure Foundation. `keysToClear(existing:)` is the whole decision and is unit-tested; the rest just applies it.
//

import Foundation

enum SessionCleanup {
    /// UserDefaults key of the cached Home payload (`KinematicRepository`, restored at launch by `KiniAppState`).
    static let mobileHomeCacheKey = "cached_mobile_home_payload"
    /// UserDefaults key of the cached Route-plan payload (`KinematicRepository`).
    static let routePlanCacheKey = "cached_route_plan_payload"

    /// Keys removed at sign-out, whether or not they are set.
    static let userDefaultsKeys: [String] = [
        CRMClientScope.storageKey,        // "kinematic_selected_client"
        CRMLocationStore.stateKey,        // "crm.location.state"
        CRMLocationStore.cityKey,         // "crm.location.city"
        mobileHomeCacheKey,
        routePlanCacheKey,
    ]

    /// Every key that starts with one of these is removed too (a family of keys, one per user + client).
    static let userDefaultsKeyPrefixes: [String] = [
        OwnerAssignmentCache.keyPrefix,   // "lead_owner_admin_only."
    ]

    /// The keys to remove, given the keys that exist: the fixed ones, then each existing key with a listed prefix.
    /// No duplicates; the order is stable (fixed keys first, the rest sorted). Anything else is left alone.
    static func keysToClear(existing: [String]) -> [String] {
        var out = userDefaultsKeys
        let fixed = Set(userDefaultsKeys)
        let family = existing
            .filter { key in !fixed.contains(key) && userDefaultsKeyPrefixes.contains { key.hasPrefix($0) } }
        for key in Set(family).sorted() { out.append(key) }
        return out
    }

    /// Remove this person's persisted leftovers from `defaults`.
    static func clearPersistedUserState(in defaults: UserDefaults = .standard) {
        for key in keysToClear(existing: Array(defaults.dictionaryRepresentation().keys)) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Forget every response the shared URL cache holds.
    static func clearTransientCaches(urlCache: URLCache = .shared) {
        urlCache.removeAllCachedResponses()
    }
}
