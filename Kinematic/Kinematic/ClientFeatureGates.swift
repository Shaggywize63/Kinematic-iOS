import Foundation

/// Tata Tiscon's CRM client id. Several features in the app were built
/// specifically for them (weighted-by-tonne pipeline view, line-item
/// per-kg pricing in the convert modal, …) and need to stay invisible
/// to every other client until those features are either generalised
/// or moved behind a tenant setting.
private let TATA_TISCON_CLIENT_ID = "a1f67468-526e-4734-be3a-2cb132cc2804"
/// The parent Kinematic tenant runs an inside-sales CRM, not a field-force
/// one — GPS lead-tagging is irrelevant, so location capture is hidden for
/// it on the lead form.
private let KINEMATIC_CLIENT_ID = "7ecd47d7-9268-4ea2-a8ce-384978c13667"

enum ClientFeatures {
    /// True when the signed-in user belongs to Tata Tiscon. Used to gate
    /// the legacy "cost toggle" / weighted-view affordances that were
    /// custom-built for their tonnage-driven pipeline. Other clients see
    /// the simpler default UI.
    static var isTataTiscon: Bool {
        Session.currentUser?.clientId == TATA_TISCON_CLIENT_ID
    }

    /// True when the signed-in user belongs to the parent Kinematic tenant.
    /// Gates off the GPS location capture on the lead form (inside sales
    /// doesn't geo-tag leads).
    static var isKinematic: Bool {
        Session.currentUser?.clientId == KINEMATIC_CLIENT_ID
    }

    /// True when the signed-in user is a Consumer Champion (Tata Tiscon's
    /// frontline FE designation). Gates manager-tier surfaces — Lead
    /// Score breakdown, Boost-score suggestions, and Lead Analytics —
    /// which clutter the field rep's workflow without giving them
    /// anything actionable. Matched against `orgRoleName` as a
    /// substring so admin variants like "Consumer Champion Manager"
    /// also collapse into the same gate without an app release.
    static var isConsumerChampion: Bool {
        let raw = Session.currentUser?.orgRoleName ?? ""
        return raw.lowercased().contains("consumer champion")
    }

    /// True when the signed-in user is allowed to reassign a lead's owner.
    /// Reps with `data_scope='own'` (e.g. Tata Tiscon's Consumer Champion
    /// designation) only see leads they own — handing one off would hide
    /// the record from them entirely, so the assign affordance must be
    /// suppressed for them in the UI. Backend permissions still enforce
    /// the rule independently; this just hides the dead control.
    static var canReassignLeads: Bool {
        (Session.currentUser?.orgRoleDataScope ?? "all") != "own"
    }

    /// True when the signed-in user's org has the Conversation Intelligence
    /// module ("Record call") switched on. This is an opt-in premium module
    /// (Tata Tiscon today, replicable to any tenant), so the gate is STRICT:
    /// we check `enabled_modules` directly instead of routing through
    /// `User.hasModule`, whose legacy-session fallback treats an empty module
    /// list as full access — that would leak this unreleased surface to every
    /// pre-entitlement session. No `crm_conversation_intel` module ⇒ the
    /// Record-call button and the Conversations section never render.
    static var hasConversationIntel: Bool {
        Session.currentUser?.enabledModules.contains("crm_conversation_intel") == true
    }

    // MARK: - SRS TATA Steel slimmed build

    /// True when the signed-in user belongs to SRS TATA Steel. This is the
    /// same tenant the app has historically labelled "Tata Tiscon" (client id
    /// a1f67468) — the client-management directory renamed it, but the data
    /// project + client id are unchanged, so it keys off the same id as
    /// `isTataTiscon`. Kept as its own named flag so the "hide these modules
    /// for SRS TATA Steel" policy lives in one place and is trivial to
    /// retarget if the client is ever moved to its own tenant.
    static var isSrsTataSteel: Bool { isTataTiscon }

    /// SRS TATA Steel runs a deliberately slimmed CRM: business-card scan,
    /// Conversation Intelligence, Accounts, and Leave are hidden for them.
    /// Every other tenant keeps the full surface. Render sites gate on these
    /// intent-named switches rather than checking the client id inline.
    static var showsCardScan: Bool { !isSrsTataSteel }
    static var showsAccounts: Bool { !isSrsTataSteel }

    /// True when the signed-in client purchased ONLY the CRM package (no field
    /// force, no distribution). Delegates to the single source of truth
    /// (`User.isCrmOnly`), which already treats a legacy/empty-entitlement
    /// session as NOT CRM-only so nothing over-hides during the brief
    /// pre-/auth/me window. Mirrors the dashboard's `isCrmOnlyClient` and
    /// Android's `Entitlements.isCrmOnly`.
    static var isCrmOnly: Bool { Session.currentUser?.isCrmOnly ?? false }

    /// Leave / the "Workplace" section is hidden for SRS TATA Steel AND for
    /// every CRM-only tenant (BMW, new lean-CRM clients, the parent Kinematic
    /// tenant) — "People & Support" was dropped from the CRM-only build. Full
    /// field-force tenants keep it.
    static var showsLeave:    Bool { !isSrsTataSteel && !isCrmOnly }

    /// Conversation Intelligence surfaces require BOTH the module SKU to be on
    /// AND the tenant to not be SRS TATA Steel (who have it switched off). The
    /// extra client gate also closes Android-parity edge cases where a legacy
    /// session's empty module list would otherwise read as full access.
    static var showsConversationIntel: Bool { hasConversationIntel && !isSrsTataSteel }
}
