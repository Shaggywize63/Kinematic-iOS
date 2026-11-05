import SwiftUI

/// A prediction from the backend Google Places proxy.
struct CRMPlacePrediction: Codable, Identifiable, Hashable {
    let placeId: String
    let description: String
    var id: String { placeId }
    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case description
    }
}

/// Resolved address parts for a picked place.
struct CRMPlaceDetail: Codable, Hashable {
    let addressLine1: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let latitude: Double?
    let longitude: Double?
    enum CodingKeys: String, CodingKey {
        case addressLine1 = "address_line1"
        case city, state
        case postalCode = "postal_code"
        case latitude, longitude
    }
}

/// Google-Places address search (via the backend proxy). Type an address, pick
/// a suggestion, and the bound address fields fill in. The lead's GPS pin is
/// left untouched unless the caller handles `onPicked` (Spark & Ray does).
struct AddressSearchField: View {
    @Binding var addressLine1: String
    @Binding var city: String
    @Binding var state: String
    @Binding var postalCode: String
    /// Called with the resolved place after the address fields were filled (Spark & Ray uses it to take the
    /// pin's coordinates from the picked address). Optional — other callers ignore it.
    var onPicked: ((CRMPlaceDetail) -> Void)? = nil

    @State private var query = ""
    @State private var results: [CRMPlacePrediction] = []
    @State private var searching = false

    // Explicit, because a private stored property (`query`, ...) makes the synthesized memberwise init private.
    init(addressLine1: Binding<String>, city: Binding<String>, state: Binding<String>, postalCode: Binding<String>,
         onPicked: ((CRMPlaceDetail) -> Void)? = nil) {
        _addressLine1 = addressLine1
        _city = city
        _state = state
        _postalCode = postalCode
        self.onPicked = onPicked
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search address (Google)", text: $query)
                    .textInputAutocapitalization(.words)
                    .onChange(of: query) { _ in Task { await search() } }
                if searching { ProgressView().scaleEffect(0.8) }
                else if !query.isEmpty {
                    Button { query = ""; results = [] } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            ForEach(results) { p in
                Button { Task { await pick(p) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle").font(.caption).foregroundColor(.secondary)
                        Text(p.description).font(.caption).foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { results = []; return }
        // Debounce — skip if the text changed while we waited.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard q == query.trimmingCharacters(in: .whitespaces) else { return }
        searching = true
        let r = await CRMService.shared.placesAutocomplete(q)
        if q == query.trimmingCharacters(in: .whitespaces) { results = r }
        searching = false
    }

    private func pick(_ p: CRMPlacePrediction) async {
        guard let d = await CRMService.shared.placeDetails(p.placeId) else { return }
        if let a = d.addressLine1, !a.isEmpty { addressLine1 = a }
        if let c = d.city, !c.isEmpty { city = c }
        if let s = d.state, !s.isEmpty { state = s }
        if let pc = d.postalCode, !pc.isEmpty { postalCode = pc }
        onPicked?(d)
        query = ""
        results = []
    }
}
