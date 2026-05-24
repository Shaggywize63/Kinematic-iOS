import SwiftUI

struct LeadEditView: View {
    let lead: Lead
    let onSaved: (Lead) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String
    @State private var lastName: String
    @State private var email: String
    @State private var phone: String
    @State private var status: String
    @State private var company: String
    @State private var title: String
    @State private var industry: String
    @State private var isB2C: Bool
    @State private var dateOfBirth: String
    @State private var gender: String
    @State private var addressLine1: String
    @State private var city: String
    @State private var state: String
    @State private var postalCode: String
    @State private var country: String
    @State private var preferredContactMethod: String
    @State private var marketingConsent: Bool
    @State private var whatsappConsent: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    // Photo + custom-field config (loaded on appear)
    @State private var photoUrl: String?
    @State private var overrides: [String: FieldOverride] = [:]
    @State private var customFields: [CRMCustomField] = []
    @State private var customValues = CustomFieldValues()
    @State private var configLoaded = false

    init(lead: Lead, onSaved: @escaping (Lead) -> Void) {
        self.lead = lead
        self.onSaved = onSaved
        _firstName = State(initialValue: lead.firstName ?? "")
        _lastName = State(initialValue: lead.lastName ?? "")
        _email = State(initialValue: lead.email ?? "")
        _phone = State(initialValue: lead.phone ?? "")
        _status = State(initialValue: lead.status ?? "new")
        _company = State(initialValue: lead.company ?? "")
        _title = State(initialValue: lead.title ?? "")
        _industry = State(initialValue: "") // not on iOS Lead model
        _isB2C = State(initialValue: lead.isB2c ?? false)
        _dateOfBirth = State(initialValue: lead.dateOfBirth ?? "")
        _gender = State(initialValue: lead.gender ?? "")
        _addressLine1 = State(initialValue: lead.addressLine1 ?? "")
        _city = State(initialValue: lead.city ?? "")
        _state = State(initialValue: lead.state ?? "")
        _postalCode = State(initialValue: lead.postalCode ?? "")
        _country = State(initialValue: lead.country ?? "India")
        _preferredContactMethod = State(initialValue: lead.preferredContactMethod ?? "")
        _marketingConsent = State(initialValue: lead.marketingConsent ?? false)
        _whatsappConsent = State(initialValue: lead.whatsappConsent ?? false)
        _photoUrl = State(initialValue: lead.photoUrl)

        // Pre-seed custom field values from the existing lead so users see
        // what they've previously entered instead of an empty form.
        var preset = CustomFieldValues()
        if let existing = lead.customFields {
            for (k, v) in existing {
                if let s = v.value { preset[k] = s }
            }
        }
        _customValues = State(initialValue: preset)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $isB2C) {
                        Text("B2B (Business)").tag(false)
                        Text("B2C (Consumer)").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                LeadPhotoSection(photoUrl: $photoUrl)

                personalSection
                if !isB2C {
                    businessSection
                } else {
                    customerSection
                    addressSection
                    consentSection
                }

                CustomFieldsSection(fields: customFields, values: $customValues)
            }
            .navigationTitle("Edit Lead")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(saving)
                }
            }
            .alert("Update failed",
                   isPresented: .init(get: { errorMessage != nil },
                                      set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .task { await loadConfig() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var personalSection: some View {
        let fn = !isHidden("first_name")
        let ln = !isHidden("last_name")
        let em = !isHidden("email")
        let ph = !isHidden("phone")
        let st = !isHidden("status")
        if fn || ln || em || ph || st {
            Section("Personal") {
                if fn { TextField(label("first_name", default: "First name"), text: $firstName) }
                if ln { TextField(label("last_name",  default: "Last name"),  text: $lastName) }
                if em {
                    TextField(label("email", default: "Email"), text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                if ph {
                    TextField(label("phone", default: "Phone"), text: $phone)
                        .keyboardType(.phonePad)
                }
                if st {
                    Picker(label("status", default: "Status"), selection: $status) {
                        ForEach(["new","working","qualified","unqualified","converted"], id: \.self) {
                            Text($0.capitalized).tag($0)
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
            Section("Business") {
                if cShown { TextField(label("company", default: "Company"), text: $company) }
                if tShown { TextField(label("title",   default: "Job title"), text: $title) }
                if iShown { TextField(label("industry", default: "Industry"), text: $industry) }
            }
        }
    }

    @ViewBuilder
    private var customerSection: some View {
        let dobShown = !isHidden("date_of_birth")
        let gShown   = !isHidden("gender")
        let pShown   = !isHidden("preferred_contact_method")
        if dobShown || gShown || pShown {
            Section("Customer") {
                if dobShown {
                    TextField(label("date_of_birth", default: "Date of birth (YYYY-MM-DD)"), text: $dateOfBirth)
                }
                if gShown {
                    Picker(label("gender", default: "Gender"), selection: $gender) {
                        ForEach(["","male","female","other","prefer_not_to_say"], id: \.self) {
                            Text($0.isEmpty ? "—" : $0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                        }
                    }
                }
                if pShown {
                    Picker(label("preferred_contact_method", default: "Preferred channel"),
                           selection: $preferredContactMethod) {
                        ForEach(["","email","phone","whatsapp","sms"], id: \.self) {
                            Text($0.isEmpty ? "—" : $0.capitalized).tag($0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var addressSection: some View {
        let a1 = !isHidden("address_line1")
        let cityShown = !isHidden("city")
        let stateShown = !isHidden("state")
        let pc = !isHidden("postal_code")
        let cn = !isHidden("country")
        if a1 || cityShown || stateShown || pc || cn {
            Section("Address") {
                if a1 { TextField(label("address_line1", default: "Address line 1"), text: $addressLine1) }
                if cityShown && stateShown {
                    LocationPicker(state: $state, city: $city)
                } else {
                    if cityShown { TextField(label("city", default: "City"), text: $city) }
                    if stateShown { TextField(label("state", default: "State"), text: $state) }
                }
                if pc { TextField(label("postal_code", default: "Postal code"), text: $postalCode) }
                if cn { TextField(label("country", default: "Country"), text: $country) }
            }
        }
    }

    @ViewBuilder
    private var consentSection: some View {
        let mc = !isHidden("marketing_consent")
        let wc = !isHidden("whatsapp_consent")
        if mc || wc {
            Section("Consent") {
                if mc { Toggle(label("marketing_consent", default: "Marketing consent"), isOn: $marketingConsent) }
                if wc { Toggle(label("whatsapp_consent",  default: "WhatsApp consent"),  isOn: $whatsappConsent) }
            }
        }
    }

    // MARK: - Config helpers

    private func override(_ key: String) -> FieldOverride? { overrides["lead.\(key)"] }
    private func isHidden(_ key: String) -> Bool { override(key)?.hidden == true }
    private func label(_ key: String, default defaultLabel: String) -> String {
        override(key)?.label ?? defaultLabel
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

    // MARK: - Submit

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: Any] = ["is_b2c": isB2C]
        if !isHidden("first_name") { body["first_name"] = firstName.isEmpty ? NSNull() : firstName }
        if !isHidden("last_name")  { body["last_name"]  = lastName.isEmpty  ? NSNull() : lastName }
        if !isHidden("email")      { body["email"]      = email.isEmpty     ? NSNull() : email }
        if !isHidden("phone")      { body["phone"]      = phone.isEmpty     ? NSNull() : phone }
        if !isHidden("status")     { body["status"]     = status }

        if !isB2C {
            if !isHidden("company") { body["company"] = company.isEmpty ? NSNull() : company }
            if !isHidden("title")   { body["title"]   = title.isEmpty   ? NSNull() : title }
            if !isHidden("industry") && !industry.isEmpty { body["industry"] = industry }
        } else {
            if !isHidden("date_of_birth") { body["date_of_birth"] = dateOfBirth.isEmpty ? NSNull() : dateOfBirth }
            if !isHidden("gender")        { body["gender"] = gender.isEmpty ? NSNull() : gender }
            if !isHidden("address_line1") { body["address_line1"] = addressLine1.isEmpty ? NSNull() : addressLine1 }
            if !isHidden("city")          { body["city"] = city.isEmpty ? NSNull() : city }
            if !isHidden("state")         { body["state"] = state.isEmpty ? NSNull() : state }
            if !isHidden("postal_code")   { body["postal_code"] = postalCode.isEmpty ? NSNull() : postalCode }
            if !isHidden("country")       { body["country"] = country.isEmpty ? NSNull() : country }
            if !isHidden("preferred_contact_method") {
                body["preferred_contact_method"] = preferredContactMethod.isEmpty ? NSNull() : preferredContactMethod
            }
            if !isHidden("marketing_consent") { body["marketing_consent"] = marketingConsent }
            if !isHidden("whatsapp_consent")  { body["whatsapp_consent"]  = whatsappConsent }
        }

        // Photo (NSNull to explicitly clear when removed).
        if let url = photoUrl, !url.isEmpty {
            body["photo_url"] = url
        } else {
            body["photo_url"] = NSNull()
        }

        let cf = customValues.jsonReady()
        if !cf.isEmpty { body["custom_fields"] = cf }

        do {
            let updated = try await CRMService.shared.patchLead(id: lead.id, body: body)
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
