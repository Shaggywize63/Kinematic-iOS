//
//  NearbyLeadsView.swift
//  Kinematic CRM
//
//  Distance-sorted lead board surfaced from the More tab. Designed as a
//  "what's around me?" board, not a list: gradient hero summary, an
//  embedded MapKit preview with rep + lead pins, distance-tier filter
//  chips, and per-lead cards that show a rotating compass arrow pointing
//  at the lead plus quick actions (Call / WhatsApp / Navigate).
//

import SwiftUI
import Combine
import CoreLocation
import MapKit
import UIKit

// MARK: - Domain

/// One row in the nearest-leads board.
struct NearbyLead: Identifiable, Hashable {
    let lead: Lead
    let distanceMeters: CLLocationDistance
    /// Compass bearing in degrees, clockwise from north. Drives the arrow
    /// rotation on the row — "which way do I walk to find this lead?".
    let bearingDegrees: Double
    var id: String { lead.id }
}

/// Distance tier the user can filter by. Values are upper bounds in metres.
enum DistanceTier: String, CaseIterable, Identifiable {
    case walk = "≤ 1 km"
    case nearby = "≤ 5 km"
    case drive = "≤ 25 km"
    case all = "All"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .nearby: return "bicycle"
        case .drive: return "car.fill"
        case .all: return "globe.asia.australia.fill"
        }
    }
    var radiusMeters: Double? {
        switch self {
        case .walk: return 1_000
        case .nearby: return 5_000
        case .drive: return 25_000
        case .all: return nil
        }
    }
}

// MARK: - ViewModel

@MainActor
final class NearbyLeadsViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var loading: Bool = false
    @Published var leads: [NearbyLead] = []
    @Published var error: String? = nil
    @Published var origin: CLLocation? = nil
    @Published var tier: DistanceTier = .nearby

    private let manager = CLLocationManager()
    private var didFetch = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Filtered + sorted view derived from `leads` and the active tier.
    /// Recomputed on every access — the list is at most a few hundred rows.
    var visibleLeads: [NearbyLead] {
        guard let cap = tier.radiusMeters else { return leads }
        return leads.filter { $0.distanceMeters <= cap }
    }

    /// First lead inside the active tier — used by the hero header.
    var closest: NearbyLead? { visibleLeads.first }

    func start() {
        switch manager.authorizationStatus {
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
            let rows: [NearbyLead] = all.compactMap { lead in
                guard let lat = lead.latitude, let lon = lead.longitude else { return nil }
                let target = CLLocation(latitude: lat, longitude: lon)
                let dist = origin.distance(from: target)
                let bearing = bearingDegrees(
                    from: origin.coordinate,
                    to: target.coordinate
                )
                return NearbyLead(lead: lead, distanceMeters: dist, bearingDegrees: bearing)
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            self.leads = rows
        } catch {
            self.error = "Couldn't load leads: \(error.localizedDescription)"
        }
    }
}

// MARK: - Bearing math

/// Initial bearing from `a` to `b` in degrees clockwise from north.
private func bearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
    let φ1 = a.latitude  * .pi / 180
    let φ2 = b.latitude  * .pi / 180
    let Δλ = (b.longitude - a.longitude) * .pi / 180
    let y = sin(Δλ) * cos(φ2)
    let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
    let θ = atan2(y, x)
    return (θ * 180 / .pi).truncatingRemainder(dividingBy: 360).addingPositive(360)
}

private extension Double {
    /// Normalises a possibly-negative degree value to `[0, base)`.
    func addingPositive(_ base: Double) -> Double {
        let v = truncatingRemainder(dividingBy: base)
        return v < 0 ? v + base : v
    }
}

// MARK: - View

struct NearbyLeadsView: View {
    @StateObject private var vm = NearbyLeadsViewModel()
    @State private var mapCameraPos: MapCameraPosition = .automatic

