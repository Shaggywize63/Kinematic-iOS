import SwiftUI

// Categorized lead edit screen — mirrors the web LeadEditModal's section
// taxonomy (Contact / Business / Personal / Address / Lifecycle / Consent /
// Custom Fields / Notes) so the same fields exist on every platform.
// SwiftUI Form + Section is the most native categorized form on iOS; the
// section headers handle the grouping the user asked for without inventing
// custom card chrome.
//
// Deferred to a follow-up: alternate_mobiles chip list editor.
struct LeadEditView: View {
    let lead: Lead
    let onSaved: (Lead) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String
    @State private var lastName: String
    @State private var email: String
    @State private var phone: String
    @State private var status: String
    @State private var sourceId: String
    @State private var ownerId: String
    @State private var company: String
    @State private var title: String
    @State private var industry: String
    @State private var isB2C: Bool
    @State private var dateOfBirth: String
    @State private var gender: String
    @State private var addressLine1: String
    @State private var addressLine2: String
    @State private var city: String
    @State private var state: String
    @State private var postalCode: String
    @State private var country: String
    @State private var preferredContactMethod: String
    @State private var marketingConsent: Bool
    @State private var whatsappConsent: Bool
    @State private var notes: String

    @State private var owners: [AssignableUser] = []
    @State private var sources: [CRMLeadSource] = []
    /// Admin-defined custom fields scoped to the rep's org role. Loaded
    /// (and hydrated from `lead.customFields`) inside `.task`.
    @StateObject private var customFields = CustomFieldsModel()
    /// Tata Tiscon affordance — mirrors the create form. Lets the rep
    /// log a follow-up site visit while editing. Default off so saving
    /// the form doesn't accidentally spawn duplicate visits.
    @State private var logAsSiteVisit = false
    @State private var saving = false
    @State private var errorMessage: String?

    private var isTata: Bool { ClientFeatures.isTataTiscon }

    init(lead: Lead, onSaved: @escaping (Lead) -> Void) {
        self.lead = lead
        self.onSaved = onSaved
        _firstName = State(initialValue: lead.firstName ?? "")
        _lastName = State(initialValue: lead.lastName ?? "")
        _email = State(initialValue: lead.email ?? "")
        _phone = State(initialValue: lead.phone ?? "")
        _status = State(initialValue: lead.status ?? "new")
        _sourceId = State(initialValue: lead.source ?? "")
        _ownerId = State(initialValue: lead.ownerId ?? "")
        _company = State(initialValue: lead.company ?? "")
        _title = State(initialValue: lead.title ?? "")
        _industry = State(initialValue: "")
        _isB2C = State(initialValue: lead.isB2c ?? false)
        _dateOfBirth = State(initialValue: lead.dateOfBirth ?? "")
        _gender = State(initialValue: lead.gender ?? "")
        _addressLine1 = State(initialValue: lead.addressLine1 ?? "")
        _addressLine2 = State(initialValue: lead.addressLine2 ?? "")
        _city = State(initialValue: lead.city ?? "")
        _state = State(initialValue: lead.state ?? "")
        _postalCode = State(initialValue: lead.postalCode ?? "")
        _country = State(initialValue: lead.country ?? "India")
        _preferredContactMethod = State(initialValue: lead.preferredContactMethod ?? "")
        _marketingConsent = State(initialValue: lead.marketingConsent ?? false)
        _whatsappConsent = State(initialValue: lead.whatsappConsent ?? false)
        _notes = State(initialValue: lead.notes ?? "")
    }

    /// Tata Tiscon is consumer-only — never offer the B2B option. Forced
    /// `isB2C = true` on appear so existing records stay consistent.
    /// (`isTata` is declared higher up alongside the @State fields.)

