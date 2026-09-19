import SwiftUI

/// Cascading State → City picker that pulls from the org's States &
/// Cities management list. Falls back to free text inputs if the org
/// hasn't seeded any states yet so users aren't blocked.
struct LocationPicker: View {
    @Binding var state: String
    @Binding var city: String
    /// Per-field visibility so State and City can be gated INDEPENDENTLY by
    /// the field-override contract (admins may hide one but not the other).
    /// Both default to true so existing call sites are unaffected.
    var showState: Bool = true
    var showCity: Bool = true
    /// Admin-overridable labels (fall back to the built-in defaults).
    var stateLabel: String = "State"
    var cityLabel: String = "City"

    @State private var states: [CrmState] = []
    @State private var cities: [CrmCity] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading locations…").font(.caption).foregroundColor(.secondary)
                }
            } else if states.isEmpty {
                // Fallback: free text
                if showState { TextField(stateLabel, text: $state) }
                if showCity { TextField(cityLabel, text: $city) }
            } else {
                if showState {
                    Picker(stateLabel, selection: $state) {
                        Text("— Select state —").tag("")
                        ForEach(states) { s in
                            Text(s.name).tag(s.name)
                        }
                    }
                    .onChange(of: state) { _, newValue in
                        city = ""
                        Task { await reloadCities(for: newValue) }
                    }
                }

                if showCity {
                    if showState {
                        // Normal cascade: City is driven by the State picker.
                        Picker(cityLabel, selection: $city) {
                            Text(state.isEmpty ? "Pick a state first" : "— Select city —").tag("")
                            ForEach(cities) { c in
                                Text(c.name).tag(c.name)
                            }
                        }
                        .disabled(state.isEmpty || cities.isEmpty)
                    } else {
                        // State is hidden, so there's no picker to drive the
                        // cascade — fall back to a free-text City so the field
                        // is still editable rather than a permanently disabled
                        // dropdown.
                        TextField(cityLabel, text: $city)
                    }
                }
            }
        }
        .task { await loadStates() }
    }

    private func loadStates() async {
        loading = true
        states = (try? await CRMService.shared.listStates()) ?? []
        if !state.isEmpty {
            await reloadCities(for: state)
        }
        loading = false
    }

    private func reloadCities(for stateName: String) async {
        guard let row = states.first(where: { $0.name == stateName }) else {
            cities = []
            return
        }
        cities = (try? await CRMService.shared.citiesForState(row.id)) ?? []
    }
}