    var body: some View {
        Group {
            if vm.loading && vm.leads.isEmpty {
                loadingState
            } else if let err = vm.error, vm.leads.isEmpty {
                emptyState(systemImage: "location.slash", text: err)
            } else if vm.leads.isEmpty {
                emptyState(
                    systemImage: "mappin.slash",
                    text: "No leads with saved coordinates yet. Capture location while creating a lead, or run the dashboard's bulk-coordinates upload, to populate this view."
                )
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        heroSummary
                        if vm.origin != nil { mapPreview }
                        tierPicker
                        leadCards
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .refreshable { vm.refresh() }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Brand.red.opacity(0.04),
                    Color(.systemBackground),
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Nearest Leads")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear { vm.start() }
    }

    // MARK: Header

    private var heroSummary: some View {
        let visible = vm.visibleLeads
        let closest = vm.closest
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.18))
                    Image(systemName: "location.north.line.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(visible.count) lead\(visible.count == 1 ? "" : "s") in range")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Text(vm.tier == .all ? "Within your tenant scope" : "Within \(vm.tier.rawValue)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
            }
            Divider().background(Color.white.opacity(0.25))
            HStack(alignment: .top, spacing: 16) {
                statBlock(label: "Closest", value: closest.map { formatDistance($0.distanceMeters) } ?? "—")
                Spacer().frame(width: 1).background(Color.white.opacity(0.2))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top lead").font(.caption2).foregroundColor(.white.opacity(0.85))
                    Text(closest?.lead.displayName ?? "—")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let city = closest?.lead.city, !city.isEmpty {
                        Text(city).font(.caption).foregroundColor(.white.opacity(0.85))
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Brand.red, Brand.red.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Brand.red.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.white.opacity(0.85))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }

    // MARK: Map

    private var mapPreview: some View {
        // Show the rep + the top-10 visible leads. Non-interactive — the
        // user taps a row to navigate; the map is purely orientational.
        let coords = Array(vm.visibleLeads.prefix(10))
        return ZStack(alignment: .topTrailing) {
            Map(position: $mapCameraPos) {
                if let origin = vm.origin {
                    Annotation("You", coordinate: origin.coordinate) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.18)).frame(width: 36, height: 36)
                            Circle().stroke(Color.blue, lineWidth: 2).frame(width: 18, height: 18)
                            Circle().fill(Color.blue).frame(width: 10, height: 10)
                        }
                    }
                }
                ForEach(coords) { row in
                    if let lat = row.lead.latitude, let lon = row.lead.longitude {
                        Annotation(row.lead.displayName, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Brand.red, .white)
                                .shadow(radius: 1)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear { recenterMap() }
            .onChange(of: vm.tier) { _, _ in recenterMap() }

            Button { recenterMap() } label: {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
            }
            .padding(8)
        }
    }

    private func recenterMap() {
        guard let origin = vm.origin else { return }
        let coords = vm.visibleLeads.prefix(10).compactMap { row -> CLLocationCoordinate2D? in
            guard let lat = row.lead.latitude, let lon = row.lead.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        // Pad the bounding rect so pins don't sit on the very edge of the map
        // tile — looks like they're spilling off otherwise.
        if coords.isEmpty {
            mapCameraPos = .region(MKCoordinateRegion(
                center: origin.coordinate,
                latitudinalMeters: 2_000,
                longitudinalMeters: 2_000
            ))
            return
        }
        var minLat = origin.coordinate.latitude, maxLat = origin.coordinate.latitude
        var minLon = origin.coordinate.longitude, maxLon = origin.coordinate.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.01)
        )
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        mapCameraPos = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: Tier filter

