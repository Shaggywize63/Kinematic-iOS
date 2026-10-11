import SwiftUI
import PhotosUI

/// A "photo required" row for Collect Payment (the cheque) and Returns (the goods). The rep takes a photo or picks
/// one; it is uploaded through the backend's signed-upload flow (needs a connection) and `url` receives the public
/// URL the payment / return is then sent with. Mirrors the Android cheque-photo tile.
struct DistributionPhotoRow: View {
    /// The upload kind the backend accepts: "cheque" | "return".
    let kind: String
    let attachedTitle: String
    let missingTitle: String
    let hint: String
    @Binding var url: String?

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var cameraImage: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusLine
            actionButtons
            if let errorText = errorText {
                Text(errorText).font(.caption).foregroundColor(.red)
            }
        }
        .sheet(isPresented: $showCamera, onDismiss: handleCamera) {
            ImagePicker(image: $cameraImage, sourceType: .camera, cameraDevice: .rear)
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item = item else { return }
            Task { await loadFromLibrary(item) }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            Image(systemName: url == nil ? "camera" : "checkmark.seal.fill")
                .foregroundColor(url == nil ? Color.red : Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(uploading ? "Uploading…" : (url == nil ? missingTitle : attachedTitle))
                    .font(.subheadline.weight(.semibold))
                if url == nil && !uploading {
                    Text(hint).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if uploading { ProgressView() }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if ImagePicker.isCameraAvailable {
                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                    .buttonStyle(.bordered)
            }
            Button { showLibrary = true } label: { Label("Choose photo", systemImage: "photo") }
                .buttonStyle(.bordered)
        }
        .disabled(uploading)
    }

    private func handleCamera() {
        guard let image = cameraImage else { return }
        cameraImage = nil
        Task { await upload(image) }
    }

    private func loadFromLibrary(_ item: PhotosPickerItem) async {
        let data = try? await item.loadTransferable(type: Data.self)
        libraryItem = nil
        if let data = data, let image = UIImage(data: data) {
            await upload(image)
        } else {
            errorText = "Couldn't read that photo."
        }
    }

    private func upload(_ image: UIImage) async {
        uploading = true
        errorText = nil
        defer { uploading = false }
        guard let jpeg = DistributionUpload.jpegData(from: image) else {
            errorText = "Couldn't read that photo."
            return
        }
        if let uploaded = await DistributionUpload.uploadJPEG(jpeg, kind: kind) {
            url = uploaded
        } else {
            errorText = "Photo upload failed — check your connection and try again."
        }
    }
}
