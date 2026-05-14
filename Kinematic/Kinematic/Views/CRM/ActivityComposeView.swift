import SwiftUI

struct ActivityComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var type = "call"
    @State private var subject = ""
    @State private var desc = ""

    // Image attachment state — mirrors the web activity composer.
    @State private var pickedImage: UIImage? = nil
    @State private var showCameraSheet: Bool = false
    @State private var showLibrarySheet: Bool = false
    @State private var uploading: Bool = false
    @State private var imageUrl: String? = nil
    @State private var showSourceSheet: Bool = false

    /// Callback now also receives an optional `imageUrl` for the uploaded photo.
    let onSubmit: (String, String, String, String?) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(["call", "email", "meeting", "note", "task"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }.pickerStyle(.segmented)
                }
                Section("Details") {
                    TextField("Subject", text: $subject)
                    TextField("Description", text: $desc, axis: .vertical).lineLimit(3...6)
                }
                Section("Attachment") {
                    if let img = pickedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(10)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    pickedImage = nil
                                    imageUrl = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Circle().fill(Color.black.opacity(0.55)))
                                }
                                .padding(8)
                            }
                            .overlay {
                                if uploading {
                                    ZStack {
                                        Color.black.opacity(0.35).cornerRadius(10)
                                        ProgressView().tint(.white)
                                    }
                                }
                            }
                    } else {
                        Button {
                            showSourceSheet = true
                        } label: {
                            Label("Attach image", systemImage: "photo.badge.plus")
                        }
                    }
                }
            }
            .navigationTitle("Log Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        Task {
                            await onSubmit(type, subject, desc, imageUrl)
                            dismiss()
                        }
                    }.disabled(subject.isEmpty || uploading)
                }
            }
            .confirmationDialog("Attach image", isPresented: $showSourceSheet, titleVisibility: .visible) {
                Button("Take photo") { showCameraSheet = true }
                Button("Choose from library") { showLibrarySheet = true }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showCameraSheet) {
                ImagePicker(image: $pickedImage, sourceType: .camera, cameraDevice: .rear)
            }
            .sheet(isPresented: $showLibrarySheet) {
                ImagePicker(image: $pickedImage, sourceType: .photoLibrary)
            }
            .onChange(of: pickedImage) { _, newImage in
                guard let img = newImage else { return }
                Task { await upload(image: img) }
            }
        }
    }

    private func upload(image: UIImage) async {
        uploading = true
        defer { uploading = false }
        // Reuses the existing /upload/activity_form bucket already wired
        // for form attachments. Returns a public URL on success or nil on
        // any failure (user can re-attempt by removing + re-attaching).
        imageUrl = await KinematicRepository.shared.uploadImage(image: image, type: "activity_form")
    }
}
