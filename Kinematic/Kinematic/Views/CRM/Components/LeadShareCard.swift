import SwiftUI
import UIKit

// MARK: - Share-card data

/// Everything a share card renders, resolved ahead of the render pass.
/// ImageRenderer is synchronous — AsyncImage never finishes inside it — so
/// the photo is pre-fetched into a UIImage and lookup UUIDs are resolved to
/// labels before the card is drawn. One shape serves Lead / Deal / Activity;
/// only the `badge`, hero source and `rows` differ per entity.
struct ShareCardData {
    /// Header pill text — "LEAD" / "DEAL" / "ACTIVITY".
    let badge: String
    /// Centrepiece name (person / deal / linked-record name).
    let name: String
    /// Secondary line under the name (phone, lead name, subject…).
    let subtitle: String?
    /// SF Symbol drawn before the subtitle.
    let subtitleIcon: String?
    /// Pre-fetched hero photo; nil falls back to `initials`.
    let photo: UIImage?
    let initials: String
    /// Labelled detail rows (label, value), already resolved to display strings.
    let rows: [(String, String)]
}

// MARK: - Renderer

/// Renders a `ShareCard` off-screen into a share-ready image. Shared by every
/// entity builder so the card size / scale live in exactly one place.
enum ShareCardRenderer {
    /// Card size in points. Rendered at scale 2 → 1080×1350 px, the 4:5
    /// portrait frame WhatsApp / Instagram previews render best.
    static let cardSize = CGSize(width: 540, height: 675)

    @MainActor
    static func image(from data: ShareCardData) -> UIImage? {
        let renderer = ImageRenderer(
            content: ShareCard(data: data)
                // The card ships as a standalone image — always render the
                // light styling regardless of the device appearance.
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: cardSize.width, height: cardSize.height)
        return renderer.uiImage
    }
}

// MARK: - Shared value helpers

private let shareCreatedFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_IN")
    f.dateFormat = "dd MMM yyyy, h:mm a"
    return f
}()

/// ISO-8601 (with or without fractional seconds) → "dd MMM yyyy, h:mm a".
private func shareCreatedText(_ iso: String?) -> String? {
    guard let iso else { return nil }
    let withFrac = ISO8601DateFormatter()
    withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = withFrac.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
    return shareCreatedFormatter.string(from: date)
}

/// Compact kg / t formatter — kg under a tonne, tonnes otherwise. Mirrors the
/// deal detail screen's formatter so the shared card reads the same number.
private func shareFormatKg(_ kg: Double) -> String? {
    guard kg > 0 else { return nil }
    if kg < 1000 {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "\(f.string(from: NSNumber(value: kg)) ?? "0") kg"
    }
    let tons = kg / 1000
    let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = tons < 10 ? 2 : 1
    return "\(f.string(from: NSNumber(value: tons)) ?? "0") t"
}

/// Fetch a private-bucket image URL into a UIImage, signing it first (the same
/// resolver SignedAsyncImage uses). Returns nil so the card degrades to
/// initials rather than failing the whole render.
@MainActor
private func shareFetchPhoto(_ urlString: String?) async -> UIImage? {
    guard let s = urlString, !s.isEmpty else { return nil }
    let signedURL = await MediaSigning.shared.resolvedURL(for: s) ?? URL(string: s)
    guard let url = signedURL,
          let (data, _) = try? await URLSession.shared.data(from: url),
          let img = UIImage(data: data) else { return nil }
    return img
}

private func shareInitials(from name: String) -> String {
    let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
    let combined = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    return combined.isEmpty ? "?" : combined
}

// MARK: - Card view

/// The rendered share card — brand header (badge + real Kinematic mark),
/// photo / initials hero, name, subtitle, and a labelled details panel. Fixed
/// light palette: the output is a standalone image, so it must not inherit the
/// device's dark mode.
struct ShareCard: View {
    let data: ShareCardData

