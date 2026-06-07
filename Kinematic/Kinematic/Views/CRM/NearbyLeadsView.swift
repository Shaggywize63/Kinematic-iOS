//
//  NearbyLeadsView.swift
//  Kinematic CRM
//
//  Surfaces the rep's geo-tagged leads sorted by haversine distance from
//  the device's current location. Tapping the navigate button opens Apple
//  Maps with turn-by-turn directions; tapping the row opens the standard
//  LeadDetailView. Lives in the CRM More tab.
//

import SwiftUI
import Combine
import CoreLocation
import MapKit

/// Lead + computed distance, ready for display.
struct NearbyLead: Identifiable, Hashable {
    let lead: Lead
    let distanceMeters: CLLocationDistance
    var id: String { lead.id }
}

@MainActor
final class NearbyLeadsViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var loading: Bool = false
    @Published var leads: [NearbyLead] = []
    @Published var error: String? = nil
    @Published var origin: CLLocation? = nil

    private let manager = CLLocationManager()
    private var didFetch = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Entry point from `.onAppear`. Requests permission if needed; otherwise
    /// triggers a single-shot location request. Permission/state changes
    /// arrive on the delegate.
    func start() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            error = "Enable location access for Kinematic in Settings to find leads near you."
        case .authorizedWhenInUse, .authorizedAlways:
            requestOneShot()
        @unknown default:
            error = "Location services unavailable."
        }
    }

    func refresh() {
        leads = []
        origin = nil
        error = nil
        didFetch = false
        start()
    }

    private func requestOneShot() {
        loading = true
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                requestOneShot()
            case .restricted, .denied:
                error = "Enable location access for Kinematic in Settings to find leads near you."
                loading = false
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.origin = loc
            await self.loadLeads(near: loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.loading = false
            // Don't overwrite a real error if we already have one.
            if self.error == nil { self.error = error.localizedDescription }
        }
    }

    private func loadLeads(near origin: CLLocation) async {
        guard !didFetch else { return }
        didFetch = true
        loading = true
        defer { loading = false }
        do {
            let all = try await CRMService.shared.listLeadsGeo()
            let sorted: [NearbyLead] = all.compactMap { lead in
                guard let lat = lead.latitude, let lon = lead.longitude else { return nil }
                let dist = origin.distance(from: CLLocation(latitude: lat, longitude: lon))
                return NearbyLead(lead: lead, distanceMeters: dist)
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            self.leads = sorted
        } catch {
            self.error = "Couldn't load leads: \(error.localizedDescription)"
        }
    }
}

struct NearbyLeadsView: View {
    @StateObject private var vm = NearbyLeadsViewModel()

    var body: some View {
        Group {
            if vm.loading && vm.leads.isEmpty {
                ProgressView("Finding nearby leads…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.error, vm.leads.isEmpty {
                emptyState(err)
            } else if vm.leads.isEmpty {
                emptyState("No leads with saved coordinates yet. Capture location while creating a lead, or run the dashboard's bulk-coordinates upload, to populate this view.")
            } else {
                List(vm.leads) { row in
                    NearbyLeadRow(row: row)
                }
                .listStyle(.plain)
                .refreshable { vm.refresh() }
            }
        }
        .navigationTitle("Nearest Leads")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear { vm.start() }
    }

    @ViewBuilder
    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Button("Try again") { vm.refresh() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NearbyLeadRow: View {
    let row: NearbyLead

    var body: some View {
        NavigationLink {
            LeadDetailView(leadId: row.lead.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.lead.displayName)
                        .font(.body.weight(.semibold))
                    let subtitle = [row.lead.city, row.lead.state]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(formatDistance(row.distanceMeters))
                        .font(.caption)
                        .foregroundColor(Brand.red)
                }
                Spacer()
                Button {
                    openInMaps(row)
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Navigate to \(row.lead.displayName)")
            }
            .padding(.vertical, 4)
        }
    }

    private func openInMaps(_ row: NearbyLead) {
        guard let lat = row.lead.latitude, let lon = row.lead.longitude else { return }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let placemark = MKPlacemark(coordinate: coord)
        let item = MKMapItem(placemark: placemark)
        item.name = row.lead.displayName
        // MKLaunchOptionsDirectionsModeDriving asks Maps to compute a route
        // from the user's current location to the lead's pin and present
        // the start-navigation UI.
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
        ])
    }
}

private func formatDistance(_ meters: CLLocationDistance) -> String {
    if meters < 1_000 { return "\(Int(meters)) m away" }
    return String(format: "%.1f km away", meters / 1_000.0)
}
