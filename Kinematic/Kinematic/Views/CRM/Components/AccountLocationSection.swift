import SwiftUI

/// The account create / edit forms' "Address" block: Address line 1 / 2, State → City (the same cascading
/// `LocationPicker` the lead forms use, with a typed City allowed), PIN code and Country.
///
/// Field-override contract: every row is gated by `account.<key>` (hide / relabel / required) and nothing is
/// drawn until the admin's overrides have loaded, so a hidden field never flashes.
struct AccountLocationSection: View {
    @Binding var draft: AccountLocationDraft
    @ObservedObject var fieldOverrides: LeadFieldOverridesModel

    private func isHidden(_ key: String) -> Bool {
        fieldOverrides.isHidden(entity: "account", key)
    }

    /// The admin's label, with a star when the admin made the field required.
    private func label(_ key: String, _ fallback: String) -> String {
        let text = fieldOverrides.labelFor(entity: "account", key, fallback)
        return fieldOverrides.requiredFor(entity: "account", key, false) ? text + " *" : text
    }

    private var anyVisible: Bool {
        AccountLocationDraft.keys.contains { !isHidden($0) }
    }

    var body: some View {
        if fieldOverrides.didLoad && anyVisible {
            Section("Address") {
                textRows
                locationRows
                trailingRows
            }
        }
    }

    @ViewBuilder
    private var textRows: some View {
        if !isHidden("address_line1") {
            TextField(label("address_line1", "Address"), text: $draft.addressLine1)
                .textContentType(.streetAddressLine1)
        }
        if !isHidden("address_line2") {
            TextField(label("address_line2", "Address line 2"), text: $draft.addressLine2)
                .textContentType(.streetAddressLine2)
        }
    }

    /// State and City are gated independently: hiding one never drops the other.
    @ViewBuilder
    private var locationRows: some View {
        if !isHidden("state") || !isHidden("city") {
            LocationPicker(
                state: $draft.state,
                city: $draft.city,
                showState: !isHidden("state"),
                showCity: !isHidden("city"),
                stateLabel: label("state", "State"),
                cityLabel: label("city", "City"),
                allowTypedCity: true
            )
        }
    }

    @ViewBuilder
    private var trailingRows: some View {
        if !isHidden("postal_code") {
            TextField(label("postal_code", "PIN code"), text: $draft.postalCode)
                .keyboardType(.numberPad)
        }
        if !isHidden("country") {
            TextField(label("country", "Country"), text: $draft.country)
        }
    }
}

/// What the account forms read off the overrides model to build and validate the payload.
extension AccountLocationDraft {
    /// Location keys the admin hid: never sent, never shown.
    @MainActor
    static func hiddenKeys(_ overrides: LeadFieldOverridesModel) -> Set<String> {
        Set(keys.filter { overrides.isHidden(entity: "account", $0) })
    }

    /// Location keys the admin marked required.
    @MainActor
    static func requiredKeys(_ overrides: LeadFieldOverridesModel) -> Set<String> {
        Set(keys.filter { overrides.requiredFor(entity: "account", $0, false) })
    }

    /// True while a visible, required location field is blank (keeps Save off).
    @MainActor
    func isIncomplete(_ overrides: LeadFieldOverridesModel) -> Bool {
        !missingRequired(hidden: Self.hiddenKeys(overrides), required: Self.requiredKeys(overrides)).isEmpty
    }
}
