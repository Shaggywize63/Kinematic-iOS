import Foundation

/// One activity type from `GET /crm/activity-types`: the built-ins (id `builtin:<slug>`, `is_system`) plus any
/// custom types an admin added in Settings (e.g. slug `industry_visit`, name "Industry Visit"). Decoding is
/// forgiving — one odd row never fails the whole list.
struct ActivityTypeDef: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String
    /// An emoji (or empty / nil) — the backend stores no SF Symbol names.
    let icon: String?
    /// `#RRGGBB` when the admin picked one.
    let color: String?
    let position: Double?
    let isSystem: Bool?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, slug, name, icon, color, position
        case isSystem = "is_system"
        case isActive = "is_active"
    }

    init(id: String, slug: String, name: String, icon: String? = nil, color: String? = nil,
         position: Double? = nil, isSystem: Bool? = nil, isActive: Bool? = nil) {
        self.id = id
        self.slug = slug
        self.name = name
        self.icon = icon
        self.color = color
        self.position = position
        self.isSystem = isSystem
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let slug = ((try? c.decode(String.self, forKey: .slug)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.slug = slug
        self.id = (try? c.decode(String.self, forKey: .id)) ?? "builtin:\(slug)"
        let rawName = ((try? c.decode(String.self, forKey: .name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = rawName.isEmpty ? ActivityTypes.humanize(slug) : rawName
        self.icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        self.color = try? c.decodeIfPresent(String.self, forKey: .color)
        if let d = try? c.decodeIfPresent(Double.self, forKey: .position) {
            self.position = d
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .position), let d = Double(s) {
            self.position = d
        } else {
            self.position = nil
        }
        self.isSystem = try? c.decodeIfPresent(Bool.self, forKey: .isSystem)
        self.isActive = try? c.decodeIfPresent(Bool.self, forKey: .isActive)
    }
}

/// Pure rules for the activity-type lists the compose sheet, the list filter and the rows use. The server list
/// is the source of truth; with none (offline, failure) a built-in fallback keeps every screen working.
enum ActivityTypes {
    /// The five types the app has always offered, in the order it offered them (Meeting first).
    static let legacySlugs = ["meeting", "call", "email", "note", "task"]

    private static func builtin(_ slug: String, _ name: String, _ icon: String) -> ActivityTypeDef {
        ActivityTypeDef(id: "builtin:\(slug)", slug: slug, name: name, icon: icon, color: nil,
                        position: -1, isSystem: true, isActive: true)
    }

    /// Every built-in the backend serves — the offline fallback and the name / icon lookup of last resort.
    static let fallback: [ActivityTypeDef] = [
        builtin("meeting", "Meeting", "📅"),
        builtin("call", "Call", "📞"),
        builtin("email", "Email", "✉️"),
        builtin("note", "Note", "📝"),
        builtin("task", "Task", "✅"),
        builtin("sms", "SMS", "💬"),
        builtin("whatsapp", "WhatsApp", ""),
    ]

    /// The full list to keep from a server response: active rows only, one per slug (first wins). Empty / nil
    /// (a failed or empty load) gives the built-in fallback.
    static func sanitize(server: [ActivityTypeDef]?) -> [ActivityTypeDef] {
        var seen = Set<String>()
        var out: [ActivityTypeDef] = []
        for t in server ?? [] where t.isActive != false {
            let key = t.slug.lowercased()
            if key.isEmpty || !seen.insert(key).inserted { continue }
            out.append(t)
        }
        return out.isEmpty ? fallback : out
    }

    /// The types a person can PICK (compose sheet, list filter): the five classic ones, in their classic order,
    /// then every custom type (non-system) by position and name. System sms / whatsapp stay out of the picker as
    /// they always have; a classic type missing from the list is filled in from the fallback.
    static func offered(_ all: [ActivityTypeDef]) -> [ActivityTypeDef] {
        var bySlug: [String: ActivityTypeDef] = [:]
        for t in all where t.isActive != false {
            let key = t.slug.lowercased()
            if bySlug[key] == nil { bySlug[key] = t }
        }
        var out: [ActivityTypeDef] = []
        for slug in legacySlugs {
            if let t = bySlug[slug] ?? fallback.first(where: { $0.slug == slug }) { out.append(t) }
        }
        let customs = bySlug.values
            .filter { $0.isSystem != true && !legacySlugs.contains($0.slug.lowercased()) }
            .sorted {
                let a = $0.position ?? 0, b = $1.position ?? 0
                if a != b { return a < b }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        return out + customs
    }

    /// The compose sheet's type list. Scheduling drops "note" (a note never reminds) and puts "task" first. A
    /// `current` slug that is not offered (an activity edited after its type was switched off) is appended so
    /// the picker can still show — and keep — it.
    static func composerTypes(_ all: [ActivityTypeDef], scheduled: Bool, ensuring current: String? = nil) -> [ActivityTypeDef] {
        var list = offered(all)
        if scheduled {
            list.removeAll { $0.slug == "note" }
            if let i = list.firstIndex(where: { $0.slug == "task" }), i != 0 {
                let t = list.remove(at: i)
                list.insert(t, at: 0)
            }
        }
        if let cur = current?.trimmingCharacters(in: .whitespacesAndNewlines), !cur.isEmpty,
           !list.contains(where: { $0.slug.lowercased() == cur.lowercased() }) {
            list.append(def(for: cur, in: all) ?? ActivityTypeDef(id: "local:\(cur)", slug: cur, name: humanize(cur)))
        }
        return list
    }

    /// Slugs for the list's filter chips (without "all"); a `current` filter not on offer is kept.
    static func filterSlugs(_ all: [ActivityTypeDef], ensuring current: String? = nil) -> [String] {
        var slugs = offered(all).map(\.slug)
        if let cur = current, !cur.isEmpty, cur != "all", !slugs.contains(where: { $0.lowercased() == cur.lowercased() }) {
            slugs.append(cur)
        }
        return slugs
    }

    static func def(for slug: String?, in all: [ActivityTypeDef]) -> ActivityTypeDef? {
        let key = (slug ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return all.first { $0.slug.lowercased() == key }
    }

    /// Display name: the type's own name, else "Site Visit" / a humanised slug.
    static func name(for slug: String?, in all: [ActivityTypeDef]) -> String {
        if let d = def(for: slug, in: all), !d.name.isEmpty { return d.name }
        if let f = def(for: slug, in: fallback) { return f.name }
        let s = (slug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Activity" : humanize(s)
    }

    /// "industry_visit" -> "Industry Visit".
    static func humanize(_ slug: String) -> String {
        slug.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// SF Symbol for a slug the app knows; nil for a custom type (the row then uses the type's emoji or a
    /// generic symbol). `visit` / `site_visit` share the map pin.
    static func knownSymbol(for slug: String?) -> String? {
        switch (slug ?? "").lowercased() {
        case "call": return "phone.fill"
        case "email": return "envelope.fill"
        case "meeting": return "person.2.fill"
        case "note": return "note.text"
        case "task": return "checkmark.square.fill"
        case "sms": return "message.fill"
        case "whatsapp": return "bubble.left.and.bubble.right.fill"
        case "site_visit", "visit": return "mappin.and.ellipse"
        default: return nil
        }
    }

    /// Symbol for any slug: the known one, else a map pin for visit-like custom types, else a generic tag.
    static func symbol(for slug: String?) -> String {
        if let s = knownSymbol(for: slug) { return s }
        return (slug ?? "").lowercased().contains("visit") ? "mappin.and.ellipse" : "tag.fill"
    }

    /// The type's emoji when it has one worth showing (a custom type's own icon). Built-ins use SF Symbols.
    static func emoji(for def: ActivityTypeDef?) -> String? {
        guard let def, knownSymbol(for: def.slug) == nil else { return nil }
        let e = (def.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // A plain word / name ("phone") is not an emoji; show only real glyphs.
        guard !e.isEmpty, e.count <= 4, e.unicodeScalars.contains(where: { !$0.isASCII }) else { return nil }
        return e
    }

    /// Parse `#RRGGBB` / `RRGGBB` into 0...1 components; nil when malformed.
    static func rgb(hex: String?) -> (r: Double, g: Double, b: Double)? {
        var h = (hex ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255.0, Double((v >> 8) & 0xFF) / 255.0, Double(v & 0xFF) / 255.0)
    }
}

/// Pure rules for the activity composer's photo attachment: what a finished upload turns into, and when Save
/// is allowed. A photo the rep attached must never be silently dropped from the saved activity.
enum ActivityPhotoRules {
    enum Outcome: Equatable {
        /// The server stored it: this is the `image_url` to send.
        case uploaded(String)
        /// No network: keep the picture on the device (the offline queue swaps in the real URL when it uploads).
        case keepOnDevice
        /// The network is up but the upload failed: tell the rep and let them retry.
        case failed
    }

    static func outcome(uploadedUrl: String?, online: Bool) -> Outcome {
        if let u = uploadedUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty { return .uploaded(u) }
        return online ? .failed : .keepOnDevice
    }

    /// Save waits for a running upload, and for a picked photo that has no `image_url` yet (failed upload).
    static func canSave(hasPickedPhoto: Bool, imageUrl: String?, uploading: Bool) -> Bool {
        if uploading { return false }
        if hasPickedPhoto, (imageUrl ?? "").isEmpty { return false }
        return true
    }
}
