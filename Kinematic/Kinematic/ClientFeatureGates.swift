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
}
