import SwiftUI

/// Compact dual-dropdown filter bar shown at the top of the CRM
/// tab container. Reads/writes CRMLocationStore.shared so list
/// screens can pick the values up via Combine.
struct LocationFilter: View {
    @ObservedObject var store: CRMLocationStore = .shared
    @State private var states: [CrmState] = []
    @State private var cities: [CrmCity] = []

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill").foregroundColor(.secondary).font(.caption2)
            Menu {
                Button("All states") { store.setState(nil) }
                Divider()
                ForEach(states) { s in
                    Button(s.name) { store.setState(s.name) }
                }
            } label: {
                pillLabel(text: store.state ?? "State", isActive: store.state != nil)
            }
            Menu {
                Button(store.state == nil ? "Pick a state" : "All cities") { store.city = nil }
                Divider()
                ForEach(cities) { c in
                    Button(c.name) { store.city = c.name }
                }
            } label: {
                pillLabel(text: store.city ?? "City", isActive: store.city != nil)
            }
            .disabled(store.state == nil)
            .opacity(store.state == nil ? 0.5 : 1)
            if store.isActive {
                Button {
                    store.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground))
        .task { await loadStates() }
        .onReceive(store.$state) { newState in
            Task { await loadCities(forStateName: newState) }
        }
    }

    private func pillLabel(text: String, isActive: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundColor(isActive ? .white : .primary)
            .background(isActive ? Color.indigo : Color(uiColor: .tertiarySystemBackground))
            .cornerRadius(6)
    }

    private func loadStates() async {
        states = (try? await CRMService.shared.listStates()) ?? []
    }

    private func loadCities(forStateName name: String?) async {
        guard let name, let row = states.first(where: { $0.name == name }) else {
            cities = []
            return
        }
        cities = (try? await CRMService.shared.citiesForState(row.id)) ?? []
    }
}
