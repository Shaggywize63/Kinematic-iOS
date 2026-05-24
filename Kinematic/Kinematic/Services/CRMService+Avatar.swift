//
//  CRMService+Avatar.swift
//  Kinematic
//
//  User-avatar upload + self-profile patch.
//
//  Pairs with `POST /api/v1/upload/avatar` (multipart, `photo` field →
//  Supabase `kinematic-avatars` bucket) and `PATCH /api/v1/auth/me`,
//  which is the regular-user-safe route for self-update. The admin-gated
//  `/users/:id` endpoint refuses non-admins, so we never hit it from the
//  iOS app for avatar changes.
//
//  Lives alongside CRMService+FormConfig.swift so iOS shares the same
//  bearer/X-Org-Id header conventions and 8 MB JPEG compressor — but the
//  surface is intentionally NOT CRM: this is the signed-in user's own
//  identity. Naming follows the existing extension-on-CRMService pattern
//  the rest of the app already calls into.
//

import Foundation
import UIKit

extension CRMService {
    /// Upload a UIImage as JPEG to `/api/v1/upload/avatar` and return
    /// the hosted Supabase URL. Mirrors `uploadPhoto(_:)` — same auth
    /// headers, same multipart `photo` field, same 8 MB cap — but
    /// targets the avatar bucket so we don't co-mingle user portraits
    /// with CRM entity photos.
    func uploadAvatar(_ image: UIImage) async throws -> String {
        guard let data = Self.avatarJpegUnder8MB(image) else {
            throw CRMServiceError.server("Could not encode avatar image")
        }

        let url = try AvatarHelpers.buildURL(path: "/api/v1/upload/avatar")
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        AvatarHelpers.applyHeaders(to: &req)
        // applyHeaders sets application/json; override for multipart.
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (respData, resp) = try await URLSession.shared.data(for: req)
        try AvatarHelpers.validate(resp, data: respData)

        // Accept either `{ data: { url } }` envelope or top-level `{ url }`.
        if let root = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] {
            if let nested = root["data"] as? [String: Any], let url = nested["url"] as? String {
                return url
            }
            if let url = root["url"] as? String { return url }
        }
        throw CRMServiceError.decodeFailed("Avatar upload did not return a url")
    }

    /// Patch the currently signed-in user's profile via `/api/v1/auth/me`.
    ///
    /// Both arguments are optional — pass only the keys you want to change.
    /// `avatarUrl` distinguishes three cases:
    ///   * `.some(url)`         → set the avatar
    ///   * `.some("")` or `nil` plus `clearAvatar = true` → clear it
    ///   * omit entirely (nil + clearAvatar=false) → don't touch the field
    ///
    /// Server returns the freshly read user row; the caller is expected
    /// to write the result back into `Session.currentUser`.
    func updateMyProfile(
        name: String? = nil,
        avatarUrl: String? = nil,
        clearAvatar: Bool = false
    ) async throws -> User {
        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if clearAvatar {
            // PostgREST / our auth route accepts NSNull as "set to null".
            // Empty-string would race with the column's NOT-NULL-but-null
            // semantics on Supabase, so prefer explicit NSNull.
            payload["avatar_url"] = NSNull()
        } else if let avatarUrl {
            payload["avatar_url"] = avatarUrl
        }
        guard !payload.isEmpty else {
            // Nothing to update — return the in-memory user untouched so
            // callers don't have to special-case "nothing changed".
            if let cached = Session.currentUser { return cached }
            throw CRMServiceError.server("No profile changes specified")
        }

        let url = try AvatarHelpers.buildURL(path: "/api/v1/auth/me")
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.timeoutInterval = 30
        AvatarHelpers.applyHeaders(to: &req)
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        try AvatarHelpers.validate(resp, data: data)

        let decoder = JSONDecoder()
        // Envelope first — matches every other write on the backend.
        if let env = try? decoder.decode(APIEnvelope<User>.self, from: data), let u = env.data {
            return u
        }
        // Some auth routes return the user as the top-level body.
        if let raw = try? decoder.decode(User.self, from: data) { return raw }
        // Last resort: stitch the response onto the cached user so the UI
        // still updates even if the server returns a thinner payload.
        if let cached = Session.currentUser {
            if clearAvatar { return cached.withAvatarUrl(nil) }
            if let avatarUrl { return cached.withAvatarUrl(avatarUrl) }
            return cached
        }
        throw CRMServiceError.decodeFailed("Profile update returned no user")
    }

    /// JPEG-encode while staying under 8MB. Same shape as the CRM photo
    /// compressor, kept separate so future avatar-specific tuning (e.g.
    /// square-crop) doesn't risk regressing CRM uploads.
    private static func avatarJpegUnder8MB(_ image: UIImage) -> Data? {
        let cap = 8 * 1024 * 1024
        var quality: CGFloat = 0.9
        var data = image.jpegData(compressionQuality: quality)
        while let d = data, d.count > cap, quality > 0.3 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
        }
        if (data?.count ?? 0) > cap {
            let scale: CGFloat = 0.7
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
            data = resized.jpegData(compressionQuality: 0.7)
        }
        return data
    }
}

// MARK: - Private helpers (mirrors CRMService+FormConfig's helpers)
private enum AvatarHelpers {
    static let baseHostURL: URL = URL(string: "https://kinematic-production.up.railway.app")!

    static func buildURL(path: String) throws -> URL {
        let url = baseHostURL.appendingPathComponent(path)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let final = components.url else {
            throw CRMServiceError.server("Bad URL")
        }
        return final
    }

    static func applyHeaders(to req: inout URLRequest) {
        let token = Session.sharedToken.isEmpty
            ? (UserDefaults.standard.string(forKey: "auth_token") ?? "")
            : Session.sharedToken
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }
    }

    static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw CRMServiceError.badResponse(0) }
        if !(200..<300).contains(http.statusCode) {
            if let env = try? JSONDecoder().decode(APIEnvelope<EmptyAck>.self, from: data),
               let msg = env.error ?? env.message {
                throw CRMServiceError.server(msg)
            }
            throw CRMServiceError.badResponse(http.statusCode)
        }
    }
}
