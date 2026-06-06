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
/// left untouched — it stays the rep's captured submission location.
struct AddressSearchField: View {
    @Binding var addressLine1: String
    @Binding var city: String
    @Binding var state: String
    @Binding var postalCode: String

    @State private var query = ""
    @State private var results: [CRMPlacePrediction] = []
    @State private var searching = false

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
        query = ""
        results = []
    }
}
