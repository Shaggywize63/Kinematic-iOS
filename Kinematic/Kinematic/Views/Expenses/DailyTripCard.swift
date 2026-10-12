import SwiftUI
import Combine

// "Today's travel" on the Expenses tab — now a READ-ONLY summary of the two-step daily odometer trip. The capture
// moved into the attendance check-in / check-out flow (OdometerCaptureSheet / OdometerCaptureModel): the rep records
// the START odometer when they check in and the END when they check out. This card only reflects where that trip has
// got to today and links into the day's claim; there are no capture controls here any more.
//
// Still gated on ExpenseLogic.dailyTripOn (+ the server's `enabled`) exactly as before, so only opted-in clients see
// it and every other client is unchanged.

// MARK: - Model

@MainActor
final class DailyTripModel: ObservableObject {
    @Published var response: OdometerTripResponse?
    @Published var loaded = false
    @Published var loadError: String?

    private let api = ExpensesAPI.shared

    var trip: OdometerTrip? { response?.trip }
    /// The server's own gate — the card renders nothing unless this is true, even if the policy flag was stale.
    var enabled: Bool { response?.enabled == true }
    var status: OdometerTripStatus { OdometerTripLogic.status(trip) }
    var vehicles: [ExpenseVehicleRate] { ExpenseLogic.dedupeVehicles(response?.vehicle_rates) }

    func load() async {
        loadError = nil
        do { response = try await api.odometerTrip() }
        catch { loadError = error.localizedDescription }
        loaded = true
    }
}

// MARK: - The card (read-only)

struct DailyTripCard: View {
    @ObservedObject var model: DailyTripModel
    let currency: String
    /// Open the day's claim (Review & submit / View).
    let onOpenClaim: (String) -> Void

    private var vehicles: [ExpenseVehicleRate] { model.vehicles }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today's travel", systemImage: "car.fill").font(.headline)
            switch model.status {
            case .none:   notStarted
            case .open:   started
            case .closed: closed
            }
        }
        .padding(.vertical, 4)
    }

    // ── none → nothing recorded yet today ─────────────────────────────────────

    private var notStarted: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No travel recorded yet today.").font(.subheadline).foregroundColor(.secondary)
            hint("Record your start odometer at check-in — you'll add the end reading when you check out.")
        }
    }

    // ── open → start recorded, waiting on check-out ───────────────────────────

    @ViewBuilder private var started: some View {
        if let t = model.trip {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Day started", systemImage: "checkmark.circle.fill").font(.subheadline).bold().foregroundColor(.green)
                    Spacer()
                    if let s = t.odometer_start { Text("\(ExpenseLogic.trimNumber(s)) km").font(.subheadline).bold() }
                }
                let bits = [t.vehicle_type.flatMap { $0.isEmpty ? nil : ExpenseLogic.vehicleName($0, in: vehicles) },
                            ExpenseLogic.shortDate(t.date)].compactMap { $0 }
                if !bits.isEmpty { Text(bits.joined(separator: " · ")).font(.caption).foregroundColor(.secondary) }
                hint("Record your end odometer when you check out to log today's travel.")
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // ── closed → completed trip ───────────────────────────────────────────────

    @ViewBuilder private var closed: some View {
        if let t = model.trip {
            VStack(alignment: .leading, spacing: 10) {
                Label("Today's travel recorded", systemImage: "checkmark.seal.fill").font(.subheadline).bold().foregroundColor(.green)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Odometer").font(.caption).foregroundColor(.secondary)
                        Text(t.readingsText).bold()
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Distance").font(.caption).foregroundColor(.secondary)
                        Text(t.distance_km.map { "\(ExpenseLogic.trimNumber($0)) km" } ?? "—").bold()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Amount").font(.caption).foregroundColor(.secondary)
                        Text(expenseMoney(t.amount, currency)).bold()
                    }
                }
                if let v = t.vehicle_type, !v.isEmpty {
                    Text(ExpenseLogic.vehicleName(v, in: vehicles)).font(.caption).foregroundColor(.secondary)
                }
                Button(OdometerTripLogic.reviewButtonLabel(claimStatus: t.claim_status)) {
                    if !t.claim_id.isEmpty { onOpenClaim(t.claim_id) }
                }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                .disabled(t.claim_id.isEmpty)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func hint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle").font(.caption2).foregroundColor(.secondary).padding(.top, 2)
            Text(text).font(.caption).foregroundColor(.secondary)
        }
    }
}
