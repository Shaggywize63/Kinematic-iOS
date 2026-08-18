//
//  FaceRecognition.swift
//  Kinematic CRM
//
//  On-device face-recognition attendance (module: face_attendance).
//
//  Pipeline, all on-device:
//    1. Vision detects exactly ONE well-framed, front-facing face and gates on
//       quality (size, roll/yaw, single face) — this is the liveness/quality
//       guard against a blank frame or a group shot.
//    2. A bundled Core ML embedding model turns the face crop into a float
//       vector (an embedding). Enrolment stores that vector on the backend;
//       check-in re-embeds and cosine-compares against the fetched reference.
//
//  MODEL DROP-IN CONTRACT (the one thing supplied separately):
//    Add a Core ML face-embedding model (e.g. MobileFaceNet) to the app target
//    named `KinematicFaceEmbedder.mlmodel` (Xcode compiles it to
//    `KinematicFaceEmbedder.mlmodelc`). It must take a single IMAGE input and
//    produce a single MLMultiArray output (the embedding). Input size + names
//    are read from the model at runtime, so any standard face-embedding model
//    works without code changes. `MODEL_ID` below MUST be bumped whenever the
//    model changes, because embeddings are only comparable within one model.
//
//  Until that model is bundled, `embed()` returns `.modelUnavailable` and the
//  attendance flow falls back to a normal selfie (no identity match) — so the
//  app always compiles and runs. Nothing here reconstructs a face; the stored
//  vector is opaque.
//

import Foundation
import UIKit
import Vision
import CoreML
import CoreImage

/// The bundled model's identity. Embeddings are ONLY comparable within the same
/// model, so this rides on every enrolment + match and the backend refuses a
/// cross-model compare (the app re-enrols on mismatch). Bump on any model swap.
let FACE_MODEL_ID = "kinematic_face_v1"

/// Resource name (without extension) of the Core ML model in the app bundle.
private let FACE_MODEL_RESOURCE = "KinematicFaceEmbedder"

/// Cosine-similarity threshold above which a face is considered the enrolled
/// person. Conservative default; tuned per real-world FAR/FRR once the model is
/// chosen. Exposed so a future server-driven setting can override it.
let FACE_MATCH_THRESHOLD: Float = 0.62

// MARK: - Results

enum FaceQualityIssue: String {
    case noFace          = "NO_FACE"
    case multipleFaces   = "MULTIPLE_FACES"
    case tooSmall        = "FACE_TOO_SMALL"
    case notFrontal      = "FACE_NOT_FRONTAL"

    var friendly: String {
        switch self {
        case .noFace:        return "No face detected. Hold the phone at eye level and look at the camera."
        case .multipleFaces: return "More than one face in frame. Only you should be in the photo."
        case .tooSmall:      return "Move a little closer so your face fills the circle."
        case .notFrontal:    return "Look straight at the camera and keep your head level."
        }
    }
}

/// Outcome of turning a captured image into an embedding.
enum FaceEmbedResult {
    /// A usable embedding for the sole, well-framed face.
    case success(embedding: [Float], modelId: String)
    /// A face was found but failed a quality gate.
    case quality(FaceQualityIssue)
    /// No embedding model is bundled yet — caller should fall back to a plain
    /// selfie (no identity match).
    case modelUnavailable

    var qualityIssue: FaceQualityIssue? {
        if case .quality(let q) = self { return q }
        return nil
    }
}

// MARK: - Facade

/// Stateless facade the attendance flow calls. Actor-isolated to serialise the
/// (potentially heavy) Vision + Core ML work off the main thread.
actor FaceRecognition {
    static let shared = FaceRecognition()

    private let detector = FaceDetector()
    private lazy var embedder: FaceEmbedder = CoreMLFaceEmbedder()

    /// True when a real embedding model is bundled. The UI uses this to decide
    /// whether to offer enrolment / enforce a match at all.
    var isAvailable: Bool { embedder.isAvailable }

    /// Detect the sole face, gate on quality, and embed it.
    func embed(_ image: UIImage) async -> FaceEmbedResult {
        guard embedder.isAvailable else { return .modelUnavailable }
        switch detector.detectSingleFace(in: image) {
        case .failure(let issue):
            return .quality(issue)
        case .success(let faceCrop):
            guard let vector = embedder.embedding(from: faceCrop), !vector.isEmpty else {
                // A bundled-but-failing model is treated as unavailable so the
                // rep is never hard-blocked by a model error.
                return .modelUnavailable
            }
            return .success(embedding: vector, modelId: FACE_MODEL_ID)
        }
    }

    /// Cosine similarity in [-1, 1]; ≥ FACE_MATCH_THRESHOLD ⇒ same person.
    nonisolated func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : -1
    }
}

// MARK: - Detection + quality gate (Vision)

private struct FaceDetector {
    enum DetectResult {
        case success(UIImage)          // tight, upright face crop
        case failure(FaceQualityIssue)
    }

    /// Minimum face bounding-box height as a fraction of the image height.
    private let minFaceFraction: CGFloat = 0.18
    /// Max absolute head roll / yaw (radians ≈ 20°) for a "frontal" face.
    private let maxAngle: CGFloat = 0.35