    private let secondaryText = Color(red: 0x6B / 255.0, green: 0x72 / 255.0, blue: 0x80 / 255.0)
    private let panelFill = Color(red: 0.965, green: 0.967, blue: 0.975)

    var body: some View {
        VStack(spacing: 0) {
            header
            heroView
            VStack(spacing: 8) {
                Text(data.name)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(Brand.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 32)
                if let subtitle = data.subtitle, !subtitle.isEmpty {
                    HStack(spacing: 8) {
                        if let icon = data.subtitleIcon {
                            Image(systemName: icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Brand.red)
                        }
                        Text(subtitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Brand.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 32)
                }
                detailPanel
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: ShareCardRenderer.cardSize.width,
               height: ShareCardRenderer.cardSize.height)
        .background(Color.white)
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Real Kinematic mark (reverse artwork = white dots for the red
            // header). Never the mono silhouette — see KinematicBrandMark.
            Image("KinematicMarkReverse")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
            Text("KINEMATIC")
                .font(.system(size: 16, weight: .black))
                .tracking(2.5)
                .foregroundColor(.white)
            Spacer()
            Text(data.badge)
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.18))
                .foregroundColor(.white)
                .cornerRadius(6)
        }
        .padding(.horizontal, 28)
        .frame(height: 76)
        .frame(maxWidth: .infinity)
        .background(Brand.red)
    }

    /// Full-width hero banner sitting directly under the header — the record's
    /// photo is the centrepiece. When there's no photo, a same-sized subtle
    /// block carries the large initials.
    private static let heroHeight: CGFloat = 250

    @ViewBuilder
    private var heroView: some View {
        if let photo = data.photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: ShareCardRenderer.cardSize.width,
                       height: Self.heroHeight)
                .clipped()
        } else {
            ZStack {
                Rectangle().fill(Brand.red.opacity(0.10))
                Text(data.initials)
                    .font(.system(size: 96, weight: .black))
                    .foregroundColor(Brand.red.opacity(0.85))
            }
            .frame(width: ShareCardRenderer.cardSize.width,
                   height: Self.heroHeight)
            .clipped()
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if !data.rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(data.rows.enumerated()), id: \.offset) { idx, row in
                    if idx > 0 {
                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(height: 1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.0.uppercased())
                            .font(.system(size: 11, weight: .black))
                            .tracking(1)
                            .foregroundColor(secondaryText)
                            .frame(width: 118, alignment: .leading)
                        Text(row.1)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Brand.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 16).fill(panelFill))
            .padding(.horizontal, 28)
        }
    }

    private var footer: some View {
        HStack {
            Text("Shared via Kinematic CRM")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(secondaryText)
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }
}

// MARK: - Lead builder

/// Assembles a lead share card (custom-field-defs fetch, one
/// `/lookup/search?ids=` call per referenced target table, one photo fetch)
/// and renders it off-screen into a share-ready image.
enum LeadShareCardBuilder {
    /// Kept for callers that render the card directly; forwards to the shared renderer.
    static let cardSize = ShareCardRenderer.cardSize

    @MainActor
    static func makeImage(for lead: Lead) async -> UIImage? {
        ShareCardRenderer.image(from: await resolveData(for: lead))
    }

