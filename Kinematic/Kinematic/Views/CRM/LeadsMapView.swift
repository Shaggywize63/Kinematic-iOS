import SwiftUI
import MapKit

// Native dashboard map (MapKit — no API key needed). Plots leads that have
// real GPS coordinates, mirroring the web LeadsGeoMap. Self-contained: fetches
// up to 200 leads (honouring the current city/client scope via CRMService) and
// drops a pin per lead with coordinates.
struct DashboardLeadsMapCard: View {
    struct LeadPin: Identifiable {
        let id: String
        let name: String
        let coord: CLLocationCoordinate2D
        /// The lead's industry (the geo payload carries it). Spark & Ray colours the pin by it.
        let industry: String?
    }

    /// Spark & Ray only: pins are coloured by industry and an industry filter is offered.
    private var isSpark: Bool { SparkJourney.isActive }
    /// Selected industry filter: nil = all, `SparkIndustries.noIndustryFilter` = leads without one.
    @State private var industryFilter: String? = nil
    /// The tenant's industries (`config.industries`): the filter options, the pin colours and the legend.
    @ObservedObject var industries = IndustriesStore.shared

    @State private var pins: [LeadPin] = []
    @State private var loading = true
    @State private var selectedLeadId: String?
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 22.0, longitude: 79.0),
                           span: MKCoordinateSpan(latitudeDelta: 24, longitudeDelta: 24)) // India
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "map.fill").foregroundColor(Brand.red)
                Text("Leads Map").font(.headline)
                Spacer()
                if !pins.isEmpty {
                    Text("\(pins.count) located").font(.caption).foregroundColor(.secondary)
                }
                if isSpark { industryFilterMenu }
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            } else if pins.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "mappin.slash").font(.title2).foregroundColor(.secondary)
                    Text("No leads with GPS coordinates yet.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                Map(position: $position) {
                    ForEach(pins) { p in
                        // Tappable annotation — opens the lead on tap (a plain
                        // Marker isn't interactive).
                        Annotation(p.name, coordinate: p.coord) {
                            Button { selectedLeadId = p.id } label: {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white, pinColor(p))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                if isSpark { industryLegend }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
        .navigationDestination(item: $selectedLeadId) { id in
            LeadDetailView(leadId: id)
        }
        .task(id: industryFilter) { await load() }
        .task { if isSpark { await industries.loadIfNeeded() } }
    }

    /// Spark & Ray: a colour key for the configured industries (plus grey for leads without / outside the list).
    private var industryLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(industries.config.names, id: \.self) { name in
                    legendItem(name)
                }
                legendItem("No industry / other")
            }
        }
    }

    private func legendItem(_ name: String) -> some View {
        HStack(spacing: 5) {
            SparkIndustryDot(industry: name, size: 8)
            Text(name).font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
    }

    /// Pin colour: the industry colour for Spark & Ray, brand red for everyone else.
    private func pinColor(_ p: LeadPin) -> Color {
        isSpark ? Color.sparkIndustry(p.industry) : Brand.red
    }

    /// Menu to narrow the map to one industry (with a colour dot per option).
    private var industryFilterMenu: some View {
        Menu {
            Button { industryFilter = nil } label: {
                Label("All industries", systemImage: industryFilter == nil ? "checkmark" : "circle")
            }
            ForEach(industries.config.names, id: \.self) { name in
                Button { industryFilter = name } label: {
                    Label(name, systemImage: industryFilter == name ? "checkmark.circle.fill" : "circle.fill")
                }
            }
            Button { industryFilter = SparkIndustries.noIndustryFilter } label: {
                Label("No industry", systemImage: industryFilter == SparkIndustries.noIndustryFilter ? "checkmark" : "circle")
            }
        } label: {
            Label(industryFilterTitle, systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption)
        }
    }

    private var industryFilterTitle: String {
        guard let f = industryFilter else { return "Industry" }
        return f == SparkIndustries.noIndustryFilter ? "No industry" : f
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let leads = (try? await CRMService.shared.listLeadsGeo(city: CRMLocationStore.shared.city, state: CRMLocationStore.shared.state, industry: isSpark ? industryFilter : nil)) ?? []
        let built: [LeadPin] = leads.compactMap { lead in
            guard let lat = lead.latitude, let lon = lead.longitude,
                  !(lat == 0 && lon == 0) else { return nil }
            return LeadPin(id: lead.id, name: lead.displayName, coord: CLLocationCoordinate2D(latitude: lat, longitude: lon), industry: lead.industry)
        }
        await MainActor.run {
            pins = built
            if let region = Self.fittingRegion(for: built) { position = .region(region) }
        }
    }

    /// Region that frames all pins with a little padding.
    private static func fittingRegion(for pins: [LeadPin]) -> MKCoordinateRegion? {
        guard !pins.isEmpty else { return nil }
        let lats = pins.map { $0.coord.latitude }
        let lons = pins.map { $0.coord.longitude }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.05)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
