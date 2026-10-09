import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    
    var sourceType: UIImagePickerController.SourceType = .camera
    var cameraDevice: UIImagePickerController.CameraDevice = .front
    /// true (the default, and what every existing caller gets): a device without the requested source — the
    /// simulator has no camera — falls back to the photo library. false: never open the library; the picker
    /// closes itself instead. For photos that must come from the camera (e.g. a camera-only odometer photo).
    var allowLibraryFallback: Bool = true

    /// Whether this device has a camera to take a photo with.
    static var isCameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        
        if UIImagePickerController.isSourceTypeAvailable(sourceType) {
            picker.sourceType = sourceType
            if sourceType == .camera {
                picker.cameraDevice = cameraDevice
            }
        } else if !allowLibraryFallback {
            // No fallback allowed: close straight away rather than show a photo library.
            print("🚨 IMAGE_PICKER: source unavailable and library fallback is off — dismissing.")
            let close = dismiss
            DispatchQueue.main.async { close() }
        } else if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            picker.sourceType = .photoLibrary
            print("📸 IMAGE_PICKER: Falling back to .photoLibrary")
        } else if UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum) {
            picker.sourceType = .savedPhotosAlbum
            print("📸 IMAGE_PICKER: Falling back to .savedPhotosAlbum")
        } else {
            print("🚨 ERROR: No image source available on this device/simulator.")
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
