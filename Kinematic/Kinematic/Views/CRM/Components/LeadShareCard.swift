import SwiftUI
import UIKit

// MARK: - Share-card data

/// Everything the share card renders, resolved ahead of the render pass.
/// ImageRenderer is synchronous — AsyncImage never finishes inside it — so
/// the photo is pre-fetched into a UIImage and lookup UUIDs are resolved
/// to labels before the card is drawn.
struct LeadShareCardData {
    let name: String
    let phone: String?
    let createdText: String?
    let ownerName: String?
    let dealerName: String?
    let brand: String?
    let block: String?
    let photo: UIImage?
    let initials: String
}

// MARK: - Builder

/// Assembles `LeadShareCardData` from a lead (one custom-field-defs fetch,
/// one `/lookup/search?ids=` call per referenced target table, one photo
/// fetch) and renders `LeadShareCard` off-screen into a share-ready image.
enum LeadShareCardBuilder {
    /// Card size in points. Rendered at scale 2 → 1080×1350 px, the 4:5
    /// portrait frame WhatsApp / Instagram previews render best.
    static let cardSize = CGSize(width: 540, height: 675)

    /// Build the final share image for a lead. Returns nil only if the
    /// renderer itself fails; missing photo / lookups degrade gracefully.
    @MainActor
    static func makeImage(for lead: Lead) async -> UIImage? {
        let data = await resolveData(for: lead)
        let renderer = ImageRenderer(
            content: LeadShareCard(data: data)
                // The card ships as a standalone image — always render the
                // light styling regardless of the device appearance.
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: cardSize.width, height: cardSize.height)
        return renderer.uiImage
    }

    /// Resolve display values: created timestamp, dealer / brand / block
    /// custom fields (lookup UUIDs → labels), and the lead photo.
    /// MainActor-bound (the awaits suspend rather than block) so the
    /// UIImage-carrying result never crosses an actor boundary.
    @MainActor
    static func resolveData(for lead: Lead) async -> LeadShareCardData {
        let cf = lead.customFields ?? [:]

        // Created — "dd MMM yyyy, h:mm a".
        let createdText: String? = lead.createdAt.flatMap { iso -> String? in
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = withFrac.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
            return Self.createdFormatter.string(from: date)
        }

        // Dealer / brand / block ride admin-defined custom fields, so the
        // exact keys vary per tenant — match the defs by key/label.
        let defs = await CRMService.shared.listCustomFields().filter { $0.entityType == "lead" }
        func firstDef(containing needle: String) -> CRMCustomFieldDef? {
            defs.first {
                $0.fieldKey.lowercased().contains(needle) || $0.label.lowercased().contains(needle)
            }
        }

        // A slot is either directly displayable or a (target, id) pair
        // still needing label resolution via /lookup/search.
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
            return (nil, nil, nil)
        }

        let dealerSlot = slot(for: firstDef(containing: "dealer"))
        let brandSlot = slot(for: firstDef(containing: "brand"))
        let blockSlot = slot(for: firstDef(containing: "block"))

        // Batch UUID → label resolution: one call per target table with
        // every pending id joined into ids= (dealer + block usually share
        // a target, so this is typically a single request).
        var pendingByTarget: [String: Set<String>] = [:]
        for s in [dealerSlot, brandSlot, blockSlot] {
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
            // Cache miss still renders something recognisable, not a
            // 36-char UUID — same fallback CustomFieldsDetailCard uses.
            return resolved["\(target):\(id)"] ?? String(id.prefix(8))
        }

        // Lead photo — column first, then the legacy custom-field spots.
        var photo: UIImage? = nil
        let photoUrlString = lead.photoUrl
            ?? (cf["photo_url"]?.raw?.any as? String)
            ?? (cf["photo"]?.raw?.any as? String)
        // Lead photos live in a PRIVATE Supabase bucket, so fetching the
        // stored URL raw 403s and the card silently drops to initials.
        // Exchange it for a short-lived signed URL first (the same resolver
        // SignedAsyncImage uses); only fall back to the raw URL if signing
        // returns nil.
        if let s = photoUrlString, !s.isEmpty {
            let signedURL = await MediaSigning.shared.resolvedURL(for: s) ?? URL(string: s)
            if let url = signedURL,
               let (data, _) = try? await URLSession.shared.data(from: url),
               let img = UIImage(data: data) {
                photo = img
            }
        }

        let initials: String = {
            let f = lead.firstName?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
            let l = lead.lastName?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
            let combined = (f + l).uppercased()
            if !combined.isEmpty { return combined }
            return String(lead.displayName.prefix(1)).uppercased()
        }()

        return LeadShareCardData(
            name: lead.displayName,
            phone: lead.phone,
            createdText: createdText,
            ownerName: lead.ownerName,
            dealerName: finish(dealerSlot),
            brand: finish(brandSlot),
            block: finish(blockSlot),
            photo: photo,
            initials: initials
        )
    }

    private static let createdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.dateFormat = "dd MMM yyyy, h:mm a"
        return f
    }()
}

// MARK: - Card view

/// The rendered share card — brand header, photo / initials, lead name,
/// phone, and a labelled details panel. Fixed light palette: the output
/// is a standalone image, so it must not inherit the device's dark mode.
struct LeadShareCard: View {
    let data: LeadShareCardData

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
                if let phone = data.phone, !phone.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Brand.red)
                        Text(phone)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Brand.ink)
                    }
                }
                detailPanel
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: LeadShareCardBuilder.cardSize.width,
               height: LeadShareCardBuilder.cardSize.height)
        .background(Color.white)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("KinematicMarkMonoWhite")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
            Text("KINEMATIC")
                .font(.system(size: 16, weight: .black))
                .tracking(2.5)
                .foregroundColor(.white)
            Spacer()
            Text("LEAD")
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

    /// Full-width hero banner sitting directly under the header — the lead's
    /// photo is the centrepiece. Roughly 37% of the card height. When there's
    /// no photo, a same-sized subtle block carries the large initials.
    private static let heroHeight: CGFloat = 250

    @ViewBuilder
    private var heroView: some View {
        if let photo = data.photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: LeadShareCardBuilder.cardSize.width,
                       height: Self.heroHeight)
                .clipped()
        } else {
            ZStack {
                Rectangle().fill(Brand.red.opacity(0.10))
                Text(data.initials)
                    .font(.system(size: 96, weight: .black))
                    .foregroundColor(Brand.red.opacity(0.85))
            }
            .frame(width: LeadShareCardBuilder.cardSize.width,
                   height: Self.heroHeight)
            .clipped()
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        let rows = detailRows()
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
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
                            .frame(width: 104, alignment: .leading)
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

    private func detailRows() -> [(String, String)] {
        var rows: [(String, String)] = []
        if let v = data.createdText, !v.isEmpty { rows.append(("Created", v)) }
        if let v = data.ownerName, !v.isEmpty { rows.append(("Owner", v)) }
        if let v = data.dealerName, !v.isEmpty { rows.append(("Dealer", v)) }
        if let v = data.brand, !v.isEmpty { rows.append(("Brand", v)) }
        if let v = data.block, !v.isEmpty { rows.append(("Block", v)) }
        return rows
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

// MARK: - Share sheet

/// UIActivityViewController wrapper for the rendered share image. Sharing
/// a plain UIImage keeps WhatsApp / Messages / Save Image in the sheet —
/// same pattern as ActivityShareSheet in CRMReportsView.
struct LeadShareActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
