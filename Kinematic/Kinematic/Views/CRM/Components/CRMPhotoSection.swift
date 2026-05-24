//
//  CRMPhotoSection.swift
//  Kinematic CRM
//
//  Reusable photo form section used by the Lead, Contact and Account
//  create / edit sheets. Lets the user pick from camera or gallery,
//  uploads to /api/v1/upload/photo via CRMService, and stores the
//  resulting URL in the parent's `photoUrl` binding.
//
//  Originally `LeadPhotoSection`; generalised when the same flow shipped
//  for Contacts and Accounts. The section title is parameterised so each
//  entity can use its own wording ("Lead Photo", "Contact Photo", etc.).
//

import SwiftUI
import PhotosUI
import UIKit

struct CRMPhotoSection: View {
    let title: String
    @Binding var photoUrl: String?

    @State private var pickedImage: UIImage?
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var uploading = false
    @State private var uploadError: String?

    init(title: String = "Photo (optional)", photoUrl: Binding<String?>) {
        self.title = title
        self._photoUrl = photoUrl
    }

    var body: some View {
        Section(title) {
            if let url = photoUrl, !url.isEmpty {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .empty:
                            ProgressView()
                        case .failure:
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .foregroundColor(.secondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()
                    Button(role: .destructive) {
                        photoUrl = nil
                        pickedImage = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(uploading)

                    Button {
                        showGallery = true
                    } label: {
                        Label("Upload from Device", systemImage: "photo.on.rectangle.angled")
                    }
                    .buttonStyle(.bordered)
                    .disabled(uploading)
                }
                if uploading {
                    HStack {
                        ProgressView()
                        Text("Uploading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if let err = uploadError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(
                image: Binding(
                    get: { pickedImage },
                    set: { img in
                        pickedImage = img
                        if let img { Task { await upload(img) } }
                    }
                ),
                sourceType: .camera
            )
        }
        .sheet(isPresented: $showGallery) {
            // PhotosPicker via the UIKit PHPicker wrapper used elsewhere in
            // the app for parity. Single-image variant: we read the first
            // selection and immediately upload.
            SinglePhotoPicker { img in
                pickedImage = img
                Task { await upload(img) }
            }
        }
    }

    @MainActor
    private func upload(_ image: UIImage) async {
        uploading = true
        uploadError = nil
        defer { uploading = false }
        do {
            let url = try await CRMService.shared.uploadPhoto(image)
            photoUrl = url
        } catch {
            uploadError = error.localizedDescription
            pickedImage = nil
        }
    }
}

/// Single-image variant of the PHPicker wrapper. Existing
/// `PHPickerRepresentable` in `ActivitySubmissionView` takes a `[UIImage]`
/// binding which is awkward here; this wraps the same picker for a single
/// image result delivered via callback so we never have to compare UIImage
/// identity in an `.onChange`.
private struct SinglePhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let img = object as? UIImage {
                    DispatchQueue.main.async { self.onPick(img) }
                }
            }
        }
    }
}
