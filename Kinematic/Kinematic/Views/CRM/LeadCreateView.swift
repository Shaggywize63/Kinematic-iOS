import SwiftUI

struct LeadCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var source = "web"
    @State private var isB2C = false

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

    // Photo + custom-fields config (loaded on appear)
    @State private var photoUrl: String?
    @State private var overrides: [String: FieldOverride] = [:]
    @State private var customFields: [CRMCustomField] = []
    @State private var customValues = CustomFieldValues()
    @State private var configLoaded = false
    @State private var validationError: String?

    let onSubmit: ([String: Any]) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Lead type", selection: $isB2C) {
                        Text("B2B (Business)").tag(false)
                        Text("B2C (Consumer)").tag(true)
                    }.pickerStyle(.segmented)
                }

                CRMPhotoSection(title: "Lead Photo (optional)", photoUrl: $photoUrl)

                identitySection
                contactSection

                if !isB2C {
                    businessSection
                } else {
                    customerSection
                    addressSection
                    consentSection
                }

                CustomFieldsSection(fields: customFields, values: $customValues)

                if let err = validationError {
                    Section {
                        Text(err).foregroundColor(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("New Lead")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
            .task { await loadConfig() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var identitySection: some View {
        let firstShown = !isHidden("first_name")
        let lastShown = !isHidden("last_name")
        if firstShown || lastShown {
            Section("Identity") {
                if firstShown {
                    TextField(label("first_name", default: "First name"), text: $firstName)
                }
                if lastShown {
                    TextField(label("last_name", default: "Last name"), text: $lastName)
                }
            }
        }
    }

    @ViewBuilder
    private var contactSection: some View {
        let emailShown = !isHidden("email")
        let phoneShown = !isHidden("phone")
        let sourceShown = !isHidden("source_id") && !isHidden("source")
        if emailShown || phoneShown || sourceShown {
            Section("Contact") {
                if emailShown {
                    TextField(label("email", default: "Email"), text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                if phoneShown {
                    TextField(label("phone", default: "Phone"), text: $phone)
                        .keyboardType(.phonePad)
                }
                if sourceShown {
                    Picker(label("source_id", default: label("source", default: "Source")), selection: $source) {
                        ForEach(["web", "referral", "event", "cold_call", "social", "whatsapp", "other"], id: \.self) {
                            Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var businessSection: some View {
        let cShown = !isHidden("company")
        let tShown = !isHidden("title")
        let iShown = !isHidden("industry")
        if cShown || tShown || iShown {
            Section("Business Details") {
                if cShown { TextField(label("company", default: "Company"), text: $company) }
                if tShown { TextField(label("title", default: "Job Title"), text: $title) }
                if iShown { TextField(label("industry", default: "Industry"), text: $industry) }
            }
        }
    }

    @ViewBuilder
    private var customerSection: some View {
        let dobShown = !isHidden("date_of_birth")
        let genderShown = !isHidden("gender")
        let prefShown = !isHidden("preferred_contact_method")
        if dobShown || genderShown || prefShown {
            Section("Customer Details") {
                if dobShown {
                    Toggle("Set \(label("date_of_birth", default: "date of birth").lowercased())", isOn: $hasDOB)
                    if hasDOB {
                        DatePicker(label("date_of_birth", default: "Date of birth"),
                                   selection: $dateOfBirth,
                                   displayedComponents: .date)
                    }
                }
                if genderShown {
                    Picker(label("gender", default: "Gender"), selection: $gender) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                        Text("Other").tag("other")
                        Text("Prefer not to say").tag("prefer_not_to_say")
                    }
                }
                if prefShown {
                    Picker(label("preferred_contact_method", default: "Preferred channel"),
                           selection: $preferredChannel) {
                        ForEach(["email", "phone", "whatsapp", "sms"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var addressSection: some View {
        let a1 = !isHidden("address_line1")
        let a2 = !isHidden("address_line2")
        let cityShown = !isHidden("city")
        let stateShown = !isHidden("state")
        let postal = !isHidden("postal_code")
        let countryShown = !isHidden("country")
        if a1 || a2 || cityShown || stateShown || postal || countryShown {
            Section("Address") {
                if a1 { TextField(label("address_line1", default: "Address line 1"), text: $addressLine1) }
                if a2 { TextField(label("address_line2", default: "Address line 2"), text: $addressLine2) }
                if cityShown { TextField(label("city", default: "City"), text: $city) }
                if stateShown { TextField(label("state", default: "State"), text: $state) }
                if postal {
                    TextField(label("postal_code", default: "Postal code"), text: $postalCode)
                        .keyboardType(.numberPad)
                }
                if countryShown { TextField(label("country", default: "Country"), text: $country) }
            }
        }
    }

    @ViewBuilder
    private var consentSection: some View {
        let mc = !isHidden("marketing_consent")
        let wc = !isHidden("whatsapp_consent")
        if mc || wc {
            Section("Consent") {
                if mc { Toggle(label("marketing_consent", default: "Marketing emails"), isOn: $marketingConsent) }
                if wc { Toggle(label("whatsapp_consent", default: "WhatsApp messages"), isOn: $whatsappConsent) }
            }
        }
    }

    // MARK: - Config helpers

    private func override(_ key: String) -> FieldOverride? {
        overrides["lead.\(key)"]
    }

    private func isHidden(_ key: String) -> Bool {
        override(key)?.hidden == true
    }

    private func label(_ key: String, default defaultLabel: String) -> String {
        override(key)?.label ?? defaultLabel
    }

    /// Required flag: respects override if present, otherwise the per-field
    /// default. Hidden fields are always treated as not-required to avoid
    /// blocking submit on something the rep can't see.
    private func isRequired(_ key: String, default defaultRequired: Bool) -> Bool {
        if isHidden(key) { return false }
        return override(key)?.required ?? defaultRequired
    }

    // MARK: - Submit

    private var canSubmit: Bool {
        // Match prior behaviour: at minimum need either first name or email
        // unless overrides hide both — in which case we accept anything.
        let firstShown = !isHidden("first_name")
        let emailShown = !isHidden("email")
        if firstShown && firstName.isEmpty == false { return true }
        if emailShown && email.isEmpty == false { return true }
        if !firstShown && !emailShown { return true }
        // No identity entered yet — keep button disabled like before.
        return false
    }

    private func loadConfig() async {
        guard !configLoaded else { return }
        configLoaded = true
        if let s = try? await CRMService.shared.leadFieldOverrides() {
            overrides = s
        }
        if let f = try? await CRMService.shared.listCustomFields(entityType: "lead") {
            customFields = f
        }
    }

    private func submit() async {
        // Enforce admin-marked required fields on visible inputs only.
        if let missing = firstMissingRequired() {
            validationError = "\(missing) is required."
            return
        }
        validationError = nil
        await onSubmit(buildBody())
        dismiss()
    }

    /// Walk the visible built-in fields in display order and return the
    /// first that's missing despite being marked required. Returns nil if
    /// all required fields are satisfied.
    private func firstMissingRequired() -> String? {
        struct Check { let key: String; let label: String; let isEmpty: Bool; let defaultRequired: Bool }
        var checks: [Check] = [
            Check(key: "first_name", label: label("first_name", default: "First name"), isEmpty: firstName.isEmpty, defaultRequired: false),
            Check(key: "last_name",  label: label("last_name",  default: "Last name"),  isEmpty: lastName.isEmpty,  defaultRequired: false),
            Check(key: "email",      label: label("email",      default: "Email"),      isEmpty: email.isEmpty,     defaultRequired: false),
            Check(key: "phone",      label: label("phone",      default: "Phone"),      isEmpty: phone.isEmpty,     defaultRequired: false),
        ]
        if !isB2C {
            checks.append(Check(key: "company",  label: label("company",  default: "Company"),  isEmpty: company.isEmpty,  defaultRequired: false))
            checks.append(Check(key: "title",    label: label("title",    default: "Job Title"), isEmpty: title.isEmpty,    defaultRequired: false))
            checks.append(Check(key: "industry", label: label("industry", default: "Industry"), isEmpty: industry.isEmpty, defaultRequired: false))
        }

        for c in checks {
            if isHidden(c.key) { continue }
            if isRequired(c.key, default: c.defaultRequired) && c.isEmpty {
                return c.label
            }
        }
        return nil
    }

    private func buildBody() -> [String: Any] {
        var body: [String: Any] = [
            "source":     source,
            "status":     "new",
            "is_b2c":     isB2C,
        ]
        // Identity / contact: only include fields not hidden.
        if !isHidden("first_name") { body["first_name"] = firstName }
        if !isHidden("last_name")  { body["last_name"]  = lastName }
        if !isHidden("email")      { body["email"]      = email }
        if !isHidden("phone")      { body["phone"]      = phone }

        if !isB2C {
            if !isHidden("company")  { body["company"]  = company }
            if !isHidden("title")    { body["title"]    = title }
            if !isHidden("industry") { body["industry"] = industry }
        } else {
            if hasDOB && !isHidden("date_of_birth") {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                body["date_of_birth"] = f.string(from: dateOfBirth)
            }
            if !isHidden("gender") { body["gender"] = gender }
            if !isHidden("preferred_contact_method") { body["preferred_contact_method"] = preferredChannel }
            if !isHidden("address_line1") { body["address_line1"] = addressLine1 }
            if !isHidden("address_line2") { body["address_line2"] = addressLine2 }
            if !isHidden("city")          { body["city"]          = city }
            if !isHidden("state")         { body["state"]         = state }
            if !isHidden("postal_code")   { body["postal_code"]   = postalCode }
            if !isHidden("country")       { body["country"]       = country }
            if !isHidden("marketing_consent") { body["marketing_consent"] = marketingConsent }
            if !isHidden("whatsapp_consent")  { body["whatsapp_consent"]  = whatsappConsent }
        }

        if let url = photoUrl, !url.isEmpty {
            body["photo_url"] = url
        }

        let cf = customValues.jsonReady()
        if !cf.isEmpty {
            body["custom_fields"] = cf
        }

        return body
    }
}
