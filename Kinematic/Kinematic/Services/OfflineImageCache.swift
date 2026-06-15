import Foundation

/// Persistent image cache for offline-first mutation replay.
///
/// When a rep attaches a photo while offline, the bytes are written
/// here under an opaque file name. The caller stamps a placeholder
/// URL of the form
///
///     kinematic-offline://image-<filename>
///
/// onto the mutation payload before queuing. On replay,
/// `OfflineMutationQueue` walks the payload, uploads each cached
/// file via the real /upload endpoint, swaps the placeholder for
/// the returned URL, and only then fires the actual mutation.
///
/// Lives under `Application Support / KinematicOfflineImages/` so
/// the bytes survive app restarts.
enum OfflineImageCache {
    static let placeholderPrefix = "kinematic-offline://image-"

    private static var dir: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("KinematicOfflineImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Persist [data] and return the placeholder URL the caller stamps
    /// onto the mutation payload.
    @discardableResult
    static func save(_ data: Data, ext: String = "jpg") -> String {
        let name = "\(UUID().uuidString).\(ext)"
        let file = dir.appendingPathComponent(name)
        try? data.write(to: file, options: [.atomic])
        return placeholderPrefix + name
    }

    /// Resolve [placeholder] back to the on-disk file URL, or nil if
    /// the URL isn't a placeholder / the file has already been drained.
    static func fileURL(for placeholder: String) -> URL? {
        guard placeholder.hasPrefix(placeholderPrefix) else { return nil }
        let name = String(placeholder.dropFirst(placeholderPrefix.count))
        // Defensive: reject path traversal attempts since the name
        // comes from the on-disk queued payload.
        if name.contains("/") || name.contains("..") { return nil }
        let file = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Delete the cached file backing [placeholder]. Called once the
    /// upload that resolved it succeeded server-side.
    static func delete(_ placeholder: String) {
        guard let file = fileURL(for: placeholder) else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