    var body: some View {
        NavigationStack {
            Form {
                // ── Type toggle (hidden for Tata Tiscon) ───────────
                if !isTata {
                    Section {
                        Picker("Type", selection: $isB2C) {
                            Text("Business (B2B)").tag(false)
                            Text("Consumer (B2C)").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // ── Contact ────────────────────────────────────────
                Section("Contact") {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                    // Email hidden for Tata Tiscon — matches LeadCreateView.
                    if !ClientFeatures.isTataTiscon {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                    }
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    if isB2C {
                        Picker("Preferred channel", selection: $preferredContactMethod) {
                            ForEach(["", "email", "phone", "whatsapp", "sms"], id: \.self) {
                                Text($0.isEmpty ? "—" : $0.capitalized).tag($0)
                            }
                        }
                    }
                }

                // ── Business (B2B only) ────────────────────────────
                if !isB2C {
                    Section("Business Details") {
                        TextField("Company", text: $company)
                            .textContentType(.organizationName)
                        TextField("Job title", text: $title)
                            .textContentType(.jobTitle)
                        TextField("Industry", text: $industry)
                    }
                }

                // ── Personal (B2C only) ────────────────────────────
                if isB2C {
                    Section("Personal") {
                        TextField("Date of birth (YYYY-MM-DD)", text: $dateOfBirth)
                        Picker("Gender", selection: $gender) {
                            ForEach(["", "male", "female", "other", "prefer_not_to_say"], id: \.self) {
                                Text($0.isEmpty ? "—" : $0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                            }
                        }
                    }
                }

                // ── Address — shown for both B2B and B2C so reps can
                //    geo-target every lead.
                Section("Address") {
                    TextField("Line 1", text: $addressLine1)
                    TextField("Line 2", text: $addressLine2)
                    LocationPicker(state: $state, city: $city)
                    TextField("Postal code", text: $postalCode)
                        .keyboardType(.numberPad)
                    TextField("Country", text: $country)
                    if let lat = lead.latitude, let lng = lead.longitude {
                        HStack {
                            Text("Coordinates")
                            Spacer()
                            Text(String(format: "%.4f, %.4f", lat, lng))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Lifecycle & Assignment ─────────────────────────
                Section("Lifecycle & Assignment") {
                    Picker("Status", selection: $status) {
                        ForEach(["new", "working", "qualified", "unqualified", "converted", "lost"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                    Picker("Source", selection: $sourceId) {
                        Text("—").tag("")
                        ForEach(sources, id: \.id) { src in
                            Text(src.name).tag(src.id)
                        }
                    }
                    // Reps with data_scope='own' (e.g. Consumer Champion)
                    // would lose visibility of the lead by reassigning it.
                    if ClientFeatures.canReassignLeads {
                        Picker("Owner", selection: $ownerId) {
                            Text("Unassigned").tag("")
                            ForEach(owners, id: \.id) { u in
                                Text(u.name ?? u.email ?? "User").tag(u.id)
                            }
                        }
                    }
                }

                // ── Consent (B2C only) ─────────────────────────────
                if isB2C {
                    Section("Consent & Preferences") {
                        Toggle("Marketing consent", isOn: $marketingConsent)
                        Toggle("WhatsApp consent", isOn: $whatsappConsent)
                    }
                }

                // ── Custom Fields — admin-defined per-tenant fields ──
                //     (e.g. Tata Tiscon's "First Visit Date", "Brand").
                //     Hidden when no defs apply to the rep's role.
                CustomFieldsSection(model: customFields)

                // ── Tata Tiscon: site-visit affordance on edit too ──
                if isTata {
                    Section {
                        Toggle("Also log a Site Visit", isOn: $logAsSiteVisit)
                    } footer: {
                        Text("Creates a completed Site Visit on this lead's timeline. When the First Visit Date custom field is filled in, the activity is recorded as a First Visit instead.")
                    }
                }

                // ── Notes ──────────────────────────────────────────
                Section("Notes") {
                    TextField("Internal notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit Lead")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadPickerOptions() }
            .onAppear {
                // Tata Tiscon is consumer-only — lock the toggle even if a
                // legacy record was somehow saved with is_b2c=false.
                if isTata { isB2C = true }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(saving)
                }
            }
            .alert("Update failed", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func loadPickerOptions() async {
        // Fire all three lookups in parallel — they're independent and
        // the form is usable without any of them while they load.
        async let ownersTask  = CRMService.shared.listAssignableUsers()
        async let sourcesTask = CRMService.shared.listLeadSources()
        async let cfTask: Void = customFields.load(entity: "lead")
        owners  = await ownersTask
        sources = await sourcesTask
        _ = await cfTask
        // Hydrate the form with the lead's existing custom-field values
        // after the defs land, so each value lands in the right type
        // bucket (text / bool / multi).
        customFields.hydrate(from: lead.customFields)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: Any] = [
            "first_name": firstName.isEmpty ? NSNull() : firstName,
            "last_name":  lastName.isEmpty  ? NSNull() : lastName,
            "email":      email.isEmpty     ? NSNull() : email,
            "phone":      phone.isEmpty     ? NSNull() : phone,
            "status":     status,
            "is_b2c":     isB2C,
            "owner_id":   ownerId.isEmpty   ? NSNull() : ownerId,
            "source_id":  sourceId.isEmpty  ? NSNull() : sourceId,
            "notes":      notes.isEmpty     ? NSNull() : notes,
            "address_line1": addressLine1.isEmpty ? NSNull() : addressLine1,
            "address_line2": addressLine2.isEmpty ? NSNull() : addressLine2,
            "city":          city.isEmpty         ? NSNull() : city,
            "state":         state.isEmpty        ? NSNull() : state,
            "postal_code":   postalCode.isEmpty   ? NSNull() : postalCode,
            "country":       country.isEmpty      ? NSNull() : country,
            // Admin-defined custom fields. Empty dict is sent so the
            // backend can persist a "the rep cleared everything" state.
            "custom_fields": customFields.jsonValues,
        ]
        // Tata Tiscon: backend pops this flag and spawns a fresh
        // site_visit activity tied to the lead.
        if isTata && logAsSiteVisit {
            body["_auto_log_site_visit"] = true
        }
        if !isB2C {
            body["company"] = company.isEmpty ? NSNull() : company
            body["title"]   = title.isEmpty   ? NSNull() : title
            if !industry.isEmpty { body["industry"] = industry }
        } else {
            body["date_of_birth"] = dateOfBirth.isEmpty ? NSNull() : dateOfBirth
            body["gender"]        = gender.isEmpty ? NSNull() : gender
            body["preferred_contact_method"] = preferredContactMethod.isEmpty ? NSNull() : preferredContactMethod
            body["marketing_consent"] = marketingConsent
            body["whatsapp_consent"]  = whatsappConsent
        }
        do {
            let updated = try await CRMService.shared.patchLead(id: lead.id, body: body)
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
