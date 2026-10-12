import SwiftUI
import Combine
import PhotosUI
import UIKit

// The reusable odometer-capture sheet for the two-step daily trip, now driven from the attendance check-in /
// check-out flow (not a card the rep taps). START is offered right after a check-in reaches the server, END after the
// final check-out — both OPTIONAL and skippable, and both only for a client whose policy opts in (see
// ExpenseLogic.dailyTripOn + OdometerCaptureModel). The camera + auto-read pipeline is exactly what the combined
// odometer editor and the old card used: the shared ImagePicker (camera, library fallback OFF when the policy is
// camera-only), KinematicRepository.compressForUpload, the `scan=odometer` upload with a `.storeOnly` fallback, and
// the OCR reading dropped into an editable field (ExpenseOdometerScan / OdometerScanNote).

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
    /// Compress + upload the photo (and read the odometer on a camera-only policy). Supplied by the caller.
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

// MARK: - The reusable sheet

/// Which reading the sheet captures.
enum OdometerCaptureMode: Equatable {
    /// Morning (after check-in): pick the vehicle (when the policy lists more than one) and record the start odometer.
    case start
    /// Evening (after check-out): record the end odometer against the start already on file.
    case end
    /// Evening fallback (after check-out) when NO start was recorded at check-in: capture the whole trip at once —
    /// pick the vehicle, record both the start AND the end odometer, so the day's travel can still be logged.
    case combined
}

/// The capture sheet shown after a check-in (START — pick the vehicle, record the start odometer) or after the final
/// check-out (END — record the end odometer, which prices and closes the trip). Always skippable: it never blocks
/// attendance. Pure building blocks only — the gating and the start/end calls are the model's (OdometerCaptureModel).
struct OdometerCaptureSheet: View {
    let mode: OdometerCaptureMode
    let vehicleRates: [ExpenseVehicleRate]
    /// The vehicle to pre-select on START (the server's sole vehicle, else the only one, else nil → the rep picks).
    let soleVehicle: String?
    let photosRequired: Bool
    let cameraOnly: Bool
    let currency: String
    /// The start reading already recorded, for END — shown and used to flag an end below it.
    var recordedStart: Double? = nil
    /// True while the start/end call is in flight (from the model).
    let busy: Bool
    /// Upload + read the odometer photo (from the model).
    let upload: (Data) async -> (ExpenseUploadedReceipt?, String?)
    /// The rep saved a START or END: (vehicle on START, reading, the stored photo reference or nil).
    let onCapture: (_ vehicleType: String?, _ reading: Double, _ photoRef: String?) -> Void
    /// The rep saved the COMBINED fallback (start + end at check-out): vehicle, start reading + photo, end reading + photo.
    var onCaptureCombined: (_ vehicleType: String?, _ start: Double, _ startPhotoRef: String?, _ end: Double, _ endPhotoRef: String?) -> Void = { _, _, _, _, _ in }
    /// The rep skipped (or dismissed): attendance carries on, nothing is recorded.
    let onSkip: () -> Void

    @State private var reading = ""
    @State private var photo = ""
    @State private var vehicle = ""
    /// The END reading + photo, used only by the combined fallback (`reading`/`photo` hold the START there).
    @State private var endReading = ""
    @State private var endPhoto = ""
    @State private var localError: String?

