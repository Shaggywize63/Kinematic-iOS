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
    /// Opt-in (the account forms): a city that is not in the master list can still be typed, and a saved
    /// State / City that is not in the master stays selectable instead of reading as blank. Off by default so
    /// the lead and contact forms behave exactly as before.
    var allowTypedCity: Bool = false

    @State private var typingCity = false
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
                        if allowTypedCity && !state.isEmpty && !states.contains(where: { $0.name == state }) {
                            Text(state).tag(state)
                        }
                        ForEach(states) { s in
                            Text(s.name).tag(s.name)
                        }
                    }
                    .onChange(of: state) { _, newValue in
                        city = ""
                        typingCity = false
                        Task { await reloadCities(for: newValue) }
                    }
                }

                if showCity {
                    if showState {
                        // Normal cascade: City is driven by the State picker.
                        cascadedCity
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

    /// City under a visible State picker. Plain cascade by default; with `allowTypedCity` the list also carries a
    /// saved city that is not in the master plus an "Other (type city)" entry, and a state with no cities in the
    /// master gets a text field.
    @ViewBuilder
    private var cascadedCity: some View {
        if allowTypedCity && !state.isEmpty && cities.isEmpty {
            TextField(cityLabel, text: $city)
        } else {
            Picker(cityLabel, selection: cityChoice) {
                Text(state.isEmpty ? "Pick a state first" : "— Select city —").tag("")
                if allowTypedCity && !city.isEmpty && !cities.contains(where: { $0.name == city }) {
                    Text(city).tag(city)
                }
                ForEach(cities) { c in
                    Text(c.name).tag(c.name)
                }
                if allowTypedCity && !state.isEmpty {
                    Text("Other (type city)…").tag(Self.otherCityTag)
                }
            }
            .disabled(state.isEmpty || (cities.isEmpty && !allowTypedCity))
            if allowTypedCity && typingCity {
                TextField("Type the city", text: $city)
            }
        }
    }

    private static let otherCityTag = "__other_city__"

    /// The City picker's selection: the real city, or the "Other" marker while the rep is typing one.
    private var cityChoice: Binding<String> {
        Binding(
            get: { typingCity ? Self.otherCityTag : city },
            set: { picked in
                if picked == Self.otherCityTag {
                    typingCity = true
                    if cities.contains(where: { $0.name == city }) { city = "" }
                } else {
                    typingCity = false
                    city = picked
                }
            }
        )
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