    /// Resolve display values: created timestamp, dealer / construction-area /
    /// brand / block custom fields (lookup UUIDs → labels), and the lead photo.
    @MainActor
    static func resolveData(for lead: Lead) async -> ShareCardData {
        let cf = lead.customFields ?? [:]
        let createdText = shareCreatedText(lead.createdAt)

        // Dealer / construction area / brand / block ride admin-defined custom
        // fields, so the exact keys vary per tenant — match the defs by
        // key/label.
        let defs = await CRMService.shared.listCustomFields().filter { $0.entityType == "lead" }
        func firstDef(containing needles: [String]) -> CRMCustomFieldDef? {
            for needle in needles {
                if let d = defs.first(where: {
                    $0.fieldKey.lowercased().contains(needle) || $0.label.lowercased().contains(needle)
                }) { return d }
            }
            return nil
        }

        // A slot is either directly displayable or a (target, id) pair still
        // needing label resolution via /lookup/search.
        func slot(for def: CRMCustomFieldDef?) -> (display: String?, target: String?, id: String?) {
            guard let def, let any = cf[def.fieldKey]?.raw?.any else { return (nil, nil, nil) }
            if let dict = any as? [String: Any] {
                if let label = dict["label"] as? String, !label.isEmpty { return (label, nil, nil) }
                if def.fieldType == "lookup", let target = def.targetTable, !target.isEmpty,
                   let id = dict["id"] as? String, !id.isEmpty {
                    return (nil, target, id)
                }
                return (nil, nil, nil)
            }
            if let s = any as? String, !s.isEmpty {
                if def.fieldType == "lookup", let target = def.targetTable, !target.isEmpty {
                    return (nil, target, s)
                }
                return (s, nil, nil)
            }
            // Plain scalar custom fields (number / boolean) — e.g. SRS's
            // "Construction Area (SQ FT)" is stored as a raw number, so it
            // never matched the dict/string branches above and silently
            // dropped off the card. Render it directly.
            if let b = any as? Bool { return (b ? "Yes" : "No", nil, nil) }
            if let i = any as? Int { return (String(i), nil, nil) }
            if let d = any as? Double {
                // Trim a trailing ".0" so 1500.0 reads "1500". Guard the Int
                // conversion against out-of-range doubles (Int(_:) traps).
                let s = (d == d.rounded() && abs(d) < 1e15) ? String(Int(d)) : String(d)
                return (s, nil, nil)
            }
            return (nil, nil, nil)
        }

        let dealerSlot = slot(for: firstDef(containing: ["dealer"]))
        let constructionSlot = slot(for: firstDef(containing: ["construction", "constr_area", "const_area"]))
        let brandSlot = slot(for: firstDef(containing: ["brand"]))
        let blockSlot = slot(for: firstDef(containing: ["block"]))

        // Batch UUID → label resolution: one call per target table.
        var pendingByTarget: [String: Set<String>] = [:]
        for s in [dealerSlot, constructionSlot, brandSlot, blockSlot] {
            if let target = s.target, let id = s.id {
                pendingByTarget[target, default: []].insert(id)
            }
        }
        var resolved: [String: String] = [:]  // "target:id" → label
        for (target, ids) in pendingByTarget {
            let opts = await CRMService.shared.lookupSearch(target: target, ids: Array(ids))
            for o in opts { resolved["\(target):\(o.id)"] = o.label }
        }
        func finish(_ s: (display: String?, target: String?, id: String?)) -> String? {
            if let d = s.display { return d }
            guard let target = s.target, let id = s.id else { return nil }
            return resolved["\(target):\(id)"] ?? String(id.prefix(8))
        }

        // Lead photo — column first, then the legacy custom-field spots.
        let photoUrlString = lead.photoUrl
            ?? (cf["photo_url"]?.raw?.any as? String)
            ?? (cf["photo"]?.raw?.any as? String)
        let photo = await shareFetchPhoto(photoUrlString)

        let initials: String = {
            let f = lead.firstName?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
            let l = lead.lastName?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
            let combined = (f + l).uppercased()
            if !combined.isEmpty { return combined }
            return shareInitials(from: lead.displayName)
        }()

        var rows: [(String, String)] = []
        if let v = createdText { rows.append(("Created", v)) }
        if let v = lead.ownerName, !v.isEmpty { rows.append(("Owner", v)) }
        if let v = finish(dealerSlot), !v.isEmpty { rows.append(("Dealer", v)) }
        if let v = finish(constructionSlot), !v.isEmpty { rows.append(("Construction Area", v)) }
        if let v = finish(brandSlot), !v.isEmpty { rows.append(("Brand", v)) }
        if let v = finish(blockSlot), !v.isEmpty { rows.append(("Block", v)) }

        return ShareCardData(
            badge: "LEAD",
            name: lead.displayName,
            subtitle: lead.phone,
            subtitleIcon: "phone.fill",
            photo: photo,
            initials: initials,
            rows: rows
        )
    }
}

