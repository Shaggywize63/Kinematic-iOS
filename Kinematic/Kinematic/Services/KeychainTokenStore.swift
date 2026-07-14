//
//  KeychainTokenStore.swift
//  Kinematic
//
//  Secure at-rest storage for authentication credentials.
//
//  SECURITY_AUDIT_2026-07.md M-1: the access token, refresh token and
//  single-device session id previously lived in plaintext `UserDefaults`
//  (an unencrypted plist inside the app container). Anyone with a file-
//  system backup, a jailbroken device, or an unlocked device + Finder
//  access could read them. They now live in the iOS Keychain, encrypted
//  at rest under a hardware-backed class key and readable only after the
//  first device unlock since boot, on THIS device only (no iCloud sync).
//
//  Callers are unchanged: `Session.sharedToken` / `refreshToken` /
//  `sessionId` keep the exact same String/String? API — only their
//  backing store moved. A one-time lazy migration copies any legacy
//  plaintext value into the Keychain on first read and scrubs the
//  `UserDefaults` copy, so existing signed-in users are not logged out.
//
//  A tiny in-memory cache keeps the hot path cheap: the bearer token is
//  read on every authenticated request, and a raw Keychain lookup per
//  request would be wasteful, so we cache after the first read and keep
//  the cache in lockstep with every write.
//

import Foundation
import Security

enum KeychainTokenStore {
    /// Keychain generic-password `service`. Namespaced to the app so it can
    /// never collide with another item.
    private static let service = "com.shaggywize63.kinematic.auth"

    /// In-memory mirror of the Keychain, keyed by account. An empty string
    /// means "known to be absent" (so we don't re-hit the Keychain on every
    /// read for a logged-out user).
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    // MARK: - Public API (mirrors the old UserDefaults contract)

    /// Read a secret. Returns `""` when absent — matching the previous
    /// `UserDefaults.standard.string(forKey:) ?? ""` behaviour so no caller
    /// needs to change. Performs a lazy, one-time migration from the legacy
    /// plaintext `UserDefaults` key on first access.
    static func get(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }

        if let cached = cache[key] { return cached }

        if let fromKeychain = readKeychain(account: key) {
            cache[key] = fromKeychain
            return fromKeychain
        }

        // Legacy plaintext migration: move it into the Keychain, then delete
        // the unencrypted copy. Runs at most once per key (afterwards the
        // Keychain read above short-circuits).
        let defaults = UserDefaults.standard
        if let legacy = defaults.string(forKey: key), !legacy.isEmpty {
            writeKeychain(account: key, value: legacy)
            defaults.removeObject(forKey: key)
            cache[key] = legacy
            return legacy
        }

        cache[key] = ""
        return ""
    }

    /// Persist a secret. An empty value deletes the item (used by logout and
    /// by clearing the refresh/session on sign-out).
    static func set(_ value: String, for key: String) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = value
        if value.isEmpty {
            deleteKeychain(account: key)
        } else {
            writeKeychain(account: key, value: value)
        }
    }

    // MARK: - SecItem plumbing

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readKeychain(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func writeKeychain(account: String, value: String) {
        let data = Data(value.utf8)
        // AfterFirstUnlockThisDeviceOnly: available to background tasks (e.g.
        // location upload) once the user has unlocked since boot, never leaves
        // the device, never syncs to iCloud.
        let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible,
        ]
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary,
                                   update as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = baseQuery(account: account)
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = accessible
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func deleteKeychain(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
