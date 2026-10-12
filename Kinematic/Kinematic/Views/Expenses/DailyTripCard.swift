import SwiftUI
import Combine
import PhotosUI
import UIKit

// The two-step daily odometer trip ("Today's travel"), shown ABOVE the claims list only for clients whose policy
// opts in (see ExpenseLogic.dailyTripOn + the trip endpoint's `enabled`). A field rep records the START odometer in
// the morning and the END odometer in the evening — they cannot know the evening reading when they set out, which
// is why the combined before/after editor could not serve them. The combined editor is untouched for every other
// policy; this card is an addition.
//
// The camera + auto-read for each reading reuses exactly what the combined odometer editor uses: the shared
// ImagePicker (camera, library fallback OFF when the policy is camera-only), the `scan=odometer` receipt upload that
// returns the stored url and the OCR reading, and the OdometerScanNote / ExpenseOdometerScan model — see
// OdometerCaptureField below and ExpenseClaimEditorView.attachOdometer.

// MARK: - Model

@MainActor
final class DailyTripModel: ObservableObject {
    @Published var response: OdometerTripResponse?
    @Published var loaded = false
    @Published var loadError: String?
    @Published var busy = false
    /// One-off message (an error the server wrote for the user, e.g. a validation message).
    @Published var notice: String?

    private let api = ExpensesAPI.shared

    var trip: OdometerTrip? { response?.trip }
    /// The server's own gate — the card renders nothing unless this is true, even if the policy flag was stale.
    var enabled: Bool { response?.enabled == true }
    var status: OdometerTripStatus { OdometerTripLogic.status(trip) }
    var vehicles: [ExpenseVehicleRate] { ExpenseLogic.dedupeVehicles(response?.vehicle_rates) }
    /// A photo of the odometer is mandatory unless the policy turned it off.
    var photosRequired: Bool { response?.photos_required != false }
    /// Odometer photos only from the camera, and the number read from the photo (as for the combined editor).
    var cameraOnly: Bool { response?.camera_only == true }
    /// The vehicle to pre-select on the start step (nil → the rep picks).
    var soleVehicle: String? { OdometerTripLogic.defaultVehicle(soleVehicle: response?.sole_vehicle, vehicleRates: vehicles) }

    func load() async {
        loadError = nil
        do { response = try await api.odometerTrip() }
        catch { loadError = error.localizedDescription }
        loaded = true
    }

