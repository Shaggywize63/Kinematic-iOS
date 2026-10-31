//
//  PlanogramCaptureView.swift
//  Kinematic
//
//  Field-rep capture flow: add one or more shelf photos (camera or gallery,
//  multi-select) and run AI analysis on each. No forced "frame the shelf" step.
//

import SwiftUI
import Combine
import PhotosUI

struct PlanogramCaptureView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = PlanogramCaptureViewModel()
    @State private var showCamera = false
    @State private var cameraImage: UIImage? = nil
    @State private var pickerItems: [PhotosPickerItem] = []
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
                if vm.images.isEmpty {
                    placeholder
                } else {
                    thumbnails
                }
                addButtons
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
            ImagePicker(image: $cameraImage, sourceType: .camera, cameraDevice: .rear)
        }
        .onChange(of: cameraImage) { _, img in
            if let img {
                vm.addImages([img])
                cameraImage = nil
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        loaded.append(img)
                    }
                }
                await MainActor.run {
                    vm.addImages(loaded)
                    pickerItems = []
                }
            }
        }
        .onReceive(vm.$phase) { phase in
            if case .complete = phase { showResult = true }
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
            Text("Add shelf photos — camera or gallery, as many as you need.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 54, weight: .light))
                    .foregroundColor(.white.opacity(0.85))
                Text("No photos yet")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text("Take photos of the shelf or pick them from your gallery. You can add more than one.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var thumbnails: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(Array(vm.images.enumerated()), id: \.offset) { index, img in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 100)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button {
                            vm.removeImage(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                        .padding(5)
                        .disabled(isUploading)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 320)
    }

    private var addButtons: some View {
        HStack(spacing: 12) {
            Button {
                showCamera = true
            } label: {
                Label("Camera", systemImage: "camera.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isUploading)

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Photos", systemImage: "photo.stack.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isUploading)
        }
    }

    private var actions: some View {
        Button {
            if case .complete = vm.phase {
                dismiss()
            } else {
                Task { await vm.submitAll() }
            }
        } label: {
            HStack(spacing: 8) {
                if isUploading {
                    ProgressView().tint(.white)
                }
                Text(submitLabel).font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(vm.canSubmit || isComplete ? Color(red: 0.88, green: 0.12, blue: 0.17) : Color.gray.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!vm.canSubmit && !isComplete)
    }

    private var isComplete: Bool {
        if case .complete = vm.phase { return true }
        return false
    }

    private var isUploading: Bool {
        if case .uploading = vm.phase { return true }
        return false
    }

    private var submitLabel: String {
        switch vm.phase {
        case .uploading:
            return vm.batchTotal > 1 ? "Analyzing \(vm.batchDone) of \(vm.batchTotal)…" : "Analyzing…"
        case .complete:
            return "Done"
        default:
            let n = vm.images.count
            return n <= 1 ? "Submit & analyze" : "Analyze \(n) photos"
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
}
