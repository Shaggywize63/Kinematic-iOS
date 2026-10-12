//
//  OdometerCaptureModel.swift
//  Kinematic
//
//  State behind the two-step daily odometer trip, now captured in the attendance flow: the START odometer right after
//  a check-in reaches the server, the END right after the final check-out. The attendance view model calls
//  `onCheckIn` / `onCheckOut` at its single success chokepoint; this model confirms eligibility (the policy opts in via
//  `ExpenseLogic.dailyTripOn` AND the server's `odometer-trip` reply is `enabled` with the right status) and, only
//  then, raises `request` to show the sheet. The sheet is OPTIONAL and skippable — it never blocks attendance.
//
//  Opt-in by DATA, and idle for everyone else: the policy is not even fetched unless the client has the expenses
//  module, and nothing is shown unless the resolved policy is a daily-trip policy. All of the capture pipeline
//  (camera + OCR, upload with the store-only fallback) is reused from the combined odometer editor via
//  `OdometerCaptureSheet` / `OdometerCaptureField`; the start/end endpoints are unchanged.
//

import Foundation
import Combine

/// One showing of the capture sheet (START after check-in, END after check-out). Identifiable so the host presents it
/// with `.sheet(item:)`, the way the Clock-In question is hosted.
struct OdometerCaptureRequest: Identifiable {
    let id = UUID()
    let mode: OdometerCaptureMode
    let vehicleRates: [ExpenseVehicleRate]
    /// The vehicle to pre-select on START (nil → the rep picks).
    let soleVehicle: String?
    let photosRequired: Bool
    let cameraOnly: Bool
    let currency: String
    /// The start reading already on file (END only) — shown, and used to flag an end below it.
    let recordedStart: Double?
    /// The India day the trip is for, sent to start/end so GET and the write agree.
    let date: String?
}

/// The brief confirmation after a successful END: "Travel recorded — ₹468 · 52 km", with the priced claim to open.
struct OdometerEndNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let claimId: String
}

@MainActor
final class OdometerCaptureModel: ObservableObject {

    static let shared = OdometerCaptureModel()

    /// Non-nil while the capture sheet should be on screen.
    @Published var request: OdometerCaptureRequest? = nil
    /// True while the start/end call is in flight.
    @Published var busy = false
    /// A one-off message (a validation error the server wrote for the user).
    @Published var notice: String? = nil
    /// Set after a successful END — the "Travel recorded" confirmation, linking to the claim.
    @Published var endNotice: OdometerEndNotice? = nil

    private let api = ExpensesAPI.shared

    private var policy: ExpensePolicy? = nil
    private var policyTriedAt: Date? = nil
    private var heldFor: String? = nil

    /// A failed policy fetch is not retried more often than this.
    private let policyRetry: TimeInterval = 60

    private init() {}

    // MARK: whose state is this

