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

    /// True when either the user's JWT-pinned client_id or the admin
    /// client-picker selection matches Tata Tiscon. Read both so org
    /// admins scoped down to Tata see the same UI as Tata's own users.
    static func isTataTiscon() -> Bool {
        if let cid = Session.currentUser?.clientId,
           cid.caseInsensitiveCompare(tataTisconClientId) == .orderedSame {
            return true
        }
        if let cid = selectedClientId(),
           cid.caseInsensitiveCompare(tataTisconClientId) == .orderedSame {
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

    private static func isUUID(_ s: String) -> Bool {
        // Mirrors the regex used in `/lib/api.ts` on the dashboard.
        let pattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension Notification.Name {
    static let crmClientScopeChanged = Notification.Name("CRMClientScopeChanged")
}
