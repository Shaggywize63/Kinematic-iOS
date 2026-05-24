//
//  AvatarPicker.swift
//  Kinematic
//
//  User-avatar picker + uploader. Modelled on `CRMPhotoSection` but
//  intentionally kept in `Views/` (not `Views/CRM/Components/`) because
//  this isn't a CRM concern — it edits the signed-in user's own profile
//  via `CRMService.uploadAvatar` + `updateMyProfile(avatarUrl:)`.
//
//  Surfaces as a sheet from the Profile screen and (optionally) the Side
//  Menu user header. The component is fully self-contained: parent only
//  decides when to present it. Once a successful upload+patch completes,
//  the new URL is written into `Session.currentUser` and the in-memory
//  app state is poked so dependent views (side-menu badge, profile chip)
//  rebuild on the next render pass.
//

import SwiftUI
import PhotosUI
import UIKit

/// Modal sheet content. Shows the current avatar (if any), Take Photo /
/// Choose from Library buttons, a Remove button, and progress + error UI.
/// Communicates results back via the `onUpdated` callback; parent typically
/// rebuilds from `Session.currentUser` rather than holding local state.
struct AvatarPicker: View {
    /// Called with the new avatar URL (or `nil` when removed) after the
    /// backend PATCH succeeds. Already persisted to `Session.currentUser`
    /// at this point — callers usually just trigger a view refresh.
    let onUpdated: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var currentUrl: String? = Session.currentUser?.avatarUrl
    @State private var pickedImage: UIImage?
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    avatarPreview
                        .padding(.top, 16)

                    if busy {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Saving…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    actionButtons

                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .navigationTitle("Profile Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
                AvatarLibraryPicker { img in
                    pickedImage = img
                    Task { await upload(img) }
                }
            }
        }
    }

    private var avatarPreview: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 132, height: 132)
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 4))
                .shadow(color: .red.opacity(0.3), radius: 12, x: 0, y: 6)

            if let urlString = currentUrl, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().tint(.white)
                    case .failure:
                        initialBadge
                    @unknown default:
                        initialBadge
                    }
                }
                .frame(width: 124, height: 124)
                .clipShape(Circle())
            } else {
                initialBadge
            }
        }
    }

    private var initialBadge: some View {
        Text(Session.currentUser?.name.prefix(1).uppercased() ?? "U")
            .font(.system(size: 56, weight: .black, design: .rounded))
            .foregroundColor(.white)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(busy)

            Button {
                showGallery = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(busy)

            if let urlString = currentUrl, !urlString.isEmpty {
                Button(role: .destructive) {
                    Task { await removeAvatar() }
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
        }
        .padding(.horizontal, 24)
    }

    @MainActor
    private func upload(_ image: UIImage) async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            // 1. Push the bytes to the avatars bucket.
            let url = try await CRMService.shared.uploadAvatar(image)
            // 2. Persist the URL on the user row via /auth/me. Regular
            //    users can't hit /users/:id, so this is the only path.
            let updated = try await CRMService.shared.updateMyProfile(avatarUrl: url)
            Session.currentUser = updated
            currentUrl = updated.avatarUrl
            onUpdated(updated.avatarUrl)
        } catch {
            errorMessage = error.localizedDescription
            pickedImage = nil
        }
    }

    @MainActor
    private func removeAvatar() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let updated = try await CRMService.shared.updateMyProfile(clearAvatar: true)
            Session.currentUser = updated
            currentUrl = updated.avatarUrl
            onUpdated(updated.avatarUrl)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Single-image PhotosPicker wrapper. Mirrors the helper in
/// `CRMPhotoSection.swift` but is duplicated here so the user-avatar
/// flow can ship without depending on a CRM-namespaced internal type.
private struct AvatarLibraryPicker: UIViewControllerRepresentable {
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

// MARK: - Shared rendering helper

/// Reusable circular avatar view. Renders `urlString` as an AsyncImage
/// when present, otherwise falls back to the initial-letter gradient
/// chip the app has used in side menu + profile from day one.
struct UserAvatarCircle: View {
    let urlString: String?
    let initial: String
    let diameter: CGFloat
    let fontSize: CGFloat
    var showStroke: Bool = true

    init(
        urlString: String?,
        name: String?,
        diameter: CGFloat,
        fontSize: CGFloat,
        showStroke: Bool = true
    ) {
        self.urlString = urlString
        self.initial = (name?.prefix(1).uppercased()).map { String($0) } ?? "U"
        self.diameter = diameter
        self.fontSize = fontSize
        self.showStroke = showStroke
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: diameter, height: diameter)

            if let s = urlString, !s.isEmpty, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().tint(.white)
                    case .failure:
                        Text(initial)
                            .font(.system(size: fontSize, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
            } else {
                Text(initial)
                    .font(.system(size: fontSize, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(showStroke ? 0.2 : 0), lineWidth: showStroke ? 2 : 0)
        )
    }
}
