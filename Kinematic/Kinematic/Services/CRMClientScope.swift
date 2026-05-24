//
//  CRMClientScope.swift
//  Kinematic CRM
//
//  Holds the active multi-tenant client picker selection used by admin users
//  who can hop between scopes. Mirrors the dashboard's `kinematic_selected_client`
//  localStorage key so the contract is exactly the same: a UUID stamped into
//  the `X-Client-Id` request header on every CRM call.
//
//  Client-level users never call `setSelectedClientId(_:)` — their scope is
//  pinned by the JWT, so the iOS UI just leaves this nil and the backend
//  uses the pinned claim. Org admins set it from the client picker, and
//  every CRMService request thereafter is scoped to that client (legacy
//  NULL-org rows still come back, matching dashboard parity).
//

import Foundation

enum CRMClientScope {
    private static let storageKey = "kinematic_selected_client"

    /// Hardcoded Tata Tiscon tenant UUID. Mirrors the constant the web
    /// dashboard uses to gate the multi-product Lead Convert flow — Tata's
    /// sales motion ships steel by tonnage, so they get the kg/pieces/₹
    /// three-way sync UI while every other tenant keeps the simple
    /// single-amount convert form.
    static let tataTisconClientId = "a1f67468-526e-4734-be3a-2cb132cc2804"

    /// True when EITHER the admin client-picker is set to Tata OR the
    /// signed-in user's JWT carries a `client_id` claim that matches
    /// Tata's tenant UUID. The picker path covers org-admins hopping
    /// between scopes; the JWT path covers Tata-pinned users (whose
    /// onboarding may not have stamped the picker on first login).
    /// Picker takes precedence when both are set.
    static func isTataTiscon() -> Bool {
        if let cid = selectedClientId(),
           cid.caseInsensitiveCompare(tataTisconClientId) == .orderedSame {
            return true
        }
        if let jwtCid = clientIdFromJWT(),
           jwtCid.caseInsensitiveCompare(tataTisconClientId) == .orderedSame {
            return true
        }
        return false
    }

    /// Persisted client selection. Returns nil unless the stored value is a
    /// valid UUID — guards against legacy strings ("Kinematic", "") that
    /// shouldn't end up on the wire.
    static func selectedClientId() -> String? {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        guard !raw.isEmpty else { return nil }
        return isUUID(raw) ? raw : nil
    }

    /// Update the picker selection. Pass nil to clear (e.g. when the admin
    /// switches back to the org-wide view).
    static func setSelectedClientId(_ value: String?) {
        if let value, !value.isEmpty {
            UserDefaults.standard.set(value, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        NotificationCenter.default.post(name: .crmClientScopeChanged, object: nil)
    }

    /// Posted whenever the active client changes. ViewModels that cache
    /// per-client data can subscribe to refresh their lists.
    static let didChange = Notification.Name.crmClientScopeChanged

    /// Decode the `client_id` claim out of the stored JWT, if present.
    /// Returns nil for non-Tata users (most accounts), demo mode, or any
    /// malformed token — caller treats nil as "no JWT-pinned client".
    /// We parse the middle JWT segment by hand rather than pulling in
    /// a JWT lib for one field. Backend never signs HS512/EdDSA with a
    /// segment count != 3, so a clean string-split + base64url decode is
    /// enough.
    private static func clientIdFromJWT() -> String? {
        let token = Session.sharedToken
        guard !token.isEmpty else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        let payload = String(parts[1])
        // base64url → base64 (URL-safe replacements + pad to length % 4)
        var b64 = payload.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let cid = json["client_id"] as? String, isUUID(cid) { return cid }
        return nil
    }

    private static func isUUID(_ s: String) -> Bool {
        // Mirrors the regex used in `/lib/api.ts` on the dashboard.
        let pattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension Notification.Name {
    static let crmClientScopeChanged = Notification.Name("CRMClientScopeChanged")
}
