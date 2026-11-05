import Foundation

/// Who may CHANGE a record's owner / assignee after it exists, and what an edit sends for it.
///
/// Covers the account owner, the deal owner and an activity's assignee(s). Mirrors the backend rule
/// (`sanitizeOwnerId` in `crm.routes.ts` silently drops `owner_id` from anyone whose role is not in
/// `OWNER_ASSIGN_ROLES`) and the web dashboard (those roles AND an org role whose data scope is not "own"),
/// so the app never offers a control the server would ignore.
///
/// This is deliberately separate from `LeadOwnerRules`, which answers the lead-specific
/// `lead_form.owner_assignment` question and has a slightly different role list (it includes `org_admin`
/// and has no `city_manager` / `supervisor`).
///
/// Pure (no session read except `currentUserCanChange`, no SwiftUI) so it is unit-tested — see
/// KinematicTests/RecordOwnerChangeTests.
enum RecordOwnerRules {
    /// System roles the backend lets reassign an owner (`OWNER_ASSIGN_ROLES`).
    static let changeRoles: Set<String> = [
        "super_admin", "admin", "main_admin", "sub_admin", "city_manager", "supervisor", "client",
    ]

    private static func norm(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// An admin / manager role whose org role does not limit them to their own records. A missing role can
    /// never change an owner, and data scope "own" never can whatever the system role says.
    static func canChangeRecordOwner(role: String?, dataScope: String?) -> Bool {
        guard changeRoles.contains(norm(role)) else { return false }
        return norm(dataScope) != "own"
    }

    /// `canChangeRecordOwner` for whoever is signed in.
    static var currentUserCanChange: Bool {
        let u = Session.currentUser
        return canChangeRecordOwner(role: u?.role, dataScope: u?.orgRoleDataScope)
    }

    // MARK: - Owner (accounts, deals)

    /// True when `selected` is a real user id that differs from `original` (ids compare case-insensitively).
    /// Clearing an owner is not offered, so an empty / nil selection never counts as a change.
    static func ownerChanged(original: String?, selected: String?) -> Bool {
        let s = norm(selected)
        guard !s.isEmpty else { return false }
        return s != norm(original)
    }

    /// `["owner_id": id]` only when the person actually picked a different owner, else `[:]` — so an
    /// untouched edit never carries an owner at all.
    static func ownerPatch(original: String?, selected: String?) -> [String: Any] {
        guard ownerChanged(original: original, selected: selected), let s = selected else { return [:] }
        return ["owner_id": s.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    /// Merge `ownerPatch` into a PATCH body.
    static func applyOwner(original: String?, selected: String?, to body: inout [String: Any]) {
        for (k, v) in ownerPatch(original: original, selected: selected) { body[k] = v }
    }

    // MARK: - Assignee (activities)

    /// Single-assignee PATCH piece (clients without multi-assignee support): `["assigned_to": id]` only when a
    /// different user was picked, else `[:]`.
    static func assignedToPatch(original: String?, selected: String?) -> [String: Any] {
        guard ownerChanged(original: original, selected: selected), let s = selected else { return [:] }
        return ["assigned_to": s.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    /// What the picker should remember after the person chose `picked`: nil ("unchanged") when it is the
    /// current assignee again (or nothing), else the picked id.
    static func selectionAfterPick(_ picked: String, original: String?) -> String? {
        ownerChanged(original: original, selected: picked) ? picked : nil
    }

    /// The Spark extras an activity edit may send. A person who may not change assignees keeps the activity's
    /// existing ones whatever the form holds; products and serial always follow the form.
    static func extrasForEdit(edited: SparkActivityExtras, previous: SparkActivityExtras, canChangeAssignees: Bool) -> SparkActivityExtras {
        guard !canChangeAssignees else { return edited }
        var out = edited
        out.assigneeIds = previous.assigneeIds
        return out
    }
}