    private var vehicles: [ExpenseVehicleRate] { vehicleRates }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    switch mode {
                    case .start:    startBody
                    case .end:      endBody
                    case .combined: combinedBody
                    }
                    if let e = localError { Text(e).font(.caption).foregroundColor(.red) }
                    saveButton
                    Button("Skip for now", action: onSkip)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(busy)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(mode == .start ? "Start your travel" : (mode == .combined ? "Log today's travel" : "End your travel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip", action: onSkip).disabled(busy) }
            }
            // Pre-select the policy's only vehicle once, when there is just one to choose.
            .task {
                if vehicle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let sole = OdometerTripLogic.defaultVehicle(soleVehicle: soleVehicle, vehicleRates: vehicles) {
                    vehicle = sole
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(busy)
    }

    private var header: some View {
        let title: String = {
            switch mode {
            case .start:    return "Record your start odometer"
            case .end:      return "Record your end odometer"
            case .combined: return "Record today's travel"
            }
        }()
        return Label(title, systemImage: "car.fill").font(.headline)
    }

    // ── START ─────────────────────────────────────────────────────────────────

    @ViewBuilder private var startBody: some View {
        Text("Record the odometer before you set out. You'll add the evening reading when you check out.")
            .font(.subheadline).foregroundColor(.secondary)
        if vehicles.count > 1 {
            Picker("Vehicle", selection: $vehicle) {
                Text("Choose a vehicle…").tag("")
                ForEach(vehicles) { v in Text("\(v.label) · \(expenseMoney(v.rate_per_km, currency))/km").tag(v.id) }
            }
            .pickerStyle(.menu)
        } else if let only = vehicles.first {
            HStack {
                Text("Vehicle").foregroundColor(.secondary)
                Spacer()
                Text("\(only.label) · \(expenseMoney(only.rate_per_km, currency))/km")
            }.font(.subheadline)
        }
        OdometerCaptureField(title: "Start odometer", reading: $reading, photoURL: $photo,
                             cameraOnly: cameraOnly, photosRequired: photosRequired,
                             upload: upload, onError: { localError = $0 })
        ForEach(startMissing, id: \.self) { m in hint(m.text) }
    }

    private var startMissing: [OdometerTripMissing] {
        OdometerTripLogic.startMissing(readingText: reading, vehicle: vehicle, photoURL: photo,
                                       photosRequired: photosRequired, vehicleRates: vehicles)
    }

    // ── END ───────────────────────────────────────────────────────────────────

    @ViewBuilder private var endBody: some View {
        if let s = recordedStart {
            HStack {
                Label("Day started", systemImage: "checkmark.circle.fill").font(.subheadline).bold().foregroundColor(.green)
                Spacer()
                Text("\(ExpenseLogic.trimNumber(s)) km").font(.subheadline).bold()
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        Text("Your day is done — record the odometer again to log today's travel.")
            .font(.subheadline).foregroundColor(.secondary)
        OdometerCaptureField(title: "End odometer", reading: $reading, photoURL: $photo,
                             cameraOnly: cameraOnly, photosRequired: photosRequired,
                             upload: upload, onError: { localError = $0 })
        if let km = liveDistance { Text("Distance so far: \(ExpenseLogic.trimNumber(km)) km").font(.caption).foregroundColor(.secondary) }
        ForEach(endMissing, id: \.self) { m in hint(m.text) }
    }

    private var endMissing: [OdometerTripMissing] {
        OdometerTripLogic.endMissing(readingText: reading, startReading: recordedStart,
                                     photoURL: photo, photosRequired: photosRequired)
    }

    private var liveDistance: Double? {
        OdometerTripLogic.distance(start: recordedStart, end: OdometerTripLogic.reading(reading))
    }

    // ── COMBINED (check-out fallback when no start was recorded at check-in) ────

    @ViewBuilder private var combinedBody: some View {
        Text("You didn't record a start reading at check-in, so log the whole trip now — the odometer before you set out and the reading now.")
            .font(.subheadline).foregroundColor(.secondary)
        if vehicles.count > 1 {
            Picker("Vehicle", selection: $vehicle) {
                Text("Choose a vehicle…").tag("")
                ForEach(vehicles) { v in Text("\(v.label) · \(expenseMoney(v.rate_per_km, currency))/km").tag(v.id) }
            }
            .pickerStyle(.menu)
        } else if let only = vehicles.first {
            HStack {
                Text("Vehicle").foregroundColor(.secondary)
                Spacer()
                Text("\(only.label) · \(expenseMoney(only.rate_per_km, currency))/km")
            }.font(.subheadline)
        }
        OdometerCaptureField(title: "Start odometer", reading: $reading, photoURL: $photo,
                             cameraOnly: cameraOnly, photosRequired: photosRequired,
                             upload: upload, onError: { localError = $0 })
        OdometerCaptureField(title: "End odometer", reading: $endReading, photoURL: $endPhoto,
                             cameraOnly: cameraOnly, photosRequired: photosRequired,
                             upload: upload, onError: { localError = $0 })
        if let km = combinedDistance { Text("Distance: \(ExpenseLogic.trimNumber(km)) km").font(.caption).foregroundColor(.secondary) }
        ForEach(combinedHints, id: \.self) { hint($0) }
    }

    private var combinedDistance: Double? {
        OdometerTripLogic.distance(start: OdometerTripLogic.reading(reading), end: OdometerTripLogic.reading(endReading))
    }

    /// Everything the combined fallback still needs, with distinct messages for the two readings/photos (so the list
    /// has no duplicate entries). Empty = ready to save.
    private var combinedHints: [String] {
        var out: [String] = []
        let start = OdometerTripLogic.reading(reading)
        let end = OdometerTripLogic.reading(endReading)
        if OdometerTripLogic.vehicleChoiceRequired(vehicles),
           vehicle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append("Choose a vehicle.") }
        if start == nil { out.append("Enter the start odometer reading.") }
        if end == nil { out.append("Enter the end odometer reading.") }
        if let s = start, let e = end, e < s { out.append(OdometerTripMissing.endBelowStart.text) }
        if photosRequired, photo.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Add a photo of the start odometer.") }
        if photosRequired, endPhoto.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Add a photo of the end odometer.") }
        return out
    }

    private var combinedReady: Bool { combinedHints.isEmpty }

    // ── Save ──────────────────────────────────────────────────────────────────

    private var missing: [OdometerTripMissing] { mode == .start ? startMissing : endMissing }

    private var saveDisabled: Bool {
        if busy { return true }
        return mode == .combined ? !combinedReady : !missing.isEmpty
    }

    private var saveLabel: String {
        switch mode {
        case .start:    return "Save start"
        case .end:      return "Save end"
        case .combined: return "Save travel"
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack { if busy { ProgressView() }; Text(saveLabel) }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(saveDisabled)
    }

    private func save() {
        let v = vehicle.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .combined {
            guard combinedReady,
                  let start = OdometerTripLogic.reading(reading),
                  let end = OdometerTripLogic.reading(endReading) else { return }
            let sp = photo.trimmingCharacters(in: .whitespacesAndNewlines)
            let ep = endPhoto.trimmingCharacters(in: .whitespacesAndNewlines)
            onCaptureCombined(v.isEmpty ? nil : v, start, sp.isEmpty ? nil : sp, end, ep.isEmpty ? nil : ep)
            return
        }
        guard let km = OdometerTripLogic.reading(reading), missing.isEmpty else { return }
        let photoRef = photo.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .start {
            onCapture(v.isEmpty ? nil : v, km, photoRef.isEmpty ? nil : photoRef)
        } else {
            onCapture(nil, km, photoRef.isEmpty ? nil : photoRef)
        }
    }

    private func hint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle").font(.caption2).foregroundColor(.secondary).padding(.top, 2)
            Text(text).font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - Host

/// Hosts the odometer-capture sheet at the root, the way `clockInTransportHost` hosts the Clock-In question — so the
/// START / END sheet appears reliably right after a punch, whatever screen the rep punched from. Nothing is drawn for
/// a client that has not opted in: the model raises `request` only after it has confirmed the policy and the server's
/// `enabled` gate. A small "Travel recorded" confirmation follows a successful END, linking to the priced claim.
struct OdometerCaptureHost: ViewModifier {
    @ObservedObject var model: OdometerCaptureModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.request) { request in
                OdometerCaptureSheet(
                    mode: request.mode,
                    vehicleRates: request.vehicleRates,
                    soleVehicle: request.soleVehicle,
                    photosRequired: request.photosRequired,
                    cameraOnly: request.cameraOnly,
                    currency: request.currency,
                    recordedStart: request.recordedStart,
                    busy: model.busy,
                    upload: { await model.uploadOdometer(data: $0) },
                    onCapture: { vehicle, reading, photo in
                        Task { await model.complete(request: request, vehicleType: vehicle, reading: reading, photoRef: photo) }
                    },
                    onCaptureCombined: { vehicle, start, startPhoto, end, endPhoto in
                        Task { await model.completeCombined(request: request, vehicleType: vehicle,
                                                            start: start, startPhoto: startPhoto, end: end, endPhoto: endPhoto) }
                    },
                    onSkip: { model.skip() }
                )
            }
            .alert("Today's travel", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                Button("OK", role: .cancel) { model.notice = nil }
            } message: { Text(model.notice ?? "") }
            .alert(model.endNotice?.title ?? "Travel recorded",
                   isPresented: Binding(get: { model.endNotice != nil }, set: { if !$0 { model.endNotice = nil } })) {
                if let note = model.endNotice, !note.claimId.isEmpty {
                    Button("View claim") {
                        let id = note.claimId
                        model.endNotice = nil
                        KiniAppState.shared.open(.expenseClaim(id))
                    }
                }
                Button("Done", role: .cancel) { model.endNotice = nil }
            } message: { Text(model.endNotice?.message ?? "") }
    }
}

extension View {
    /// See `OdometerCaptureHost`. Attach once, high in the view tree.
    func odometerCaptureHost(_ model: OdometerCaptureModel = .shared) -> some View {
        modifier(OdometerCaptureHost(model: model))
    }
}