    /// Record the start reading. Returns true on success (the caller reloads and refreshes the claims list).
    func start(odometerStart: Double, vehicleType: String?, startPhotoURL: String?) async -> Bool {
        busy = true; defer { busy = false }
        func trimmed(_ s: String?) -> String? { let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        let input = OdometerTripStartInput(odometer_start: odometerStart,
                                           vehicle_type: trimmed(vehicleType),
                                           start_photo_url: trimmed(startPhotoURL),
                                           date: nil)
        do { response = try await api.startOdometerTrip(input); return true }
        catch { notice = error.localizedDescription; return false }
    }

    /// Record the end reading, which prices and closes the trip. Returns true on success.
    func end(odometerEnd: Double, endPhotoURL: String?) async -> Bool {
        busy = true; defer { busy = false }
        let ph = (endPhotoURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let input = OdometerTripEndInput(odometer_end: odometerEnd, end_photo_url: ph.isEmpty ? nil : ph, date: nil)
        do { response = try await api.endOdometerTrip(input); return true }
        catch { notice = error.localizedDescription; return false }
    }

    /// Upload an odometer photo exactly as the combined editor does: read the number off it when the policy reads
    /// odometers (`camera_only`), otherwise just store it. If the read step fails the photo is still stored — the
    /// photo matters more than the auto-read, which the rep can always type in.
    func uploadOdometer(data: Data) async -> (ExpenseUploadedReceipt?, String?) {
        let read = cameraOnly
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
}

// MARK: - A single odometer reading with its camera auto-read (reused for start and end)

/// One odometer reading: an editable number and the photo that backs it. On a camera-only policy the photo can only
/// be taken with the camera (no library) and the number is read off it and dropped into the field, still editable —
/// the same behaviour and building blocks as the combined odometer editor.
struct OdometerCaptureField: View {
    let title: String
    @Binding var reading: String
    /// The stored reference to send to the server (empty = no photo yet).
    @Binding var photoURL: String
    let cameraOnly: Bool
    let photosRequired: Bool
    /// Compress + upload the photo (and read the odometer on a camera-only policy). Supplied by the card's model.
    let upload: (Data) async -> (ExpenseUploadedReceipt?, String?)
    var onError: (String) -> Void = { _ in }

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var cameraImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var signedURL: String?
    @State private var uploading = false
    @State private var note: OdometerScanNote?
    @State private var viewing: ReceiptRef?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("\(title) (km)", text: $reading).keyboardType(.decimalPad)
            if let note = note {
                Text(note.text).font(.caption).foregroundColor(note == .unreadable ? .orange : .blue)
            }
            if uploading {
                HStack { ProgressView(); Text("Uploading the photo…").font(.subheadline) }
            } else if !photoURL.isEmpty {
                HStack(spacing: 10) {
                    Button { if let v = signedURL { viewing = ReceiptRef(url: v) } } label: { ReceiptThumbnail(url: signedURL) }
                        .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photo attached").font(.subheadline).bold()
                        Text("Tap the preview to view it").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    captureButton(label: "Retake")
                    Button {
                        photoURL = ""; signedURL = nil; note = nil
                    } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                        .buttonStyle(.borderless).accessibilityLabel("Remove photo")
                }
            } else {
                captureButton(label: photosRequired ? "Capture \(title.lowercased())" : "Capture \(title.lowercased()) (optional)")
            }
        }
        .sheet(isPresented: $showCamera, onDismiss: handleCamera) {
            // Camera-only never falls back to the photo library (matches the combined editor's odometer photos).
            ImagePicker(image: $cameraImage, sourceType: .camera, cameraDevice: .rear, allowLibraryFallback: !cameraOnly)
        }
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item = item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                photoItem = nil
                if let data = data, let image = UIImage(data: data) { await attach(image: image) }
                else { onError("Couldn't read that photo.") }
            }
        }
        .sheet(item: $viewing) { ReceiptViewerSheet(url: $0.url) }
    }

    @ViewBuilder private func captureButton(label: String) -> some View {
        if cameraOnly {
            Button { openCamera() } label: { Label(label, systemImage: "camera") }
                .buttonStyle(.borderless)
        } else {
            Menu {
                Button { openCamera() } label: { Label("Take a photo", systemImage: "camera") }
                Button { showLibrary = true } label: { Label("Choose a photo", systemImage: "photo.on.rectangle") }
            } label: { Label(label, systemImage: "camera") }
        }
    }

    private func openCamera() {
        guard ImagePicker.isCameraAvailable || !cameraOnly else {
            onError("This device has no camera available, so the odometer photo can't be taken.")
            return
        }
        showCamera = true
    }

    private func handleCamera() {
        guard let image = cameraImage else { return }
        cameraImage = nil
        Task { await attach(image: image) }
    }

    private func attach(image: UIImage) async {
        uploading = true
        guard let data = KinematicRepository.compressForUpload(image, maxDim: 1800, targetKB: 1500), !data.isEmpty else {
            uploading = false; onError("Couldn't read that photo."); return
        }
        if data.count > 10 * 1024 * 1024 { uploading = false; onError("That photo is larger than 10 MB."); return }
        let (result, error) = await upload(data)
        uploading = false
        guard let r = result else { onError(error ?? "Couldn't upload the photo."); return }
        photoURL = r.url
        signedURL = r.signed_url
        if cameraOnly {
            if let km = r.odometer?.reading, km.isFinite, km >= 0 {
                reading = ExpenseLogic.trimNumber(km)
                note = .read
            } else {
                note = .unreadable
            }
        }
    }
}

// MARK: - The card

struct DailyTripCard: View {
    @ObservedObject var model: DailyTripModel
    let currency: String
    /// Open the day's claim (Review & submit / View).
    let onOpenClaim: (String) -> Void
    /// Something changed on the server (start or end) — the claims list should refresh.
    let onChanged: () -> Void

    // Morning step
    @State private var startReading = ""
    @State private var startPhoto = ""
    @State private var vehicle = ""
    // Evening step
    @State private var endReading = ""
    @State private var endPhoto = ""

