import SwiftUI
import UIKit

/// Renders a `field_type == "image"` custom field on the create / edit forms:
/// capture a photo (camera) or pick one from the gallery, upload it via the
/// existing `/upload/photo` endpoint, and store the returned URL string in
/// `model.text[field_key]` — the same shape the web form persists, so the
/// value round-trips through `custom_fields` identically on every platform.
///
/// The admin's camera configuration (Settings → Custom Fields) arrives as
/// string tokens inside the def's `options` array — no schema change, and
/// builds that pre-date this feature never read `options` on image fields:
///   'camera_only' → hide the gallery button, capture must come from camera
///   'front'       → open the front camera (default: back)
struct ImageCustomFieldRow: View {
    let def: CRMCustomFieldDef
    @ObservedObject var model: CustomFieldsModel

    @State private var showCamera = false
    @State private var showGallery = false
    @State private var uploading = false
    @State private var uploadFailed = false
    /// Local preview of the just-captured shot — avoids a signed-URL
    /// round-trip to re-display an image we already have in memory.
    @State private var preview: UIImage?

    private var cameraOnly: Bool { def.options?.contains("camera_only") == true }
    private var cameraDevice: UIImagePickerController.CameraDevice {
        def.options?.contains("front") == true ? .front : .rear
    }
    private var storedUrl: String? {
        let v = model.text[def.fieldKey] ?? ""
        return v.isEmpty ? nil : v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(def.label)
                .font(.subheadline)

            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if storedUrl != nil {
                Label("Photo attached", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack(spacing: 10) {
                Button {
                    showCamera = true
                } label: {
                    Label(uploading ? "Uploading…" : "Take Photo", systemImage: "camera")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(uploading)

                if !cameraOnly {
                    Button {
                        showGallery = true
                    } label: {
                        Label("Gallery", systemImage: "photo.on.rectangle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(uploading)
                }

                if storedUrl != nil && !uploading {
                    Button(role: .destructive) {
                        model.text[def.fieldKey] = ""
                        preview = nil
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if uploadFailed {
                Text("Upload failed — check your connection and retry.")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showCamera) {
            SystemImagePicker(source: .camera, cameraDevice: cameraDevice) { image in
                if let image { Task { await upload(image) } }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showGallery) {
            SystemImagePicker(source: .photoLibrary, cameraDevice: .rear) { image in
                if let image { Task { await upload(image) } }
            }
            .ignoresSafeArea()
        }
    }

    private func upload(_ image: UIImage) async {
        uploading = true
        uploadFailed = false
        if let url = await KinematicRepository.shared.uploadImage(image: image, type: "photo") {
            model.text[def.fieldKey] = url
            preview = image
        } else {
            uploadFailed = true
        }
        uploading = false
    }
}

/// Thin UIImagePickerController wrapper. UIImagePickerController (rather than
/// PHPicker) is used for BOTH sources so one representable covers camera and
/// gallery, and because it's the only API that lets us honour the admin's
/// front/back camera choice (`cameraDevice`). Falls back to the photo library
/// when a camera isn't available (Simulator).
struct SystemImagePicker: UIViewControllerRepresentable {
    let source: UIImagePickerController.SourceType
    let cameraDevice: UIImagePickerController.CameraDevice
    let onPick: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if source == .camera, UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            if UIImagePickerController.isCameraDeviceAvailable(cameraDevice) {
                picker.cameraDevice = cameraDevice
            }
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SystemImagePicker
        init(_ parent: SystemImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            parent.onPick(image)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onPick(nil)
            parent.dismiss()
        }
    }
}
