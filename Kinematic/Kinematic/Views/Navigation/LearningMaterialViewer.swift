import SwiftUI
import PDFKit
import AVKit
import UIKit

// In-app viewer for a Learning Hub material. PDF / image / video are rendered
// inside the app (no external browser). The backend serves a short-lived signed
// https URL in `fileUrl`, so the file is directly fetchable. Link / slides /
// document types are handled by the caller (opened externally) and never reach
// here.
struct LearningMaterialViewer: View {
    let material: LearningMaterial
    @Environment(\.dismiss) private var dismiss

    private var url: URL? { material.fileUrl.flatMap { URL(string: $0) } }

    var body: some View {
        NavigationStack {
            Group {
                if let url {
                    switch (material.type ?? "").lowercased() {
                    case "pdf":   LearningPDFViewer(url: url)
                    case "image": LearningImageViewer(url: url)
                    case "video": LearningVideoViewer(url: url)
                    default:      LearningViewerMessage(text: "This file type can't be previewed here.")
                    }
                } else {
                    LearningViewerMessage(text: "This material has no file attached.")
                }
            }
            .navigationTitle(material.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - PDF

private struct LearningPDFViewer: View {
    let url: URL
    @State private var localURL: URL?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if let localURL {
                PDFKitView(url: localURL)
            } else if failed {
                LearningViewerMessage(text: "Couldn't load this PDF.")
            } else {
                ProgressView("Loading…")
            }
        }
        .task { await load() }
    }

    // Download to a temp file first — more reliable than PDFDocument(url:) over
    // the network, and lets us surface a clean error state on failure.
    private func load() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                await MainActor.run { failed = true }
                return
            }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")
            try data.write(to: tmp, options: .atomic)
            await MainActor.run { localURL = tmp }
        } catch {
            await MainActor.run { failed = true }
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil {
            uiView.document = PDFDocument(url: url)
        }
    }
}

// MARK: - Image

private struct LearningImageViewer: View {
    let url: URL
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in scale = max(1, value) }
                                .onEnded { _ in withAnimation { scale = max(1, scale) } }
                        )
                case .failure:
                    LearningViewerMessage(text: "Couldn't load this image.")
                default:
                    ProgressView().tint(.white)
                }
            }
        }
    }
}

// MARK: - Video

private struct LearningVideoViewer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear { if player == nil { player = AVPlayer(url: url) } }
    }
}

// MARK: - Shared

private struct LearningViewerMessage: View {
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