    private var vehicles: [ExpenseVehicleRate] { model.vehicles }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today's travel", systemImage: "car.fill").font(.headline)
            switch model.status {
            case .none:   startStep
            case .open:   endStep
            case .closed: closedStep
            }
        }
        .padding(.vertical, 4)
        // Pre-select the policy's only vehicle once the trip config has loaded (nil when there are several).
        .onChange(of: model.soleVehicle, initial: true) { _, sole in
            if vehicle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let sole = sole { vehicle = sole }
        }
        .alert("Today's travel", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }

    // ── none → Start your day ─────────────────────────────────────────────────

    private var startStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record the odometer before you set out. You'll add the evening reading when your day is done.")
                .font(.subheadline).foregroundColor(.secondary)
            if vehicles.count > 1 {
                Picker("Vehicle", selection: $vehicle) {
                    Text("Choose a vehicle…").tag("")
                    ForEach(vehicles) { v in Text("\(v.label) · \(expenseMoney(v.rate_per_km, currency))/km").tag(v.id) }
                }
            } else if let only = vehicles.first {
                HStack {
                    Text("Vehicle").foregroundColor(.secondary)
                    Spacer()
                    Text("\(only.label) · \(expenseMoney(only.rate_per_km, currency))/km")
                }.font(.subheadline)
            }
            OdometerCaptureField(title: "Start odometer", reading: $startReading, photoURL: $startPhoto,
                                 cameraOnly: model.cameraOnly, photosRequired: model.photosRequired,
                                 upload: { await model.uploadOdometer(data: $0) },
                                 onError: { model.notice = $0 })
            ForEach(startMissing, id: \.self) { m in hint(m.text) }
            Button {
                Task { await saveStart() }
            } label: {
                HStack { if model.busy { ProgressView() }; Text("Save start") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy || !startMissing.isEmpty)
        }
    }

    private var startMissing: [OdometerTripMissing] {
        OdometerTripLogic.startMissing(readingText: startReading, vehicle: vehicle, photoURL: startPhoto,
                                       photosRequired: model.photosRequired, vehicleRates: vehicles)
    }

    private func saveStart() async {
        guard let km = OdometerTripLogic.reading(startReading) else { return }
        let v = vehicle.trimmingCharacters(in: .whitespacesAndNewlines)
        if await model.start(odometerStart: km, vehicleType: v.isEmpty ? nil : v, startPhotoURL: startPhoto) {
            startReading = ""; startPhoto = ""
            onChanged()
        }
    }

    // ── open → End your day ───────────────────────────────────────────────────

    private var endStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = model.trip { recordedStart(t) }
            Text("When your day is done, record the odometer again.").font(.subheadline).foregroundColor(.secondary)
            OdometerCaptureField(title: "End odometer", reading: $endReading, photoURL: $endPhoto,
                                 cameraOnly: model.cameraOnly, photosRequired: model.photosRequired,
                                 upload: { await model.uploadOdometer(data: $0) },
                                 onError: { model.notice = $0 })
            if let km = liveEndDistance { Text("Distance so far: \(ExpenseLogic.trimNumber(km)) km").font(.caption).foregroundColor(.secondary) }
            ForEach(endMissing, id: \.self) { m in hint(m.text) }
            Button {
                Task { await saveEnd() }
            } label: {
                HStack { if model.busy { ProgressView() }; Text("Save end") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy || !endMissing.isEmpty)
        }
    }

    private var endMissing: [OdometerTripMissing] {
        OdometerTripLogic.endMissing(readingText: endReading, startReading: model.trip?.odometer_start,
                                     photoURL: endPhoto, photosRequired: model.photosRequired)
    }

    private var liveEndDistance: Double? {
        OdometerTripLogic.distance(start: model.trip?.odometer_start, end: OdometerTripLogic.reading(endReading))
    }

    private func saveEnd() async {
        guard let km = OdometerTripLogic.reading(endReading) else { return }
        if await model.end(odometerEnd: km, endPhotoURL: endPhoto) {
            endReading = ""; endPhoto = ""
            onChanged()
        }
    }

    @ViewBuilder private func recordedStart(_ t: OdometerTrip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Day started", systemImage: "checkmark.circle.fill").font(.subheadline).bold().foregroundColor(.green)
                Spacer()
                if let s = t.odometer_start { Text("\(ExpenseLogic.trimNumber(s)) km").font(.subheadline).bold() }
            }
            let bits = [t.vehicle_type.flatMap { $0.isEmpty ? nil : ExpenseLogic.vehicleName($0, in: vehicles) },
                        ExpenseLogic.shortDate(t.date)].compactMap { $0 }
            if !bits.isEmpty { Text(bits.joined(separator: " · ")).font(.caption).foregroundColor(.secondary) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // ── closed → completed trip ───────────────────────────────────────────────

    @ViewBuilder private var closedStep: some View {
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
