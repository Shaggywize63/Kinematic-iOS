import SwiftUI

struct ActivityComposeView: View {
    @Environment(\.dismiss) private var dismiss

    /// Optional prefill — call buttons pass `initialType="call"` and a
    /// subject like "Call with <Name>". Default to "call" type + empty
    /// subject so existing callers (e.g. ActivitiesView's "Add" button)
    /// keep their previous behavior.
    let initialType: String
    let initialSubject: String
    /// When true, the composer offers a lead picker (used by the global
    /// Activities "+", where there's no parent record). Detail screens pass
    /// false — they already supply the linked entity themselves.
    let allowLeadPicker: Bool
    /// Callback receives type, subject, description, optional imageUrl, the
    /// chosen "when" date, and an optional picked lead id (nil unless a lead
    /// was chosen via the picker).
    let onSubmit: (String, String, String, String?, Date, String?) async -> Void

    @State private var type: String
    @State private var subject: String
    @State private var desc: String = ""
    /// Picked lead (only when allowLeadPicker). Its phone shows in the row.
    @State private var selectedLead: Lead? = nil
    @State private var showLeadPicker = false
    /// Editable timestamp for the activity. Defaults to now so the common
    /// case (logging right after the action) is one tap. The picker is
    /// surfaced for every non-task type; tasks reuse this as `due_at`.
    @State private var when: Date = Date()

    // Image attachment state — mirrors the web activity composer.
    @State private var pickedImage: UIImage? = nil
    @State private var showCameraSheet: Bool = false
    @State private var showLibrarySheet: Bool = false
    @State private var uploading: Bool = false
    @State private var imageUrl: String? = nil
    @State private var showSourceSheet: Bool = false

    init(
        initialType: String = "call",
        initialSubject: String = "",
        allowLeadPicker: Bool = false,
        onSubmit: @escaping (String, String, String, String?, Date, String?) async -> Void
    ) {
        self.initialType = initialType
        self.initialSubject = initialSubject
        self.allowLeadPicker = allowLeadPicker
        self.onSubmit = onSubmit
        _type = State(initialValue: initialType)
        _subject = State(initialValue: initialSubject)
    }

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
                if allowLeadPicker {
                    Section("Linked lead") {
                        Button {
                            showLeadPicker = true
                        } label: {
                            HStack {
                                if let l = selectedLead {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(l.displayName).foregroundColor(.primary)
                                        if let phone = l.phone, !phone.isEmpty {
                                            Text(phone).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                } else {
                                    Text("Select a lead (optional)").foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Section("Details") {
                    TextField("Subject", text: $subject)
                    TextField("Description", text: $desc, axis: .vertical).lineLimit(3...6)
                    // Editable time. Default is now; tap to change. Reps
                    // who log a call after the fact want to back-date it,
                    // and tasks want a future due date.
                    DatePicker(
                        type == "task" ? "Due" : "When",
                        selection: $when,
                        displayedComponents: [.date, .hourAndMinute]
                    )
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
                            await onSubmit(type, subject, desc, imageUrl, when, selectedLead?.id)
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
            .sheet(isPresented: $showLeadPicker) {
                ActivityLeadPickerList { lead in selectedLead = lead }
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

/// Searchable lead list for attaching a lead to a global activity. Shows each
/// lead's name + phone so the rep can pick the right one. Server-side search
/// via `?q=` (matches name and phone).
private struct ActivityLeadPickerList: View {
    let onPick: (Lead) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var leads: [Lead] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List(leads) { lead in
                Button {
                    onPick(lead)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lead.displayName).foregroundColor(.primary)
                        if let phone = lead.phone, !phone.isEmpty {
                            Text(phone).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .overlay { if loading { ProgressView() } }
            .searchable(text: $search, prompt: "Search by name or phone")
            .onChange(of: search) { _ in Task { await load() } }
            .navigationTitle("Select lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        leads = (try? await CRMService.shared.listLeads(search: search.isEmpty ? nil : search, limit: 50)) ?? []
    }
}