    func detectSingleFace(in image: UIImage) -> DetectResult {
        // Redraw to `.up` first so Vision (orientation .up) and the crop share
        // one coordinate space — front-camera selfies are usually mirrored/rotated.
        let up = image.normalizedUp()
        guard let cg = up.cgImage else { return .failure(.noFace) }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return .failure(.noFace) }

        guard let faces = request.results, !faces.isEmpty else { return .failure(.noFace) }
        if faces.count > 1 { return .failure(.multipleFaces) }
        let face = faces[0]

        if face.boundingBox.height < minFaceFraction { return .failure(.tooSmall) }
        if let roll = face.roll?.doubleValue, abs(roll) > Double(maxAngle) { return .failure(.notFrontal) }
        if let yaw = face.yaw?.doubleValue, abs(yaw) > Double(maxAngle) { return .failure(.notFrontal) }

        guard let crop = cropped(cg: cg, normalizedRect: face.boundingBox) else {
            return .failure(.noFace)
        }
        return .success(crop)
    }

    /// Crop the (Vision-normalised, bottom-left origin) face rect out of an
    /// already-`.up` CGImage, with 25% padding.
    private func cropped(cg: CGImage, normalizedRect: CGRect) -> UIImage? {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        // Vision rects are normalised with a bottom-left origin; flip Y to UIKit.
        var rect = CGRect(
            x: normalizedRect.minX * w,
            y: (1 - normalizedRect.maxY) * h,
            width: normalizedRect.width * w,
            height: normalizedRect.height * h
        )
        let padX = rect.width * 0.25, padY = rect.height * 0.25
        rect = rect.insetBy(dx: -padX, dy: -padY)
        rect = rect.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isNull, rect.width > 1, rect.height > 1,
              let sub = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: sub)
    }
}

// MARK: - Embedder (Core ML, model-agnostic, drop-in)

private protocol FaceEmbedder {
    var isAvailable: Bool { get }
    /// Returns an L2-normalised embedding for the given face crop, or nil.
    func embedding(from faceCrop: UIImage) -> [Float]?
}

/// Loads the bundled Core ML model dynamically (no compile-time generated class,
/// so the app builds with no model present). Reads the model's own input image
/// size + feature names, so any standard single-image → single-multiarray face
/// embedder works unchanged.
private final class CoreMLFaceEmbedder: FaceEmbedder {
    private let model: MLModel?
    private let imageInputName: String?
    private let inputSize: CGSize
    private let ciContext = CIContext(options: nil)

    init() {
        guard let url = Bundle.main.url(forResource: FACE_MODEL_RESOURCE, withExtension: "mlmodelc"),
              let m = try? MLModel(contentsOf: url) else {
            self.model = nil; self.imageInputName = nil; self.inputSize = .zero
            print("ℹ️ FACE: no bundled embedding model (\(FACE_MODEL_RESOURCE)); face-match disabled, plain selfie used.")
            return
        }
        self.model = m
        // Find the first image input and its expected pixel dimensions.
        var name: String? = nil
        var size = CGSize(width: 112, height: 112)   // MobileFaceNet default
        for (key, desc) in m.modelDescription.inputDescriptionsByName {
            if let c = desc.imageConstraint {
                name = key
                size = CGSize(width: c.pixelsWide, height: c.pixelsHigh)
                break
            }
        }
        self.imageInputName = name
        self.inputSize = size
        if name == nil {
            print("⚠️ FACE: bundled model has no image input; face-match disabled.")
        }
    }

    var isAvailable: Bool { model != nil && imageInputName != nil }

    func embedding(from faceCrop: UIImage) -> [Float]? {
        guard let model, let imageInputName,
              let pixelBuffer = faceCrop.pixelBuffer(width: Int(inputSize.width), height: Int(inputSize.height), context: ciContext)
        else { return nil }
        let value = MLFeatureValue(pixelBuffer: pixelBuffer)   // non-throwing
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [imageInputName: value]),
              let out = try? model.prediction(from: provider) else { return nil }

        // Take the first multiarray output as the embedding.
        for name in out.featureNames {
            if let arr = out.featureValue(for: name)?.multiArrayValue {
                return normalize(arr)
            }
        }
        return nil
    }

    /// MLMultiArray → L2-normalised [Float].
    private func normalize(_ arr: MLMultiArray) -> [Float] {
        let n = arr.count
        var v = [Float](repeating: 0, count: n)
        for i in 0..<n { v[i] = arr[i].floatValue }
        var norm: Float = 0
        for x in v { norm += x * x }
        norm = norm.squareRoot()
        if norm > 0 { for i in 0..<n { v[i] /= norm } }
        return v
    }
}

// MARK: - UIImage helpers

private extension UIImage {
    /// Redraw with `.up` orientation so cropping math is predictable.
    func normalizedUp() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Render into a square BGRA CVPixelBuffer of the model's input size.
    func pixelBuffer(width: Int, height: Int, context: CIContext) -> CVPixelBuffer? {
        guard width > 0, height > 0, let cg = cgImage else { return nil }
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let buffer = pb else { return nil }
        // Aspect-fill the face into the square target.
        let ciImage = CIImage(cgImage: cg)
        let sx = CGFloat(width) / ciImage.extent.width
        let sy = CGFloat(height) / ciImage.extent.height
        let scale = max(sx, sy)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        context.render(scaled, to: buffer)
        return buffer
    }
}
