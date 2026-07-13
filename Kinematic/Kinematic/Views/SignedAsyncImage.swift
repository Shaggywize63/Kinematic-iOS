//
//  SignedAsyncImage.swift
//  Kinematic
//
//  Drop-in replacement for `AsyncImage` that renders images stored in PRIVATE
//  Supabase Storage buckets (attendance selfies, form photos, avatars) by
//  exchanging the stored object URL for a short-lived signed URL via
//  GET /api/v1/media/sign. SECURITY_AUDIT_2026-07.md PR-1 — the selfie/photo
//  buckets were flipped from world-readable to private, so a raw <AsyncImage>
//  pointed at the stored URL would now 400/403.
//
//  Safe by design: URLs that are NOT one of the signable private buckets
//  (public assets, external images, the `kinematic-offline://` placeholder)
//  pass through unchanged, and if signing fails for any reason we fall back to
//  the original URL — so it is never worse than a plain AsyncImage.
//

import SwiftUI

/// Actor that exchanges stored private-bucket URLs for short-lived signed URLs
/// and caches them just under the backend's 5-minute grant.
actor MediaSigning {
    static let shared = MediaSigning()

    private var cache: [String: (url: String, expires: Date)] = [:]
    private let ttl: TimeInterval = 4 * 60  // a little under the 300s the backend signs for

    // Keep in sync with SIGNABLE_BUCKETS in the backend media controller and
    // SIGNABLE_RE in the dashboard's SignedImage component.
    private static let signableRegex = try? NSRegularExpression(
        pattern: "/storage/v1/object/(?:public|sign|authenticated)/"
               + "(?:kinematic-selfies|kinematic-form-photos|form-responses|kinematic-avatars|kinematic-materials)/"
    )

    /// Resolve a stored URL string to a `URL` ready for `AsyncImage`.
    /// - nil / empty → nil
    /// - non-signable (public asset, external, offline placeholder) → as-is
    /// - signable → signed URL (cached), falling back to the original on error
    func resolvedURL(for stored: String?) async -> URL? {
        guard let stored, !stored.isEmpty else { return nil }
        guard isSignable(stored) else { return URL(string: stored) }

        if let hit = cache[stored], hit.expires > Date() {
            return URL(string: hit.url)
        }
        do {
            let signed = try await CRMService.shared.signMediaURL(stored)
            cache[stored] = (signed, Date().addingTimeInterval(ttl))
            return URL(string: signed)
        } catch {
            return URL(string: stored)  // graceful fallback — no worse than the raw URL
        }
    }

    private func isSignable(_ s: String) -> Bool {
        guard let rx = Self.signableRegex else { return false }
        let range = NSRange(s.startIndex..., in: s)
        return rx.firstMatch(in: s, options: [], range: range) != nil
    }
}

/// `AsyncImage`-shaped view that signs private-bucket URLs before loading.
struct SignedAsyncImage<Content: View>: View {
    private let urlString: String?
    private let scale: CGFloat
    private let transaction: Transaction
    @ViewBuilder private let content: (AsyncImagePhase) -> Content

    @State private var resolved: URL?

    /// Phase-based initializer (mirrors `AsyncImage(url:scale:transaction:content:)`).
    init(urlString: String?,
         scale: CGFloat = 1,
         transaction: Transaction = Transaction(),
         @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.urlString = urlString
        self.scale = scale
        self.transaction = transaction
        self.content = content
    }

    var body: some View {
        AsyncImage(url: resolved, scale: scale, transaction: transaction, content: content)
            .task(id: urlString) {
                resolved = await MediaSigning.shared.resolvedURL(for: urlString)
            }
    }
}

extension SignedAsyncImage {
    /// Content + placeholder initializer (mirrors
    /// `AsyncImage(url:scale:content:placeholder:)`).
    init<I: View, P: View>(urlString: String?,
                           scale: CGFloat = 1,
                           @ViewBuilder content: @escaping (Image) -> I,
                           @ViewBuilder placeholder: @escaping () -> P)
        where Content == _ConditionalContent<I, P> {
        self.init(urlString: urlString, scale: scale) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
    }
}
