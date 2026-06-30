import SwiftUI
import UIKit

/// "Scan business card → Create Lead" flow.
///
/// The rep takes a photo of a business card; we downscale it (long edge
/// ~1024px, JPEG ~0.7) so the base64 payload stays under the backend's
/// 2 MB body limit, POST it to `/crm/ai/scan-card`, then drop them onto
/// the normal lead-create form pre-filled with whatever the vision model
/// could read.
///
/// IMPORTANT: this view only ever *seeds values* into the existing
/// `LeadCreateView`. It adds no new render site for built-in fields and
/// does not bypass that form's `fieldOverrides` gating — fields the admin
/// hid stay hidden even if the card produced a value for them.
struct LeadScanCardView: View {
    @Environment(\.dismiss) private var dismiss

    /// Same submission closure `LeadsListView` already passes to
    /// `LeadCreateView` (routes through `LeadsViewModel.create`). Reused
    /// verbatim so the scanned lead saves through the identical
    /// online / offline-queue path.
    let onSubmit: ([String: Any]) async -> Bool

    private enum Phase {
        case capture          // show the camera / picker
        case scanning         // "Reading card…" progress
        case form(LeadCreatePrefill)   // present prefilled create form
    }

    @State private var phase: Phase = .capture
    @State private var pickedImage: UIImage?
    @State private var showCamera = true
    @State private var scanError: String?

    var body: some View {
        Group {
            switch phase {
            case .capture:
                capturePlaceholder
            case .scanning:
                scanningView
            case .form(let prefill):
                LeadCreateView(prefill: prefill) { body in
                    let ok = await onSubmit(body)
                    if ok { dismiss() }
                    return ok
                }
            }
        }
        // Rear camera by default (cards are held in front of the rep);
        // ImagePicker falls back to the photo library on the simulator.
        .sheet(isPresented: $showCamera, onDismiss: handlePickerDismiss) {
            ImagePicker(image: $pickedImage, sourceType: .camera, cameraDevice: .rear)
        }
        .alert(
            "Couldn't read the card",
            isPresented: Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })
        ) {
            Button("Retake") { resetToCapture() }
            Button("Enter manually") { phase = .form(LeadCreatePrefill()) }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text(scanError ?? "")
        }
    }

    // MARK: - Subviews

    private var capturePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 44))
                .foregroundColor(Brand.red)
            Text("Point the camera at a business card")
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Open camera") { showCamera = true }
                .buttonStyle(.borderedProminent)
                .tint(Brand.red)
        }
        .padding()
    }

    private var scanningView: some View {
        VStack(spacing: 18) {
            if let img = pickedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
            }
            ProgressView()
                .tint(Brand.red)
            Text("Reading card…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Flow

    /// Called when the camera/picker sheet dismisses. If a photo came back
    /// we kick off the scan; otherwise (rep cancelled) close the flow.
    private func handlePickerDismiss() {
        guard let image = pickedImage else {
            dismiss()
            return
        }
        phase = .scanning
        Task { await scan(image) }
    }

    private func scan(_ image: UIImage) async {
        // Downscale long edge to ~1024px and JPEG-encode at ~0.7 so the
        // base64 body stays well under the 2 MB backend limit.
        guard let data = KinematicRepository.compressForUpload(image, maxDim: 1024, targetKB: 1500),
              !data.isEmpty else {
            await MainActor.run { scanError = "Couldn't process the photo. Try again." }
            return
        }
        // Base64 WITHOUT a `data:` prefix — the endpoint wants raw base64.
        let base64 = data.base64EncodedString()

        let result = await KinematicRepository.shared.scanCard(imageBase64: base64)
        await MainActor.run {
            guard let r = result else {
                scanError = "We couldn't read that card. Retake the photo in good light, or enter the lead manually."
                return
            }
            phase = .form(LeadCreatePrefill(
                firstName: r.firstName,
                lastName: r.lastName,
                company: r.company,
                title: r.title,
                email: r.email,
                phone: r.phone
            ))
        }
    }

    private func resetToCapture() {
        pickedImage = nil
        phase = .capture
        showCamera = true
    }
}
