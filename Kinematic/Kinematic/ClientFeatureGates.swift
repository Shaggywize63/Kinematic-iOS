import Foundation

/// Tata Tiscon's CRM client id. Several features in the app were built
/// specifically for them (weighted-by-tonne pipeline view, line-item
/// per-kg pricing in the convert modal, …) and need to stay invisible
/// to every other client until those features are either generalised
/// or moved behind a tenant setting.
private let TATA_TISCON_CLIENT_ID = "a1f67468-526e-4734-be3a-2cb132cc2804"

enum ClientFeatures {
    /// True when the signed-in user belongs to Tata Tiscon. Used to gate
    /// the legacy "cost toggle" / weighted-view affordances that were
    /// custom-built for their tonnage-driven pipeline. Other clients see
    /// the simpler default UI.
    static var isTataTiscon: Bool {
        Session.currentUser?.clientId == TATA_TISCON_CLIENT_ID
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
}
