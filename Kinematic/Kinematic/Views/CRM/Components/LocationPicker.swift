import SwiftUI

/// Cascading State → City picker that pulls from the org's States &
/// Cities management list. Falls back to free text inputs if the org
/// hasn't seeded any states yet so users aren't blocked.
struct LocationPicker: View {
    @Binding var state: String
    @Binding var city: String

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
                TextField("State", text: $state)
                TextField("City", text: $city)
            } else {
                Picker("State", selection: $state) {
                    Text("— Select state —").tag("")
                    ForEach(states) { s in
                        Text(s.name).tag(s.name)
                    }
                }
                .onChange(of: state) { _, newValue in
                    city = ""
                    Task { await reloadCities(for: newValue) }
                }

                Picker("City", selection: $city) {
                    Text(state.isEmpty ? "Pick a state first" : "— Select city —").tag("")
                    ForEach(cities) { c in
                        Text(c.name).tag(c.name)
                    }
                }
                .disabled(state.isEmpty || cities.isEmpty)
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
