import SwiftUI

/// The "Owner" picker on the account / deal edit forms. The host decides WHETHER to show it (role gate,
/// field override, settings loaded — see `RecordOwnerRules`); this only draws the row.
///
/// `selectedId` starts as the record's current owner id ("" when it has none) and the host builds its PATCH
/// with `RecordOwnerRules.applyOwner(original:selected:to:)`, so the owner goes on the wire only when it
/// really changed. Clearing an owner is not offered: an owner-less record gets an "Unassigned" row (the
/// untouched state), an owned one does not.
struct RecordOwnerPickerRow: View {
    let label: String
    let users: [AssignableUser]
    let currentOwnerId: String?
    let currentOwnerName: String?
    @Binding var selectedId: String

    private var current: String {
        (currentOwnerId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentIsListed: Bool {
        users.contains { $0.id == current }
    }

    private var currentLabel: String {
        let n = (currentOwnerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Current owner" : n
    }

    var body: some View {
        Picker(label, selection: $selectedId) {
            if current.isEmpty {
                Text("Unassigned").tag("")
            } else if !currentIsListed {
                // The list can lack the present owner (loading, or outside the caller's team). Keep them
                // selectable so the picker never points at a tag that does not exist.
                Text(currentLabel).tag(current)
            }
            ForEach(users) { u in
                Text(u.displayName).tag(u.id)
            }
        }
    }
}
