import SwiftUI
import Combine
import CoreLocation

/// Seed values for the lead-create form. Used by the "Scan business card"
/// flow to land the rep on the normal create form pre-filled. Only the
/// plain text identity / contact / company fields are seeded — every row
/// still renders through the form's existing `fieldOverrides` gating, so
/// a value seeded here for an admin-hidden field simply never shows (and
/// `buildBody` won't persist it). All fields optional.
struct LeadCreatePrefill {
    var firstName: String? = nil
    var lastName: String? = nil
    var company: String? = nil
    var title: String? = nil
    var email: String? = nil
    var phone: String? = nil
}

struct LeadCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locator = OneShotLocationProvider()
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    /// Extra reach numbers beyond the primary mobile. Multi-value
    /// add/remove editor (mirrors the web AlternateMobiles chip list).
    /// Persisted to the `alternate_mobiles` text[] column.
    @State private var alternateMobiles: [String] = []
    @State private var source = "web"
    // Source picker — backed by /api/v1/crm/lead-sources (now scoped
    // by client_id so Tata reps only see Tata sources like Site Visit).
    @State private var sources: [CRMLeadSource] = []
    @State private var sourceId: String = ""
    // Default to B2C. Fail-safe: if the /crm/settings business_type hasn't
    // resolved yet, failed (401 on a dead session / offline), or the client_id
    // is missing so `isTata` reads false, we must NOT leak the B2B option or
    // silently save a B2B lead. Every configured tenant on this build is either
    // B2C-locked or explicitly "both"; a genuine "both" tenant gets the picker
    // (below) and can switch to B2B deliberately.
    @State private var isB2C = true
    /// Today's lead-target progress badge (achieved/target).
    @State private var target: CRMTarget?

    // B2B fields
    @State private var company = ""
    @State private var title = ""
    @State private var industry = ""

    // B2C fields
    @State private var dateOfBirth: Date = Date()
    @State private var hasDOB = false
    @State private var gender = "prefer_not_to_say"
    @State private var preferredChannel = "email"
    @State private var addressLine1 = ""
    @State private var addressLine2 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var postalCode = ""
    @State private var country = "India"
    @State private var marketingConsent = false
    @State private var whatsappConsent = false
    // DPDP §5/§6 — at-collection notice + primary consent for the lead's
    // personal data. Recorded in the crm_consents ledger via the `_consent`
    // block on create. Distinct from the marketing/WhatsApp opt-ins above.
    @State private var dataConsent = false

    /// Admin-defined custom fields for leads, scoped to the user's org role.
    @StateObject private var customFields = CustomFieldsModel()
    @StateObject private var productLines = ProductLinesModel()
    /// Built-in field overrides (hide / relabel / required) from
    /// /api/v1/crm/settings. Reads the same source the web form does
    /// so DOB / Gender / Preferred Channel disappear here when the
    /// admin has hidden them via Settings → Custom Fields.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()

    /// Tata Tiscon affordance — checkbox in the create form that asks
    /// the backend to echo back an `auto_log_site_visit_prefill` block
    /// (lead_id + suggested subject + type). The compose screen reads
    /// that block to land pre-filled, so the rep can attach notes +
    /// outcome before actually saving the activity. Default OFF —
    /// otherwise every Tata Champion would be bounced into the compose
    /// screen on every lead save, even when they didn't visit.
    @State private var logAsSiteVisit = false

    // Save flow state — surfaced so we can show a spinner on the toolbar
    // button and keep the sheet open if the server rejects the body.
    @State private var saving: Bool = false
    @State private var saveError: String?

    // MARK: - Inline "Fill with voice" (push-to-talk / walkie-talkie)
    //
    // Press and HOLD the mic to record, RELEASE to submit: on release we stop,
    // transcribe, call extract-lead and hand the result to `apply(_:)`, which
    // maps the fields onto this form (still gated by the field-override
    // contract). The live listening + processing animation renders INLINE as an
    // overlay layered on this same view (`voiceOverlay`) — there is NO separate
    // voice sheet, screen or navigation destination. Voice is input only.
    @StateObject private var voice = KiniVoiceRecognizer()
    @State private var voicePhase: VoicePhase = .idle
    @State private var voiceTranscript = ""
    /// True while a single press-and-hold is in flight — guards the press-down
    /// handler from re-firing on every drag-move callback.
    @State private var isHoldingMic = false
    /// Set when the finger has slid far off the mic; releasing then cancels
    /// instead of submitting.
    @State private var voiceWillCancel = false

    /// State machine for the inline push-to-talk mic control.
    private enum VoicePhase: Equatable {
        case idle           // nothing happening — collapsed
        case listening      // holding the mic, recording live
        case processing     // released with a transcript; calling extract-lead
        case success        // fields applied — brief tick before collapsing
        case error(String)  // friendly failure message
    }

    /// Local brand red (0xE0/0x1E/0x2C) for the voice surfaces — matches the
    /// voice orb and the removed voice sheet. `Brand.red` is a slightly darker
    /// 0xD0; the mic accent uses this brighter red.
    private let voiceBrandRed = Color(red: 0xE0/255, green: 0x1E/255, blue: 0x2C/255)

    /// Returns true when the lead was created (or queued offline); false
    /// when the parent's create call failed. The form keeps itself open
    /// on false so the rep can adjust + retry — the previous Void
    /// signature dismissed unconditionally and swallowed every backend
    /// error, which is the "leads not getting saved" symptom from users.
    let onSubmit: ([String: Any]) async -> Bool

    /// Default + prefill initializer. The `prefill` path seeds the @State
    /// fields for the "Scan business card" flow; it only sets plain text
    /// values and changes no other behavior. Seeding @State requires
    /// assigning the underlying State wrappers in init (a later .onAppear
    /// would clobber what the rep starts editing).
    init(prefill: LeadCreatePrefill? = nil, onSubmit: @escaping ([String: Any]) async -> Bool) {
        self.onSubmit = onSubmit
        if let p = prefill {
            if let v = p.firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                _firstName = State(initialValue: v)
            }
            if let v = p.lastName?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                _lastName = State(initialValue: v)
            }
            if let v = p.company?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                _company = State(initialValue: v)
            }
            if let v = p.title?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                _title = State(initialValue: v)
            }
            if let v = p.email?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                _email = State(initialValue: v)
            }
            // Match the phone field's input rule (digits only, max 10) so a
            // seeded number lines up with what the rep would have typed.
            if let raw = p.phone {
                let digits = String(raw.filter { $0.isNumber }.prefix(10))
                if !digits.isEmpty { _phone = State(initialValue: digits) }
            }
        }
    }

    /// Server-side business_type ("b2c" / "b2b"). Loaded once when the form
    /// opens via /crm/settings. Used as a fallback for the Tata gate so the
    /// Products of Interest section + site-visit toggle still render when
    /// `Session.currentUser.clientId` is stale or missing (legacy sessions
    /// stored before the User decoder picked up `client_id` — Android reads
    /// it from a live DataStore Flow, iOS reads it from a one-shot
    /// UserDefaults blob, so iOS users on an old install saw the picker
    /// disappear while Android users on the same backend kept it).
    @State private var businessType: String?
    /// True once the /crm/settings fetch has resolved (success or failure).
    /// The B2B/B2C picker is deferred behind this so a b2c-locked tenant
    /// (e.g. BMW — not Tata, so `ClientFeatures.isTataTiscon` is false) never
    /// flashes the B2B option before business_type arrives. Mirrors the
    /// already-correct deferral in LeadEditView.
    @State private var settingsLoaded = false

    // Tata Tiscon requires the submission location to be captured automatically
    // and is non-editable + mandatory (parity with the web lead form). Other
    // clients keep the optional "Use current location" + manual entry flow.
    private var isTata: Bool {
        ClientFeatures.isTataTiscon || (businessType?.lowercased() == "b2c")
    }
    private var hasValidCoords: Bool {
        Double(latitude.trimmingCharacters(in: .whitespaces)) != nil &&
        Double(longitude.trimmingCharacters(in: .whitespaces)) != nil
    }
    /// Sticky-bottom Create button gate. Same single hard rule as the
    /// toolbar Save: last_name required unless the admin flipped it
    /// optional via field overrides.
    private var saveCtaEnabled: Bool {
        if saving { return false }
        let req = fieldOverrides.requiredFor("last_name", defaultRequired: true, isB2C: isB2C)
        if req && lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                // KINI "Fill with voice" — INLINE push-to-talk. Press and HOLD
                // the mic to record, release to fill. On release we stop,
                // transcribe, call extract-lead and apply() the fields onto the
                // form (fills only fields the admin hasn't hidden — apply()
                // writes @State; the override gating still controls render +
                // save). The live listening + processing animation renders
                // inline over this view (`voiceOverlay`) — no separate sheet or
                // screen. Voice is input only.
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color(red: 1, green: 0.30, blue: 0.30), voiceBrandRed],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 40, height: 40)
                                .scaleEffect(voicePhase == .listening ? 1.14 : 1)
                                .shadow(color: voiceBrandRed.opacity(voicePhase == .listening ? 0.5 : 0),
                                        radius: 10, y: 3)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Fill with voice")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text(micHintText)
                                .font(.system(size: 12))
                                .foregroundColor(voicePhase == .listening ? voiceBrandRed : .secondary)
                        }
                        Spacer()
                        Image(systemName: "sparkles").foregroundColor(voiceBrandRed)
                    }
                    // Not a Button — a plain row carrying the press-and-hold
                    // gesture, so the DragGesture's press-down / release drive
                    // recording directly without fighting a Button's tap.
                    .contentShape(Rectangle())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: voicePhase)
                    .gesture(micHoldGesture)
                    .disabled(!voice.isAvailable)
                    .accessibilityLabel("Fill with voice")
                    .accessibilityHint("Hold to speak, release to fill the form")
                } footer: {
                    Text("Hold the mic and describe the lead — release and KINI fills the form.")
                }

                if let t = target, t.hasTarget {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: t.achieved >= t.target ? "checkmark.seal.fill" : "target")
                                .foregroundColor(t.achieved >= t.target ? Brand.success : Brand.red)
                            Text("Today's lead target")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text("\(t.achieved)/\(t.target)")
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(t.achieved >= t.target ? Brand.success : Brand.red)
                        }
                    }
                }

                // B2B/B2C picker — shown ONLY for a tenant whose crm_settings
                // business_type is explicitly "both". Every other case is
                // locked: "b2c" / nil / Tata → B2C; "b2b" → B2B (see the .task
                // + isB2C default). Gating on == "both" (rather than !isTata)
                // means a dead-session or racing fetch — where business_type is
                // nil and the client_id (hence `isTata`) may be missing — can
                // never leak the B2B picker; it stays on the fail-safe B2C default.
                if settingsLoaded && businessType?.lowercased() == "both" {
                    Section {
                        Picker("Lead type", selection: $isB2C) {
                            Text("B2B (Business)").tag(false)
                            Text("B2C (Consumer)").tag(true)
                        }.pickerStyle(.segmented)
                    }
                }

                Section("Identity") {
                    if !fieldOverrides.isHidden("first_name", isB2C: isB2C) {
                        labelledField(
                            label: fieldOverrides.labelFor("first_name", defaultLabel: "First name", isB2C: isB2C),
                            // Match web default — first name is required.
                            required: fieldOverrides.requiredFor("first_name", defaultRequired: true, isB2C: isB2C),
                            text: $firstName,
                        )
                    }
                    if !fieldOverrides.isHidden("last_name", isB2C: isB2C) {
                        labelledField(
                            label: fieldOverrides.labelFor("last_name", defaultLabel: "Last name", isB2C: isB2C),
                            required: fieldOverrides.requiredFor("last_name", defaultRequired: true, isB2C: isB2C),
                            text: $lastName,
                        )
                    }
                }
                Section("Contact") {
                    // Email field hidden for Tata Tiscon — their FE walk-in
                    // flow doesn't collect email; prompting just to skip it
                    // adds friction. Admin override stacks on top.
                    if !ClientFeatures.isTataTiscon && !fieldOverrides.isHidden("email", isB2C: isB2C) {
                        labelledField(
                            label: fieldOverrides.labelFor("email", defaultLabel: "Email", isB2C: isB2C),
                            required: fieldOverrides.requiredFor("email", defaultRequired: false, isB2C: isB2C),
                            text: $email,
                            keyboard: .emailAddress,
                            autocapitalize: false,
                        )
                    }
                    if !fieldOverrides.isHidden("phone", isB2C: isB2C) {
                        labelledField(
                            label: fieldOverrides.labelFor("phone", defaultLabel: "Primary Mobile", isB2C: isB2C),
                            required: fieldOverrides.requiredFor("phone", defaultRequired: true, isB2C: isB2C),
                            text: $phone,
                            keyboard: .phonePad,
                        )
                    }
                    // Alternate numbers — parallel multi-value list to the
                    // primary mobile (mirrors the web AlternateMobiles chip
                    // editor). Gated on the same override contract as every
                    // other built-in field.
                    if !fieldOverrides.isHidden("alternate_mobiles", isB2C: isB2C) {
                        alternateNumbersEditor(
                            label: fieldOverrides.labelFor("alternate_mobiles", defaultLabel: "Alternate Number", isB2C: isB2C),
                            required: fieldOverrides.requiredFor("alternate_mobiles", defaultRequired: false, isB2C: isB2C),
                        )
                    }
                    // Source picker — bound to crm_lead_sources so reps see
                    // the same options admins configure on the web console
                    // (e.g. Site Visit on Tata Tiscon). Loaded async; falls
                    // back to "Unspecified" while empty. Override-aware
                    // (hide / relabel / require) like every other field.
                    if !fieldOverrides.isHidden("source_id", isB2C: isB2C) {
                        let req = fieldOverrides.requiredFor("source_id", defaultRequired: false, isB2C: isB2C)
                        let lbl = fieldOverrides.labelFor("source_id", defaultLabel: "Source", isB2C: isB2C) + (req ? " *" : "")
                        Picker(lbl, selection: $sourceId) {
                            Text("— Unspecified —").tag("")
                            ForEach(sources, id: \.id) { s in
                                Text(s.name).tag(s.id)
                            }
                        }
                    }
                }
                if !isB2C {
                    Section("Business Details") {
                        if !fieldOverrides.isHidden("company", isB2C: false) {
                            labelledField(
                                label: fieldOverrides.labelFor("company", defaultLabel: "Company", isB2C: false),
                                required: fieldOverrides.requiredFor("company", defaultRequired: false, isB2C: false),
                                text: $company,
                            )
                        }
                        if !fieldOverrides.isHidden("title", isB2C: false) {
                            labelledField(
                                label: fieldOverrides.labelFor("title", defaultLabel: "Job Title", isB2C: false),
                                required: fieldOverrides.requiredFor("title", defaultRequired: false, isB2C: false),
                                text: $title,
                            )
                        }
                        if !fieldOverrides.isHidden("industry", isB2C: false) {
                            labelledField(
                                label: fieldOverrides.labelFor("industry", defaultLabel: "Industry", isB2C: false),
                                required: fieldOverrides.requiredFor("industry", defaultRequired: false, isB2C: false),
                                text: $industry,
                            )
                        }
                    }
                } else {
                    // Business Details on a B2C lead — only when an admin
                    // explicitly un-hid company/title/industry (persisted
                    // hidden:false). Keeps the B2B-only default for tenants
                    // that never touched these keys. Mirrors the web forms.
                    if fieldOverrides.didLoad && (
                        fieldOverrides.explicitlyShownOnB2C("company")
                        || fieldOverrides.explicitlyShownOnB2C("title")
                        || fieldOverrides.explicitlyShownOnB2C("industry")
                    ) {
                        Section("Business Details") {
                            if fieldOverrides.explicitlyShownOnB2C("company") {
                                labelledField(
                                    label: fieldOverrides.labelFor("company", defaultLabel: "Company", isB2C: true),
                                    required: fieldOverrides.requiredFor("company", defaultRequired: false, isB2C: true),
                                    text: $company,
                                )
                            }
                            if fieldOverrides.explicitlyShownOnB2C("title") {
                                labelledField(
                                    label: fieldOverrides.labelFor("title", defaultLabel: "Job Title", isB2C: true),
                                    required: fieldOverrides.requiredFor("title", defaultRequired: false, isB2C: true),
                                    text: $title,
                                )
                            }
                            if fieldOverrides.explicitlyShownOnB2C("industry") {
                                labelledField(
                                    label: fieldOverrides.labelFor("industry", defaultLabel: "Industry", isB2C: true),
                                    required: fieldOverrides.requiredFor("industry", defaultRequired: false, isB2C: true),
                                    text: $industry,
                                )
                            }
                        }
                    }
                    // Customer Details section — each field individually
                    // gated against the admin's hide flag so the form
                    // matches what the rep sees on the web. The Section
                    // header is skipped entirely when all three fields
                    // are hidden so we don't render an empty bucket.
                    // Defer rendering admin-gated rows until the override
                    // map has loaded — otherwise the form races the network
                    // and briefly shows fields (with default labels) the
                    // admin had hidden in the web console.
                    if fieldOverrides.didLoad && (
                        !fieldOverrides.isHidden("date_of_birth", isB2C: isB2C)
                        || !fieldOverrides.isHidden("gender", isB2C: isB2C)
                        || !fieldOverrides.isHidden("preferred_contact_method", isB2C: isB2C)
                    ) {
                        Section("Customer Details") {
                            if !fieldOverrides.isHidden("date_of_birth", isB2C: isB2C) {
                                Toggle("Set date of birth", isOn: $hasDOB)
                                if hasDOB {
                                    DatePicker("Date of birth", selection: $dateOfBirth, displayedComponents: .date)
                                }
                            }
                            if !fieldOverrides.isHidden("gender", isB2C: isB2C) {
                                Picker("Gender", selection: $gender) {
                                    Text("Male").tag("male")
                                    Text("Female").tag("female")
                                    Text("Other").tag("other")
                                    Text("Prefer not to say").tag("prefer_not_to_say")
                                }
                            }
                            if !fieldOverrides.isHidden("preferred_contact_method", isB2C: isB2C) {
                                Picker("Preferred channel", selection: $preferredChannel) {
                                    ForEach(["email", "phone", "whatsapp", "sms"], id: \.self) { Text($0.capitalized).tag($0) }
                                }
                            }
                        }
                    }
                    Section("Address") {
                        AddressSearchField(addressLine1: $addressLine1, city: $city, state: $state, postalCode: $postalCode)
                        if !fieldOverrides.isHidden("address_line1", isB2C: true) {
                            labelledField(
                                label: fieldOverrides.labelFor("address_line1", defaultLabel: "Address line 1", isB2C: true),
                                required: fieldOverrides.requiredFor("address_line1", defaultRequired: false, isB2C: true),
                                text: $addressLine1,
                            )
                        }
                        if !fieldOverrides.isHidden("address_line2", isB2C: true) {
                            labelledField(
                                label: fieldOverrides.labelFor("address_line2", defaultLabel: "Address line 2", isB2C: true),
                                required: false,
                                text: $addressLine2,
                            )
                        }
                        if !fieldOverrides.isHidden("city", isB2C: true) {
                            labelledField(
                                label: fieldOverrides.labelFor("city", defaultLabel: "City", isB2C: true),
                                required: fieldOverrides.requiredFor("city", defaultRequired: false, isB2C: true),
                                text: $city,
                            )
                        }
                        if !fieldOverrides.isHidden("state", isB2C: true) {
                            labelledField(
                                label: fieldOverrides.labelFor("state", defaultLabel: "State", isB2C: true),
                                required: fieldOverrides.requiredFor("state", defaultRequired: false, isB2C: true),
                                text: $state,
                            )
                        }
                        if !fieldOverrides.isHidden("postal_code", isB2C: true) {
                            labelledField(
                                label: fieldOverrides.labelFor("postal_code", defaultLabel: "Postal code", isB2C: true),
                                required: fieldOverrides.requiredFor("postal_code", defaultRequired: false, isB2C: true),
                                text: $postalCode,
                                keyboard: .numberPad,
                            )
                        }
                        if !fieldOverrides.isHidden("country", isB2C: true) {
                            labelledField(
                                label: fieldOverrides.labelFor("country", defaultLabel: "Country", isB2C: true),
                                required: false,
                                text: $country,
                            )
                        }
                    }
                    // Consent toggles only render when the admin hasn't
                    // hidden BOTH. We drop the header too — an empty
                    // "Consent" section reads as a bug, not a feature.
                    let showMarketing = !fieldOverrides.isHidden("marketing_consent", isB2C: true)
                    let showWhatsapp  = !fieldOverrides.isHidden("whatsapp_consent", isB2C: true)
                    if showMarketing || showWhatsapp {
                        Section("Consent") {
                            if showMarketing {
                                Toggle(fieldOverrides.labelFor("marketing_consent", defaultLabel: "Marketing emails", isB2C: true), isOn: $marketingConsent)
                            }
                            if showWhatsapp {
                                Toggle(fieldOverrides.labelFor("whatsapp_consent", defaultLabel: "WhatsApp messages", isB2C: true), isOn: $whatsappConsent)
                            }
                        }
                    }
                }

                // DPDP §5/§6 — at-collection notice + primary consent (B2B + B2C).
                Section("Data Collection & Consent") {
                    Text("We collect this person’s name, contact details and the information entered here to create and manage their record and to contact them, as described in our Privacy Notice. They may access, correct or erase their data, or raise a grievance, at any time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("The individual has been shown this notice and consents to the collection and processing of their personal data.", isOn: $dataConsent)
                }

                // Admin-defined custom fields for this user's hierarchy role.
                CustomFieldsSection(model: customFields)

                // Multi-row product picker — drives custom_fields.product_lines
                // and mirrors row 0 onto the legacy product_interested /
                // quantity / measuring_unit / estimated_amount keys.
                // Hidden for Kaiyo/Tata, who now capture the basket in the
                // Convert dialog instead of on the lead form; every other tenant
                // keeps it (empty by default, only persists picked rows).
                if !ClientFeatures.isTataTiscon {
                    ProductLinesSection(model: productLines)
                }

                // Geo-location is captured automatically — no button, no manual
                // entry. We start a one-shot GPS fix when the form opens so the
                // coordinates are ready by the time the rep taps Save.
                // Hidden for the Kinematic tenant (inside sales doesn't geo-tag).
                if !ClientFeatures.isKinematic {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "location.fill").foregroundColor(.accentColor)
                        if hasValidCoords {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Location captured").font(.subheadline)
                                Text("\(latitude), \(longitude)").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        } else if locator.isLocating {
                            Text("Capturing current location…")
                            Spacer()
                            ProgressView()
                        } else {
                            Text("Location will be captured automatically")
                            Spacer()
                            Button("Retry") { locator.requestLocation() }
                        }
                    }
                    if let msg = locator.errorMessage {
                        Text(msg).font(.caption).foregroundColor(.secondary)
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("Your current location is captured automatically and saved with the lead.")
                }
                .onReceive(locator.$coordinate) { coord in
                    guard let c = coord else { return }
                    latitude = String(format: "%.6f", c.latitude)
                    longitude = String(format: "%.6f", c.longitude)
                    // Auto-populate address / city / state / postal
                    // from the GPS fix via CLGeocoder (built-in, free —
                    // no Google API key needed on iOS). Only fills
                    // fields the rep hasn't already touched so a value
                    // they typed in wins over the geocode. Best-effort:
                    // a geocode failure leaves the form blank for
                    // manual entry, no toast.
                    Task {
                        let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
                        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
                            await MainActor.run {
                                let formattedLine = [placemark.subThoroughfare, placemark.thoroughfare]
                                    .compactMap { $0 }
                                    .joined(separator: " ")
                                if addressLine1.isEmpty, !formattedLine.isEmpty { addressLine1 = formattedLine }
                                if city.isEmpty, let v = placemark.locality { city = v }
                                if state.isEmpty, let v = placemark.administrativeArea { state = v }
                                if postalCode.isEmpty, let v = placemark.postalCode { postalCode = v }
                            }
                        }
                    }
                }
                }

                // Tata Tiscon site-visit affordance — most leads are added
                // while the rep is physically at the consumer / dealer
                // counter, so we default it on. Backend spawns the
                // matching activity in the same round-trip.
                if isTata {
                    Section {
                        Toggle("Also log this lead as a Site Visit activity", isOn: $logAsSiteVisit)
                    } footer: {
                        Text("Creates a completed Site Visit activity tied to this lead — visible on the lead detail timeline. When the First Visit Date custom field is filled in, the activity is recorded as a First Site Visit instead.")
                    }
                }
            }
            // Sticky Create button pinned to the bottom safe area so it
            // stays in reach no matter how far the rep has scrolled —
            // matches the Android Scaffold.bottomBar version. Toolbar
            // Save above is kept for power users + parity with the rest
            // of the app's confirm/cancel pattern.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        if !ClientFeatures.isKinematic && !hasValidCoords { locator.requestLocation() }
                        Task {
                            saving = true
                            // Admin-required custom fields (crm_custom_field_defs
                            // .required) block submit the same way built-in
                            // required fields do — the backend would accept
                            // the row without them otherwise.
                            let missingCustom = customFields.missingRequiredLabels
                            guard missingCustom.isEmpty else {
                                saving = false
                                saveError = "Please fill: \(missingCustom.joined(separator: ", "))"
                                return
                            }
                            let body = buildBody()
                            guard !body.isEmpty else {
                                saving = false
                                saveError = "Fill in the required fields before saving."
                                return
                            }
                            let ok = await onSubmit(body)
                            saving = false
                            if ok {
                                dismiss()
                            } else {
                                saveError = "Couldn't save this lead. Check the details and try again."
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if saving { ProgressView().tint(.white) }
                            Text(saving ? "Saving…" : "Create lead")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(saveCtaEnabled ? Brand.red : Color.gray.opacity(0.4))
                        )
                    }
                    .disabled(!saveCtaEnabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(.bar)
            }
            .navigationTitle("New Lead")
            .task { target = await CRMService.shared.myTarget() }
            .task { await customFields.load(entity: "lead") }
            .task { await productLines.load() }
            .task { await fieldOverrides.load() }
            .task { sources = await CRMService.shared.listLeadSources() }
            .task {
                // Resolve businessType so the Tata-equivalent gate works
                // even when Session.currentUser.clientId is stale.
                businessType = await CRMService.shared.getCRMSettings()?.business_type
                // Lock the lead type from the tenant's business_type: "b2c" →
                // consumer, "b2b" → business. "both" leaves the user's choice
                // (picker shown below); a nil / failed fetch stays on the
                // fail-safe B2C default so a racing or dead session can never
                // leak the B2B option or silently persist a B2B lead.
                switch businessType?.lowercased() ?? "" {
                case "b2c": isB2C = true
                case "b2b": isB2C = false
                default:    break
                }
                // Flip regardless of success/failure so the picker (deferred
                // above, and only shown for a "both" tenant) resolves.
                settingsLoaded = true
            }
            .onAppear {
                // Tata Tiscon only ever creates B2C (consumer) leads.
                if isTata { isB2C = true }
                // Auto-capture the submission location as soon as the form
                // opens so it's attached by the time the rep taps Save.
                // Kinematic doesn't geo-tag leads, so never request GPS there.
                if !ClientFeatures.isKinematic && !hasValidCoords && !locator.isLocating {
                    locator.requestLocation()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        // Fetch the location on Save if we still don't have a
                        // fix (e.g. permission was just granted) — best effort.
                        if !ClientFeatures.isKinematic && !hasValidCoords { locator.requestLocation() }
                        Task {
                            saving = true
                            // Admin-required custom fields (crm_custom_field_defs
                            // .required) block submit the same way built-in
                            // required fields do — the backend would accept
                            // the row without them otherwise.
                            let missingCustom = customFields.missingRequiredLabels
                            guard missingCustom.isEmpty else {
                                saving = false
                                saveError = "Please fill: \(missingCustom.joined(separator: ", "))"
                                return
                            }
                            let body = buildBody()
                            // Empty body means the require-gate caught a
                            // bad state (e.g. last_name required + blank);
                            // surface that to the rep instead of POSTing
                            // `{}` to the server and silently dismissing.
                            guard !body.isEmpty else {
                                saving = false
                                saveError = "Fill in the required fields before saving."
                                return
                            }
                            let ok = await onSubmit(body)
                            saving = false
                            if ok {
                                dismiss()
                            } else {
                                saveError = "Couldn't save this lead. Check the details and try again."
                            }
                        }
                    } label: {
                        if saving { ProgressView() } else { Text("Save") }
                    }
                    // Save is gated on whatever the admin marked required.
                    // Default: last_name is required (matches leadCreateSchema)
                    // — override flips the gate off when an admin sets
                    // last_name optional via field overrides.
                    .disabled(
                        saving ||
                        (fieldOverrides.requiredFor("last_name", defaultRequired: true, isB2C: isB2C)
                         && lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
            .alert("Save failed",
                   isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            // Inline listening / processing animation layered over the form
            // (NOT a sheet). Placed after the sticky Create bar so it covers the
            // whole screen while active.
            .overlay { voiceOverlay }
            .onDisappear { voice.stop() }
        }
    }

    // MARK: - Inline voice (push-to-talk) plumbing

    /// Hint under the "Fill with voice" title, reflecting the current phase.
    private var micHintText: String {
        switch voicePhase {
        case .listening:  return "Listening… release to fill"
        case .processing: return "Reading…"
        case .success:    return "Filled from your voice"
        case .error:      return "Hold to try again"
        case .idle:       return "Hold to speak · release to fill"
        }
    }

    /// True only while actively recording — drives the orb's amplitude
    /// reactivity + the live transcript preview.
    private var isVoiceActive: Bool {
        if case .listening = voicePhase { return true }
        return false
    }

    /// Press-and-HOLD gesture. `minimumDistance: 0` makes `.onChanged` fire on
    /// touch-down; `.onEnded` fires on release. Sliding far off the mic before
    /// release cancels instead of submitting.
    private var micHoldGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isHoldingMic {
                    isHoldingMic = true
                    beginVoiceHold()
                }
                // Squared-distance compare (no sqrt) — slide > 140pt off the
                // mic to arm cancel-on-release.
                let dx = value.translation.width
                let dy = value.translation.height
                voiceWillCancel = (dx * dx + dy * dy) > 140 * 140
            }
            .onEnded { _ in
                guard isHoldingMic else { return }
                isHoldingMic = false
                let cancelled = voiceWillCancel
                voiceWillCancel = false
                endVoiceHold(cancelled: cancelled)
            }
    }

    /// Press-down: enter the listening state and start the recognizer, which
    /// requests speech + mic permission if needed.
    private func beginVoiceHold() {
        // Never interrupt an in-flight extraction with a fresh hold.
        if case .processing = voicePhase { return }
        voiceTranscript = ""
        withAnimation(.easeOut(duration: 0.2)) { voicePhase = .listening }
        voice.start { text in voiceTranscript = text }
    }

    /// Release: stop recording and, if we captured something usable, transcribe
    /// → extract-lead → apply(). Cancelled / empty / too-short holds collapse
    /// silently, keeping whatever the rep already typed.
    private func endVoiceHold(cancelled: Bool) {
        guard case .listening = voicePhase else { return }
        voice.stop()
        let t = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if cancelled || t.count < 2 {
            withAnimation(.easeOut(duration: 0.2)) { voicePhase = .idle }
            voiceTranscript = ""
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { voicePhase = .processing }
        Task { @MainActor in
            do {
                let e = try await CRMService.shared.extractLead(transcript: t, isB2C: isB2C)
                apply(e)
                withAnimation(.easeOut(duration: 0.2)) { voicePhase = .success }
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                if case .success = voicePhase {
                    withAnimation(.easeOut(duration: 0.25)) { voicePhase = .idle }
                }
            } catch {
                withAnimation(.easeOut(duration: 0.2)) { voicePhase = .error(voiceFriendly(error)) }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if case .error = voicePhase {
                    withAnimation(.easeOut(duration: 0.25)) { voicePhase = .idle }
                }
            }
        }
    }

    /// Friendly failure text — mirrors the removed voice sheet, including the
    /// monthly-limit case.
    private func voiceFriendly(_ error: Error) -> String {
        let s = String(describing: error).lowercased()
        if s.contains("usage limit") || s.contains("monthly") {
            return "KINI has hit its monthly AI limit. Try again after it resets, or type the details in."
        }
        return "Couldn't read that — please try again, or type the details in."
    }

    private var voiceHeadline: String {
        switch voicePhase {
        case .listening:  return "LISTENING…"
        case .processing: return "READING…"
        case .success:    return "FILLED FROM VOICE"
        case .error:      return "COULDN'T READ THAT"
        case .idle:       return ""
        }
    }

    private var voiceHeadlineColor: Color {
        if case .success = voicePhase { return Brand.success }
        return voiceBrandRed
    }

    /// The inline listening / processing panel, layered over the form via
    /// `.overlay`. Non-interactive (`allowsHitTesting(false)`) so it never
    /// steals the in-flight press-and-hold touch from the mic underneath — the
    /// mic's DragGesture keeps receiving the release event.
    @ViewBuilder
    private var voiceOverlay: some View {
        if voicePhase != .idle {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    VoiceInputOrb(level: voice.level, active: isVoiceActive)
                        .frame(width: 200, height: 200)

                    Text(voiceHeadline)
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.5)
                        .foregroundColor(voiceHeadlineColor)

                    if isVoiceActive {
                        Text(voiceTranscript.isEmpty
                             ? "Describe the lead — name, mobile, and what they need"
                             : voiceTranscript)
                            .font(.system(size: 16, weight: voiceTranscript.isEmpty ? .regular : .semibold))
                            .foregroundColor(voiceTranscript.isEmpty ? .secondary : .primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(5)
                            .padding(.horizontal, 28)
                    }

                    switch voicePhase {
                    case .processing:
                        ProgressView().tint(voiceBrandRed)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(Brand.success)
                    case .error(let msg):
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(voiceBrandRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    default:
                        if let perr = voice.permissionError {
                            Text(perr)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                    }
                }
                .padding(.vertical, 24)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Map KINI-extracted fields onto the form's @State. Only non-empty values
    /// overwrite (so a partial transcript never wipes what the rep already
    /// typed). Hidden fields are harmless — the override gating still controls
    /// what renders and `buildBody` still strips admin-hidden keys on save.
    private func apply(_ e: ExtractedLead) {
        func clean(_ v: String?) -> String? {
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty == false) ? t : nil
        }
        if let v = clean(e.firstName) { firstName = v }
        if let v = clean(e.lastName) { lastName = v }
        if let v = clean(e.email) { email = v.lowercased() }
        if let raw = e.phone {
            let d = String(raw.filter { $0.isNumber }.prefix(10))
            if !d.isEmpty { phone = d }
        }
        if let alts = e.alternateMobiles {
            let cleaned = alts.map { String($0.filter { $0.isNumber }.prefix(10)) }.filter { $0.count == 10 }
            if !cleaned.isEmpty { alternateMobiles = cleaned }
        }
        if let v = clean(e.company) { company = v }
        if let v = clean(e.title) { title = v }
        if let v = clean(e.industry) { industry = v }
        if let v = clean(e.addressLine1) { addressLine1 = v }
        if let v = clean(e.city) { city = v }
        if let v = clean(e.state) { state = v }
        if let v = clean(e.country) { country = v }
        if let g = clean(e.gender)?.lowercased(),
           ["male", "female", "other", "prefer_not_to_say"].contains(g) { gender = g }
        if let ch = clean(e.preferredContactMethod)?.lowercased(),
           ["email", "phone", "whatsapp", "sms"].contains(ch) { preferredChannel = ch }
        if let dob = clean(e.dateOfBirth) {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            if let d = f.date(from: dob) { dateOfBirth = d; hasDOB = true }
        }
        // Source hint → best-effort match against the tenant's source list.
        if let hint = clean(e.sourceHint)?.lowercased(),
           let match = sources.first(where: { $0.name.lowercased().contains(hint) || hint.contains($0.name.lowercased()) }) {
            sourceId = match.id
        }
    }

    /// Plain TextField with the label baked into the placeholder so the
    /// whole row stays tappable in a Form. LabeledContent / a separate
    /// Text label + Spacer both left the field zero-width and reps
    /// couldn't tap into First Name / Last Name / Primary Mobile at
    /// all. The required asterisk is appended to the placeholder
    /// ("First name *") — coloured via a thin overlay so it reads red
    /// without losing the tap target.
    @ViewBuilder
    private func labelledField(
        label: String,
        required: Bool,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        autocapitalize: Bool = true,
    ) -> some View {
        let placeholder = label + (required ? " *" : "")
        // 10-digit-only restriction on phone fields. The backend's
        // leadCreateSchema rejects anything other than exactly 10 digits
        // (it was previously a free-form max(40), which let reps paste
        // in country codes / spaces and break the city / source roll-
        // ups). Strip non-digits + clamp to 10 chars at input time so
        // the rep can't even type an invalid mobile.
        let isPhone = keyboard == .phonePad || keyboard == .numberPad
        return TextField(placeholder, text: Binding(
            get: { text.wrappedValue },
            set: { raw in
                if isPhone {
                    let digits = raw.filter { $0.isNumber }
                    text.wrappedValue = String(digits.prefix(10))
                } else {
                    text.wrappedValue = raw
                }
            },
        ))
        .keyboardType(keyboard)
        .autocapitalization(autocapitalize ? .sentences : .none)
    }

    /// Multi-value editor for `alternate_mobiles`: a header row carrying the
    /// (override-aware) label + an "Add number" button, then one text field
    /// per number with a remove button. Digits/phone keyboard; whitespace is
    /// stripped at input time to match the web's `normalise`.
    @ViewBuilder
    private func alternateNumbersEditor(label: String, required: Bool) -> some View {
        HStack {
            Text(label + (required ? " *" : ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Button {
                alternateMobiles.append("")
            } label: {
                Label("Add number", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
        ForEach(alternateMobiles.indices, id: \.self) { idx in
            HStack(spacing: 8) {
                TextField("Alternate number", text: Binding(
                    get: { idx < alternateMobiles.count ? alternateMobiles[idx] : "" },
                    set: { raw in
                        guard idx < alternateMobiles.count else { return }
                        alternateMobiles[idx] = String(raw.filter { !$0.isWhitespace }.prefix(15))
                    },
                ))
                .keyboardType(.phonePad)
                Button(role: .destructive) {
                    guard idx < alternateMobiles.count else { return }
                    alternateMobiles.remove(at: idx)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundColor(Brand.red)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func buildBody() -> [String: Any] {
        // Helper — only include non-empty trimmed strings. Empty values
        // were tripping the backend's Zod validator (e.g. `email` with
        // `""` fails .email()), which surfaced as "leads not saving".
        func put(_ key: String, _ value: String?, into body: inout [String: Any]) {
            guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
            body[key] = v
        }
        // last_name defaults to required (matches leadCreateSchema).
        // Admin override can flip it optional — keep the empty-body guard
        // in line with whatever requirement the form rendered.
        let lastNameRequired = fieldOverrides.requiredFor("last_name", defaultRequired: true, isB2C: isB2C)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if lastNameRequired && trimmedLast.isEmpty { return [:] }

        var body: [String: Any] = [
            "status": "new",
            "is_b2c": isB2C,
        ]
        if !trimmedLast.isEmpty { body["last_name"] = trimmedLast }
        put("first_name", firstName, into: &body)
        put("email",      email,     into: &body)
        put("phone",      phone,     into: &body)
        // alternate_mobiles — trimmed, non-empty numbers only. Omit the
        // key entirely when the list is empty (matches the web's
        // `form.alternate_mobiles.length ? … : undefined`). Honour the
        // admin's hide flag so a hidden field never silently persists.
        if !fieldOverrides.isHidden("alternate_mobiles", isB2C: isB2C) {
            let alts = alternateMobiles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !alts.isEmpty { body["alternate_mobiles"] = alts }
        }
        // source_id — UUID from /api/v1/crm/lead-sources, picked by the
        // rep above. Old string-source path silently dropped on the
        // server; this is the canonical column.
        if !sourceId.isEmpty { body["source_id"] = sourceId }
        if !isB2C {
            if !fieldOverrides.isHidden("company",  isB2C: false) { put("company",  company,  into: &body) }
            if !fieldOverrides.isHidden("title",    isB2C: false) { put("title",    title,    into: &body) }
            if !fieldOverrides.isHidden("industry", isB2C: false) { put("industry", industry, into: &body) }
        } else {
            // Business fields persist on B2C only when an admin has
            // explicitly un-hidden them (so the value the rep typed saves).
            if fieldOverrides.explicitlyShownOnB2C("company")  { put("company",  company,  into: &body) }
            if fieldOverrides.explicitlyShownOnB2C("title")    { put("title",    title,    into: &body) }
            if fieldOverrides.explicitlyShownOnB2C("industry") { put("industry", industry, into: &body) }
            // Honour the admin's "hidden" flag — fields the rep can't
            // see shouldn't quietly persist a value.
            if hasDOB, !fieldOverrides.isHidden("date_of_birth", isB2C: true) {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                body["date_of_birth"] = f.string(from: dateOfBirth)
            }
            if !fieldOverrides.isHidden("gender", isB2C: true) {
                put("gender", gender, into: &body)
            }
            if !fieldOverrides.isHidden("preferred_contact_method", isB2C: true) {
                put("preferred_contact_method", preferredChannel, into: &body)
            }
            if !fieldOverrides.isHidden("address_line1", isB2C: true) { put("address_line1", addressLine1, into: &body) }
            if !fieldOverrides.isHidden("address_line2", isB2C: true) { put("address_line2", addressLine2, into: &body) }
            if !fieldOverrides.isHidden("city",          isB2C: true) { put("city",          city,         into: &body) }
            if !fieldOverrides.isHidden("state",         isB2C: true) { put("state",         state,        into: &body) }
            if !fieldOverrides.isHidden("postal_code",   isB2C: true) { put("postal_code",   postalCode,   into: &body) }
            if !fieldOverrides.isHidden("country",       isB2C: true) { put("country",       country,      into: &body) }
            if !fieldOverrides.isHidden("marketing_consent", isB2C: true) { body["marketing_consent"] = marketingConsent }
            if !fieldOverrides.isHidden("whatsapp_consent",  isB2C: true) { body["whatsapp_consent"]  = whatsappConsent }
        }
        // Geo coordinates (both B2B + B2C). Only sent when they parse as
        // valid numbers, so a half-typed value never reaches the API.
        if let lat = Double(latitude.trimmingCharacters(in: .whitespaces)) { body["latitude"] = lat }
        if let lon = Double(longitude.trimmingCharacters(in: .whitespaces)) { body["longitude"] = lon }
        // Admin-defined custom fields (scoped to the user's role) merged
        // with the product-lines block. ProductLinesModel.jsonValues
        // contains product_lines + the mirrored legacy keys; merging it
        // last lets it override any stale empty values left by the generic
        // form.
        var cf = customFields.jsonValues
        for (k, v) in productLines.jsonValues { cf[k] = v }
        if !cf.isEmpty { body["custom_fields"] = cf }
        // Tata Tiscon site-visit affordance — backend reads this flag,
        // strips it before persisting the lead, and atomically spawns a
        // completed `site_visit` activity tied to the new lead.
        if isTata && logAsSiteVisit {
            body["_auto_log_site_visit"] = true
        }
        // DPDP §6 — capture consent at collection. Always recorded in the
        // crm_consents ledger; the backend enforces any per-tenant hard gate.
        body["_consent"] = [
            "consented": dataConsent,
            "method": "in_app",
            "notice_version": "2026-07-22",
        ]
        return body
    }
}
