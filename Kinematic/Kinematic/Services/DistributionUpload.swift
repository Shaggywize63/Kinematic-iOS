// DistributionUpload — the two-step photo upload the distribution screens use (cheque photo on Collect Payment, photo
// of the goods on a Return): ask the backend for a signed upload URL (`POST /salesman/uploads/sign`), then PUT the
// JPEG to it. The returned public URL is what goes on the payment / return — the backend only accepts URLs it issued.
// Mirrors the Android `DistributionRepository.uploadDistributionImage`.

import Foundation
import UIKit

enum DistributionUpload {

    /// `kind` is the upload kind the backend accepts: "cheque" | "pod" | "return" | "signature" | "kyc".
    /// Returns the public URL, or nil on any failure (offline, refused, …) — the caller says "try again".
    static func uploadJPEG(_ jpeg: Data, kind: String) async -> String? {
        do {
            let signed = try await DistributionAPI.shared.signUpload(kind: kind, ext: "jpg")
            guard let url = URL(string: signed.upload_url) else { return nil }
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.timeoutInterval = 60
            req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            req.setValue("true", forHTTPHeaderField: "x-upsert")
            // Harmless on pre-signed URLs that don't need it, required for Supabase signed-upload URLs.
            if !signed.token.isEmpty { req.setValue("Bearer \(signed.token)", forHTTPHeaderField: "Authorization") }
            let (_, response) = try await URLSession.shared.upload(for: req, from: jpeg)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return signed.public_url
        } catch {
            return nil
        }
    }

    /// A photo as JPEG bytes small enough to upload on a weak connection: the longest side is brought down to
    /// `maxDimension` points and the quality to `quality`.
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.75) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        if longest <= maxDimension { return image.jpegData(compressionQuality: quality) }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}
