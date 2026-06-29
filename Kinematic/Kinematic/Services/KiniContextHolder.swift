//
//  KiniContextHolder.swift
//  Kinematic CRM
//
//  Lightweight, app-wide "where is the user right now?" holder for the KINI
//  agentic-chat v2 context block. Record detail screens stamp their screen /
//  record_type / record_id in `.onAppear`; the global KINI chat reads the
//  current snapshot when the rep sends a message so the assistant knows what
//  they're looking at.
//
//  This is a *hint*, not a fence — KINI's v2 endpoint can still answer across
//  every module. The context just biases it toward the record on screen.
//
//  Modelled on the other shared singletons in this codebase (Session,
//  CRMLocationStore): a `static let shared` with simple stored properties.
//  Mutated only from the main actor (SwiftUI `.onAppear`), so no extra
//  synchronisation is needed.
//

import Foundation

final class KiniContextHolder {
    static let shared = KiniContextHolder()

    /// Coarse screen name, e.g. "lead_detail", "deal_detail". nil on list /
    /// non-CRM screens.
    var screen: String?
    /// "lead" | "deal" | "contact" | "account" — only set when a specific
    /// record is open.
    var recordType: String?
    /// UUID of the open record. Pairs with `recordType`.
    var recordId: String?
    /// Active CRM city scope, if any. Mirrors the `?city=` GET scope.
    var city: String?

    private init() {}

    /// Stamp the context for an open record detail screen. Pass nils for the
    /// record fields on list / overview screens so KINI doesn't pin to a
    /// stale record.
    func set(screen: String?, recordType: String?, recordId: String?, city: String? = nil) {
        self.screen = screen
        self.recordType = recordType
        self.recordId = recordId
        self.city = city
    }

    /// Reset to "no specific screen / record". Useful on list screens.
    func clear() {
        screen = nil
        recordType = nil
        recordId = nil
        city = nil
    }

    /// Build the `context` dict KINI's v2 chat expects. Always carries
    /// `module: "crm"`; every other key is omitted when nil so the backend
    /// treats a missing record as "no record open". The current city scope is
    /// folded in automatically when the caller didn't stamp one.
    func contextDict() -> [String: Any] {
        var dict: [String: Any] = ["module": "crm"]
        if let screen, !screen.isEmpty { dict["screen"] = screen }
        if let recordType, !recordType.isEmpty { dict["record_type"] = recordType }
        if let recordId, !recordId.isEmpty { dict["record_id"] = recordId }
        let effectiveCity = city ?? CRMLocationStore.shared.city
        if let effectiveCity, !effectiveCity.isEmpty { dict["city"] = effectiveCity }
        return dict
    }
}