// MARK: - Deal builder

/// Assembles a deal share card. Re-fetches the deal so the backend-stamped
/// dealer_name / lead_name / owner_name are guaranteed present even when the
/// caller only had a list row, resolves any site-photo custom field, and
/// surfaces the deal's tonnage + value.
enum DealShareCardBuilder {
    @MainActor
    static func makeImage(for deal: Deal) async -> UIImage? {
        let full = (try? await CRMService.shared.getDeal(id: deal.id)) ?? deal
        return ShareCardRenderer.image(from: await resolveData(for: full))
    }

    @MainActor
    static func resolveData(for deal: Deal) async -> ShareCardData {
        let cf = deal.customFields ?? [:]
        let createdText = shareCreatedText(deal.createdAt)

        // Site photo — prefer an image attached to the deal's own custom
        // fields; otherwise tag the linked lead's site photo (its column or a
        // custom-field image). "Tag site photo from lead (if any attached)".
        var photoURL = firstImageURL(in: cf)
        if photoURL == nil, let leadId = deal.leadId,
           let lead = try? await CRMService.shared.getLead(id: leadId) {
            photoURL = lead.photoUrl ?? firstImageURL(in: lead.customFields ?? [:])
        }
        let photo = await shareFetchPhoto(photoURL)

        let leadName = deal.leadName?.trimmingCharacters(in: .whitespaces)
        let displayName = deal.name.isEmpty ? (leadName ?? "Deal") : deal.name

        var rows: [(String, String)] = []
        if let v = createdText { rows.append(("Created", v)) }
        if let v = deal.ownerName?.trimmingCharacters(in: .whitespaces), !v.isEmpty { rows.append(("Owner", v)) }
        if let v = deal.dealerName?.trimmingCharacters(in: .whitespaces), !v.isEmpty { rows.append(("Dealer", v)) }
        // The lead name already headlines the card (name / subtitle up top),
        // so don't repeat it here — surface the lead's contact number instead.
        if let v = deal.leadPhone?.trimmingCharacters(in: .whitespaces), !v.isEmpty { rows.append(("Lead Contact", v)) }
        if let v = shareFormatKg(derivedWeightKg(cf)) { rows.append(("Tonnage", v)) }
        if let amt = deal.amount, amt > 0 { rows.append(("Value", CurrencyFormatter.formatINR(amt))) }

        return ShareCardData(
            badge: "DEAL",
            name: displayName,
            subtitle: leadName,
            subtitleIcon: "person.fill",
            photo: photo,
            initials: shareInitials(from: displayName),
            rows: rows
        )
    }

    /// Total weight (kg) — prefers custom_fields.volume_kg, falls back to
    /// recomputing from product_lines. Mirrors DealDetailView.derivedWeightKg.
    private static func derivedWeightKg(_ cf: [String: AnyCodable]) -> Double {
        let map = cf.compactMapValues { $0.raw?.any }
        if let v = map["volume_kg"] as? Double, v > 0 { return v }
        if let v = map["volume_kg"] as? Int, v > 0 { return Double(v) }
        if let s = map["volume_kg"] as? String, let v = Double(s), v > 0 { return v }
        guard let lines = map["product_lines"] as? [[String: Any]] else { return 0 }
        var total = 0.0
        for l in lines {
            let qty: Double = {
                if let n = l["quantity"] as? Double { return n }
                if let n = l["quantity"] as? Int { return Double(n) }
                if let s = l["quantity"] as? String { return Double(s) ?? 0 }
                return 0
            }()
            guard qty > 0 else { continue }
            let unit = (l["measuring_unit"] as? String)?.lowercased() ?? ""
            total += qty * (unit == "tonne" ? 1000 : 1)
        }
        return total
    }
}

// MARK: - Activity builder