    private var tierPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DistanceTier.allCases) { tier in
                    let count = leadCount(in: tier)
                    let selected = vm.tier == tier
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { vm.tier = tier }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tier.icon).font(.caption.weight(.semibold))
                            Text(tier.rawValue).font(.caption.weight(.semibold))
                            Text("\(count)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(
                                    Capsule().fill(selected ? Color.white.opacity(0.25) : Brand.red.opacity(0.12))
                                )
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundColor(selected ? .white : .primary)
                        .background(
                            Capsule().fill(selected ? Brand.red : Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func leadCount(in tier: DistanceTier) -> Int {
        guard let cap = tier.radiusMeters else { return vm.leads.count }
        return vm.leads.filter { $0.distanceMeters <= cap }.count
    }

    // MARK: Cards

    @ViewBuilder
    private var leadCards: some View {
        let rows = vm.visibleLeads
        if rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "binoculars.fill").font(.system(size: 30)).foregroundColor(.secondary)
                Text("No leads inside \(vm.tier.rawValue.lowercased()).")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
        } else {
            VStack(spacing: 12) {
                ForEach(rows) { row in
                    NearbyLeadCard(row: row)
                }
            }
        }
    }

    // MARK: Loading / empty

    private var loadingState: some View {
        VStack(spacing: 14) {
            PulsingLocationDot()
            Text("Finding nearby leads…")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(systemImage: String, text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
            Button("Try again") { vm.refresh() }
                .buttonStyle(.borderedProminent)
                .tint(Brand.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card

private struct NearbyLeadCard: View {
    let row: NearbyLead

    var body: some View {
        NavigationLink {
            LeadDetailView(leadId: row.lead.id)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    BearingArrow(degrees: row.bearingDegrees)
                    ScoreAvatar(name: row.lead.displayName, grade: scoreTier(row.lead.score))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.lead.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        let subtitle = [row.lead.city, row.lead.state]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: ", ")
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            DistancePill(meters: row.distanceMeters)
                            if let status = row.lead.status, !status.isEmpty {
                                StatusChip(status: status)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)

                Divider().padding(.horizontal, 14)

                HStack(spacing: 0) {
                    QuickAction(label: "Call", systemImage: "phone.fill", enabled: !(row.lead.phone ?? "").isEmpty) {
                        guard let phone = row.lead.phone, !phone.isEmpty,
                              let url = URL(string: "tel://\(phone.filter { !$0.isWhitespace })") else { return }
                        UIApplication.shared.open(url)
                    }
                    Divider().frame(height: 22)
                    QuickAction(label: "WhatsApp", systemImage: "message.fill", enabled: !(row.lead.phone ?? "").isEmpty) {
                        guard let phone = row.lead.phone, !phone.isEmpty else { return }
                        let digits = phone.filter(\.isNumber)
                        guard let url = URL(string: "https://wa.me/\(digits)") else { return }
                        UIApplication.shared.open(url)
                    }
                    Divider().frame(height: 22)
                    QuickAction(label: "Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill", enabled: true) {
                        openInMaps()
                    }
                }
                .padding(.vertical, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator).opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func openInMaps() {
        guard let lat = row.lead.latitude, let lon = row.lead.longitude else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        item.name = row.lead.displayName
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

// MARK: - Subviews

private struct BearingArrow: View {
    let degrees: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            // Soft inner fill so the arrow reads even on dark mode.
            Circle()
                .fill(Brand.red.opacity(0.08))
            Image(systemName: "location.north.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(Brand.red)
                .rotationEffect(.degrees(degrees))
        }
        .frame(width: 36, height: 36)
        .accessibilityLabel("Bearing \(Int(degrees.rounded())) degrees")
    }
}

private struct ScoreAvatar: View {
    let name: String
    let grade: ScoreTier

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [grade.color, grade.color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            Text(initials)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if grade != .unknown {
                Text(grade.label)
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(grade.color)
                    .padding(3)
                    .background(Circle().fill(Color.white))
                    .offset(x: 14, y: -14)
            }
        }
        .frame(width: 42, height: 42)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

private struct DistancePill: View {
    let meters: CLLocationDistance
    var body: some View {
        let band = DistanceBand.of(meters)
        return HStack(spacing: 4) {
            Image(systemName: band.icon).font(.system(size: 10, weight: .semibold))
            Text(formatDistance(meters)).font(.caption2.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundColor(band.fg)
        .background(Capsule().fill(band.bg))
    }
}

private struct StatusChip: View {
    let status: String
    var body: some View {
        let label = status.replacingOccurrences(of: "_", with: " ").capitalized
        let color = statusColor(status)
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundColor(color)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

private struct QuickAction: View {
    let label: String
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                Text(label).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundColor(enabled ? Brand.red : .secondary)
            .opacity(enabled ? 1 : 0.5)
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}

private struct PulsingLocationDot: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle()
                .stroke(Brand.red.opacity(0.45), lineWidth: 2)
                .frame(width: 56, height: 56)
                .scaleEffect(pulse ? 1.6 : 1.0)
                .opacity(pulse ? 0 : 1)
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            Circle().fill(Brand.red).frame(width: 18, height: 18)
            Circle().fill(Color.white).frame(width: 6, height: 6)
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Helpers

private enum ScoreTier: Equatable {
    case a, b, c, d, unknown
    var label: String { switch self { case .a: "A"; case .b: "B"; case .c: "C"; case .d: "D"; case .unknown: "" } }
    var color: Color {
        switch self {
        case .a: return Color(red: 0.16, green: 0.74, blue: 0.50)   // green
        case .b: return Color(red: 0.20, green: 0.55, blue: 0.95)   // blue
        case .c: return Color(red: 0.96, green: 0.62, blue: 0.16)   // amber
        case .d: return Color(red: 0.93, green: 0.34, blue: 0.30)   // red
        case .unknown: return Color(.systemGray2)
        }
    }
}

private func scoreTier(_ score: Double?) -> ScoreTier {
    guard let s = score else { return .unknown }
    switch s {
    case 80...: return .a
    case 60..<80: return .b
    case 40..<60: return .c
    default: return .d
    }
}

private enum DistanceBand {
    case walk, near, drive, far
    static func of(_ meters: CLLocationDistance) -> DistanceBand {
        switch meters {
        case ..<1_000: return .walk
        case ..<5_000: return .near
        case ..<25_000: return .drive
        default: return .far
        }
    }
    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .near: return "bicycle"
        case .drive: return "car.fill"
        case .far: return "airplane"
        }
    }
    var fg: Color {
        switch self {
        case .walk: return Color(red: 0.05, green: 0.55, blue: 0.30)
        case .near: return Color(red: 0.15, green: 0.45, blue: 0.85)
        case .drive: return Color(red: 0.75, green: 0.45, blue: 0.05)
        case .far:  return Color(red: 0.70, green: 0.20, blue: 0.20)
        }
    }
    var bg: Color { fg.opacity(0.12) }
}

private func statusColor(_ status: String) -> Color {
    switch status.lowercased() {
    case "new":         return Color(red: 0.20, green: 0.55, blue: 0.95)
    case "working":     return Color(red: 0.96, green: 0.62, blue: 0.16)
    case "qualified":   return Color(red: 0.16, green: 0.74, blue: 0.50)
    case "unqualified", "lost": return Color(red: 0.93, green: 0.34, blue: 0.30)
    case "converted":   return Color(red: 0.55, green: 0.30, blue: 0.95)
    default:            return Color(.systemGray)
    }
}

private func formatDistance(_ meters: CLLocationDistance) -> String {
    if meters < 1_000 { return "\(Int(meters)) m" }
    return String(format: "%.1f km", meters / 1_000.0)
}
