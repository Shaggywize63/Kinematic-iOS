//
//  PlanogramCaptureView.swift
//  Kinematic
//
//  Field-rep capture flow: frame the shelf and capture a photo for AI analysis.
//

import SwiftUI
import Combine

struct PlanogramCaptureView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = PlanogramCaptureViewModel()
    @State private var showCamera = false
    @State private var showResult = false

    /// Pass these in from the parent (e.g. visit context).
    let storeId: String?
    let visitId: String?
    let planogramId: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                header
                if let img = vm.capturedImage {
                    preview(image: img)
                } else {
                    placeholder
                }
                actions
                if case .failed(let msg) = vm.phase {
                    errorBanner(msg)
                }
            }
            .padding(20)
        }
        .onAppear {
            vm.storeId = storeId
            vm.visitId = visitId
            vm.planogramId = planogramId
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(image: bindingForCapturedImage(), sourceType: .camera, cameraDevice: .rear)
        }
        .sheet(isPresented: $showResult) {
            if case .complete(let resp) = vm.phase {
                PlanogramComplianceView(response: resp, image: vm.capturedImage)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shelf capture")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white)
            Text("Frame the shelf, hold steady, and tap capture.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                .foregroundColor(.white.opacity(0.25))
            VStack(spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 54, weight: .light))
                    .foregroundColor(.white.opacity(0.85))
                Text("Frame the shelf")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text("Fit the whole shelf in the frame, then tap Capture.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func preview(image: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Button {
                vm.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
            }
            .padding(12)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                vm.reset()
                showCamera = true
            } label: {
                Label(vm.capturedImage == nil ? "Capture" : "Retake",
                      systemImage: "camera.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Button {
                if case .complete = vm.phase {
                    dismiss()
                } else {
                    Task { await vm.submit(imageURL: "") }
                }
            } label: {
                HStack(spacing: 8) {
                    if case .uploading = vm.phase {
                        ProgressView().tint(.white)
                    }
                    Text(submitLabel).font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(vm.canSubmit || isComplete ? Color(red: 0.88, green: 0.12, blue: 0.17) : Color.gray.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!vm.canSubmit && !isComplete)
        }
    }

    private var isComplete: Bool {
        if case .complete = vm.phase { return true }
        return false
    }

    private var submitLabel: String {
        switch vm.phase {
        case .uploading:    return "Analyzing…"
        case .complete:     return "Done"
        default:            return "Submit"
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func bindingForCapturedImage() -> Binding<UIImage?> {
        Binding(
            get: { vm.capturedImage },
            set: { vm.capturedImage = $0 }
        )
    }
}