/// Assembles an activity share card. Everything the card needs is already on
/// the Activity (backend-stamped owner_name / lead_name, the activity photo),
/// so no extra fetch beyond signing the image URL.
enum ActivityShareCardBuilder {
    @MainActor
    static func makeImage(for activity: Activity) async -> UIImage? {
        ShareCardRenderer.image(from: await resolveData(for: activity))
    }

    @MainActor
    static func resolveData(for activity: Activity) async -> ShareCardData {
        // Prefer the created stamp; fall back to completed/due so older rows
        // still show a date.
        let createdText = shareCreatedText(activity.createdAt ?? activity.completedAt ?? activity.dueAt)
        let photo = await shareFetchPhoto(activity.imageUrl)

        // "Lead name or Directory name" — the linked record. Falls back
        // through lead → directory (people-directory dealer) → contact → deal.
        let leadName = activity.leadName?.trimmingCharacters(in: .whitespaces)
        let directoryName = activity.directoryName?.trimmingCharacters(in: .whitespaces)
        let linked = [leadName, directoryName, activity.contactName, activity.dealName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let typeLabel = (activity.type ?? "activity")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        let subject = activity.subject?.trimmingCharacters(in: .whitespaces)
        let displayName = linked ?? (subject?.isEmpty == false ? subject! : typeLabel)

        // Contact number to reach them — the directory's mobile, else the
        // linked lead's phone.
        let contactNumber = [activity.directoryPhone, activity.leadPhone]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }

        var rows: [(String, String)] = []
        rows.append(("Type", typeLabel))
        if let v = createdText { rows.append(("Created", v)) }
        if let v = leadName, !v.isEmpty, v != displayName { rows.append(("Lead", v)) }
        if let v = directoryName, !v.isEmpty, v != displayName { rows.append(("Directory", v)) }
        if let v = contactNumber { rows.append(("Contact", v)) }
        if let v = activity.ownerName?.trimmingCharacters(in: .whitespaces), !v.isEmpty { rows.append(("Owner", v)) }

        return ShareCardData(
            badge: "ACTIVITY",
            name: displayName,
            subtitle: (subject?.isEmpty == false && subject != displayName) ? subject : (linked != nil ? typeLabel : nil),
            subtitleIcon: "tag.fill",
            photo: photo,
            initials: shareInitials(from: displayName),
            rows: rows
        )
    }
}

// MARK: - Shared photo helper

/// Find the first stored image URL inside a custom-fields map — used for a
/// deal's optional "site photo". Prefers keys that look like a photo/image/site
/// field, then any http-valued string.
private func firstImageURL(in cf: [String: AnyCodable]) -> String? {
    func urlString(_ any: Any?) -> String? {
        if let s = any as? String, s.hasPrefix("http") { return s }
        if let d = any as? [String: Any] {
            if let u = d["url"] as? String, u.hasPrefix("http") { return u }
            if let u = d["value"] as? String, u.hasPrefix("http") { return u }
        }
        return nil
    }
    let preferred = cf.keys.filter {
        let l = $0.lowercased()
        return l.contains("photo") || l.contains("image") || l.contains("site")
    }
    for k in preferred { if let u = urlString(cf[k]?.raw?.any) { return u } }
    for (_, v) in cf { if let u = urlString(v.raw?.any) { return u } }
    return nil
}

// MARK: - Share sheet

/// UIActivityViewController wrapper for a rendered share image. Sharing a plain
/// UIImage keeps WhatsApp / Messages / Save Image in the sheet.
struct LeadShareActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// A text activity item that also supplies an email subject. Added alongside a
/// file item so the OS share sheet gives Mail a proper subject + body and gives
/// WhatsApp a proper caption — instead of an attachment with no message.
final class ShareTextItemSource: NSObject, UIActivityItemSource {
    private let text: String
    private let subject: String
    init(text: String, subject: String) { self.text = text; self.subject = subject }
    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { text }
    func activityViewController(_ controller: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { text }
    func activityViewController(_ controller: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String { subject }
}