    private var currentUserId: String? {
        let t = (Session.currentUser?.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Forget everything held (sign-out, or a different person signed in).
    func reset() {
        policy = nil
        policyTriedAt = nil
        request = nil
        busy = false
        notice = nil
        endNotice = nil
    }

    private func syncUser() {
        let uid = currentUserId
        if uid != heldFor {
            reset()
            heldFor = uid
        }
    }

    // MARK: entry points (called by AttendanceViewModel on a punch that reached the server)

    /// Which punch raised the capture — the mode is then decided from the day's trip status.
    private enum Phase { case checkIn, checkOut }

    /// A check-in just reached the server: offer the START capture when the policy opts in and no trip has begun today.
    func onCheckIn(date: String?) {
        Task { await evaluate(phase: .checkIn, day: date) }
    }

    /// The final check-out just reached the server: offer the END capture when the day's trip is open, or — when no
    /// start was recorded at check-in — the COMBINED fallback so the whole trip can still be logged.
    func onCheckOut(date: String?) {
        Task { await evaluate(phase: .checkOut, day: date) }
    }

    // MARK: eligibility

    private func ensurePolicy() async {
        if policy != nil { return }
        if let tried = policyTriedAt, Date().timeIntervalSince(tried) < policyRetry { return }
        policyTriedAt = Date()
        let fetched = try? await api.policy()
        policy = ExpenseLogic.policyAfterRefresh(current: policy, fetched: fetched)
    }

    private func evaluate(phase: Phase, day: String?) async {
        syncUser()
        let uid = currentUserId
        guard uid != nil else { return }
        // The expenses module must be on for this client, and a sheet must not already be up.
        guard ClientFeatures.showsExpenses, request == nil else { return }
        await ensurePolicy()
        // Somebody else signed in while the policy was being fetched.
        guard uid == currentUserId else { return }
        guard ExpenseLogic.dailyTripOn(policy?.rules) else { return }

        let resp: OdometerTripResponse
        do { resp = try await api.odometerTrip(date: day) } catch { return }
        // The server's own gate (even if the policy flag was stale) and the status decide whether — and how — to offer.
        guard uid == currentUserId, resp.enabled, request == nil else { return }

        // Decide the capture from where the day's trip has got to:
        //  • check-in  → START only when nothing has begun yet.
        //  • check-out → END when a start is already on file; COMBINED (start + end at once) when none was recorded;
        //                nothing once the trip is already closed.
        let status = OdometerTripLogic.status(resp.trip)
        let mode: OdometerCaptureMode?
        switch phase {
        case .checkIn:
            mode = status == .none ? .start : nil
        case .checkOut:
            if status == .open { mode = .end }
            else if status == .none { mode = .combined }
            else { mode = nil }
        }
        guard let mode else { return }

        let vehicles = ExpenseLogic.dedupeVehicles(resp.vehicle_rates)
        request = OdometerCaptureRequest(
            mode: mode,
            vehicleRates: vehicles,
            soleVehicle: OdometerTripLogic.defaultVehicle(soleVehicle: resp.sole_vehicle, vehicleRates: vehicles),
            photosRequired: resp.photos_required,
            cameraOnly: resp.camera_only,
            currency: policy?.currency ?? "INR",
            recordedStart: mode == .end ? resp.trip?.odometer_start : nil,
            date: day
        )
    }

    // MARK: the sheet's callbacks

    /// Upload an odometer photo exactly as the combined editor does: read the number off it when the policy reads
    /// odometers (`camera_only`), otherwise just store it. If the read step fails the photo is still stored — the
    /// photo matters more than the auto-read, which the rep can always type in.
    func uploadOdometer(data: Data) async -> (ExpenseUploadedReceipt?, String?) {
        let read = request?.cameraOnly == true
        do {
            return (try await api.uploadReceipt(data: data, filename: "odometer.jpg", mime: "image/jpeg",
                                                scan: read ? .odometer : .storeOnly), nil)
        } catch {
            if read {
                do { return (try await api.uploadReceipt(data: data, filename: "odometer.jpg", mime: "image/jpeg", scan: .storeOnly), nil) }
                catch { return (nil, error.localizedDescription) }
            }
            return (nil, error.localizedDescription)
        }
    }

    /// The rep pressed Save on the sheet. Records the start or end; on success the sheet closes (END also shows the
    /// "Travel recorded" confirmation). A validation refusal is shown and the sheet stays so the rep can fix it.
    func complete(request req: OdometerCaptureRequest, vehicleType: String?, reading: Double, photoRef: String?) async {
        if busy { return }
        busy = true
        defer { busy = false }
        func trimmed(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        do {
            if req.mode == .start {
                let input = OdometerTripStartInput(odometer_start: reading, vehicle_type: trimmed(vehicleType),
                                                   start_photo_url: trimmed(photoRef), date: req.date)
                _ = try await api.startOdometerTrip(input)
                request = nil
            } else {
                let input = OdometerTripEndInput(odometer_end: reading, end_photo_url: trimmed(photoRef), date: req.date)
                let resp = try await api.endOdometerTrip(input)
                let note = Self.endNotice(from: resp, currency: req.currency)
                request = nil
                // Let the sheet finish dismissing before the confirmation alert comes up (same as the travel prompt).
                try? await Task.sleep(nanoseconds: 450_000_000)
                endNotice = note
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    /// The rep saved the COMBINED fallback (check-out with no start on file): record the start, then the end, against
    /// the same day — reusing the two existing endpoints so the day's claim is built and priced exactly as the normal
    /// two-step flow does. On success the sheet closes and the "Travel recorded" confirmation follows.
    func completeCombined(request req: OdometerCaptureRequest, vehicleType: String?,
                          start: Double, startPhoto: String?, end: Double, endPhoto: String?) async {
        if busy { return }
        busy = true
        defer { busy = false }
        func trimmed(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        do {
            _ = try await api.startOdometerTrip(OdometerTripStartInput(
                odometer_start: start, vehicle_type: trimmed(vehicleType), start_photo_url: trimmed(startPhoto), date: req.date))
            let resp = try await api.endOdometerTrip(OdometerTripEndInput(
                odometer_end: end, end_photo_url: trimmed(endPhoto), date: req.date))
            let note = Self.endNotice(from: resp, currency: req.currency)
            request = nil
            // Let the sheet finish dismissing before the confirmation alert comes up (same as the END flow).
            try? await Task.sleep(nanoseconds: 450_000_000)
            endNotice = note
        } catch {
            notice = error.localizedDescription
        }
    }

    /// The rep skipped (or dismissed) the sheet: attendance carries on, nothing is recorded.
    func skip() {
        request = nil
    }

    /// Build the "Travel recorded — ₹X · Y km" confirmation from the `/end` reply (the closed, priced trip + claim).
    private static func endNotice(from resp: OdometerTripResponse, currency: String) -> OdometerEndNotice? {
        let cur = resp.claim?.currency ?? currency
        let amount = resp.trip?.amount ?? resp.claim?.total_amount ?? 0
        let claimId = (resp.trip?.claim_id).flatMap { $0.isEmpty ? nil : $0 } ?? resp.claim?.id ?? ""
        var message = "Travel recorded — \(ExpenseLogic.money(amount, cur))"
        if let km = resp.trip?.distance_km { message += " · \(ExpenseLogic.trimNumber(km)) km" }
        return OdometerEndNotice(title: "Travel recorded", message: message, claimId: claimId)
    }
}
