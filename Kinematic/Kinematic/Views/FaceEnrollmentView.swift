//
//  FaceEnrollmentView.swift
//  Kinematic CRM
//
//  Supervised face enrolment (module face_attendance). Lets a rep explicitly
//  register / re-register their reference face instead of relying on the silent
//  auto-enrol on first check-in — useful to re-do a bad first capture or to
//  enrol before the first shift. Reached from Settings, gated on the module.
//
//  The camera frame is embedded ON-DEVICE (Vision + Core ML); only the opaque
//  float signature is sent to the backend — never the photo. Falls back
//  gracefully when no embedding model is bundled.
//

import SwiftUI
import UIKit

struct FaceEnrollmentView: View {
    @State private var enrolled: Bool? = nil     // nil = still loading
    @State private var available = true          // a real embedding model is bundled
    @State private var showCamera = false
    @State private var captured: UIImage?
    @State private var busy = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        List {
            Section {
                statusRow
            } footer: {
                Text("Your face is matched on your phone at check-in. Only an anonymous mathematical signature is stored — never your photo.")
            }

            if available {
                Section {
                    Button {
                        message = nil
                        showCamera = true
                    } label: {
                        Label(enrolled == true ? "Re-enroll my face" : "Enroll my face",
                              systemImage: "camera.viewfinder")
                    }
                    .disabled(busy)
                }
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(messageIsError ? .red : .green)
                }
            }
        }
        .navigationTitle("Face Enrollment")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStatus() }
        .sheet(isPresented: $showCamera, onDismiss: {
            // UIImage isn't Equatable, so we react on dismiss rather than onChange.
            if let img = captured { Task { await enroll(img) } }
        }) {
            ImagePicker(image: $captured, sourceType: .camera, cameraDevice: .front)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder private var statusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 26))
                .foregroundColor(statusColor)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.headline)
                Text(statusSubtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if busy { ProgressView() }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        if !available { return "exclamationmark.triangle" }
        switch enrolled {
        case .some(true):  return "checkmark.seal.fill"
        case .some(false): return "person.crop.circle.badge.questionmark"
        case .none:        return "hourglass"
        }
    }
    private var statusColor: Color {
        if !available { return .orange }
        return enrolled == true ? .green : .secondary
    }
    private var statusTitle: String {
        if !available { return "Not available on this build" }
        switch enrolled {
        case .some(true):  return "Face enrolled"
        case .some(false): return "Not enrolled yet"
        case .none:        return "Checking…"
        }
    }
    private var statusSubtitle: String {
        if !available { return "Face recognition needs the bundled model. A plain selfie is used instead." }
        switch enrolled {
        case .some(true):  return "Your check-ins are matched against this reference."
        case .some(false): return "Enroll now, or it happens automatically on your first check-in."
        case .none:        return "Fetching your enrolment status."
        }
    }

    private func loadStatus() async {
        available = await FaceRecognition.shared.isAvailable
        guard available else { enrolled = false; return }
        let ref = await KinematicRepository.shared.fetchFaceEnrollment()
        enrolled = (ref != nil)
    }

    private func enroll(_ image: UIImage) async {
        busy = true
        message = nil
        defer { busy = false; captured = nil }

        switch await FaceRecognition.shared.embed(image) {
        case .success(let vec, let mid):
            let ok = await KinematicRepository.shared.enrollFace(embedding: vec, modelId: mid, selfieUrl: nil, quality: nil)
            if ok {
                enrolled = true
                messageIsError = false
                message = "Face enrolled successfully."
            } else {
                messageIsError = true
                message = "Couldn't save your enrolment. Please check your connection and try again."
            }
        case .quality(let issue):
            messageIsError = true
            message = issue.friendly
        case .modelUnavailable:
            available = false
            messageIsError = true
            message = "Face recognition isn't available on this build."
        }
    }
}
