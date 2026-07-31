//
//  PlanogramCaptureView.swift
//  Kinematic
//
//  Field-rep capture flow with an AR-style alignment overlay so the AI
//  receives a consistent, well-framed shelf image.
//

import SwiftUI
import Combine
import CoreMotion

struct PlanogramCaptureView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = PlanogramCaptureViewModel()
    @State private var showCamera = false
    @State private var showResult = false

    /// Pass these in from the parent (e.g. visit context).
    let storeId: String?
    let visitId: String?
    let planogramId: String?

    private let motion = CMMotionManager()

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
            startMotion()
        }
        .onDisappear { motion.stopDeviceMotionUpdates() }
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
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                    .foregroundColor(alignmentColor.opacity(0.7))
                VStack(spacing: 12) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 54, weight: .light))
                        .foregroundColor(alignmentColor)
                    Text(alignmentHeadline)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(alignmentGuidance)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, minHeight: 320)

            AlignmentBar(score: vm.alignmentScore)
                .padding(.horizontal, 4)
            Text("A level, straight-on shot helps the AI read every SKU accurately. This is a guide — you can tap Capture at any time.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    /// Colour + copy that react to the live alignment score so the rep knows
    /// exactly how to hold the phone before shooting (green = ready).
    private var alignmentColor: Color {
        vm.alignmentScore >= 0.8 ? .green : vm.alignmentScore >= 0.5 ? .yellow : .red
    }
    private var alignmentHeadline: String {
        vm.alignmentScore >= 0.8 ? "Good alignment" : "Align your shot"
    }
    private var alignmentGuidance: String {
        if vm.alignmentScore >= 0.8 { return "Hold steady and tap Capture." }
        if vm.alignmentScore >= 0.5 { return "Almost there — straighten the phone so it's parallel to the shelf." }
        return "Hold your phone flat and square to the shelf — keep it level, not tilted."
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

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.15
        motion.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let d = data else { return }
            vm.updateAlignment(roll: d.attitude.roll, pitch: d.attitude.pitch)
        }
    }
}

// MARK: - Alignment bar

private struct AlignmentBar: View {
    let score: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Frame alignment")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(score * 100))%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * score))
                }
            }
            .frame(height: 6)
        }
    }

    private var color: Color {
        score >= 0.8 ? .green : score >= 0.5 ? .yellow : .red
    }
}
