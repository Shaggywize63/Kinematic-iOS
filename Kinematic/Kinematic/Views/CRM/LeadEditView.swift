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
    @StateObject private var productLines = ProductLinesModel()
    /// Admin-defined per-tenant overrides — visibility / label / required
    /// for built-in lead fields. Mirrors LeadCreateView so editing honours
    /// the same admin policy as creation.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()
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
                // Each row is guarded by fieldOverrides.isHidden so the
                // tenant's admin can hide a built-in field for the rep's
                // org-role — same policy the create form honours.
                Section("Contact") {
                    if !fieldOverrides.isHidden("first_name", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor("first_name", defaultLabel: "First name", isB2C: isB2C), text: $firstName)
                            .textContentType(.givenName)
                    }
                    if !fieldOverrides.isHidden("last_name", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor("last_name", defaultLabel: "Last name", isB2C: isB2C), text: $lastName)
                            .textContentType(.familyName)
                    }
                    if !ClientFeatures.isTataTiscon && !fieldOverrides.isHidden("email", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor("email", defaultLabel: "Email", isB2C: isB2C), text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                    }
                    if !fieldOverrides.isHidden("phone", isB2C: isB2C) {
                        // Strip non-digits + clamp to 10 at input time so the rep
                        // can't type/paste spaces. Mirrors LeadCreateView.
                        TextField(fieldOverrides.labelFor("phone", defaultLabel: "Phone", isB2C: isB2C), text: Binding(
                            get: { phone },
                            set: { raw in phone = String(raw.filter { $0.isNumber }.prefix(10)) }
                        ))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    }
                    if isB2C && !fieldOverrides.isHidden("preferred_contact_method", isB2C: isB2C) {
                        Picker(fieldOverrides.labelFor("preferred_contact_method", defaultLabel: "Preferred channel", isB2C: isB2C), selection: $preferredContactMethod) {
                            ForEach(["", "email", "phone", "whatsapp", "sms"], id: \.self) {
                                Text($0.isEmpty ? "—" : $0.capitalized).tag($0)
                            }
                        }
                    }
                }

                // ── Business (B2B only) ────────────────────────────
                if !isB2C {
                    Section("Business Details") {
                        if !fieldOverrides.isHidden("company", isB2C: false) {
                            TextField(fieldOverrides.labelFor("company", defaultLabel: "Company", isB2C: false), text: $company)
                                .textContentType(.organizationName)
                        }
                        if !fieldOverrides.isHidden("title", isB2C: false) {
                            TextField(fieldOverrides.labelFor("title", defaultLabel: "Job title", isB2C: false), text: $title)
                                .textContentType(.jobTitle)
                        }
                        if !fieldOverrides.isHidden("industry", isB2C: false) {
                            TextField(fieldOverrides.labelFor("industry", defaultLabel: "Industry", isB2C: false), text: $industry)
                        }
                    }
                }

                // ── Personal (B2C only) ────────────────────────────
                if isB2C {
                    Section("Personal") {
                        if !fieldOverrides.isHidden("date_of_birth", isB2C: true) {
                            TextField(fieldOverrides.labelFor("date_of_birth", defaultLabel: "Date of birth (YYYY-MM-DD)", isB2C: true), text: $dateOfBirth)
                        }
                        if !fieldOverrides.isHidden("gender", isB2C: true) {
                            Picker(fieldOverrides.labelFor("gender", defaultLabel: "Gender", isB2C: true), selection: $gender) {
                                ForEach(["", "male", "female", "other", "prefer_not_to_say"], id: \.self) {
                                    Text($0.isEmpty ? "—" : $0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                                }
                            }
                        }
                    }
                }

                // ── Address — shown for both B2B and B2C so reps can
                //    geo-target every lead.
                Section("Address") {
                    if !fieldOverrides.isHidden("address_line1", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor("address_line1", defaultLabel: "Line 1", isB2C: isB2C), text: $addressLine1)
                    }
                    if !fieldOverrides.isHidden("address_line2", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor("address_line2", defaultLabel: "Line 2", isB2C: isB2C), text: $addressLine2)
                    }
                    // State + City share a LocationPicker so hide them together
                    // if either is hidden — partial hide would leave a half-form.
                    if !fieldOverrides.isHidden("city", isB2C: isB2C) && !fieldOverrides.isHidden("state", isB2C: isB2C) {
                        LocationPicker(state: $state, city: $city)
                    }
                    if !fieldOverrides.isHidden("postal_code", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor("postal_code", defaultLabel: "Postal code", isB2C: isB2C), text: $postalCode)
                            .keyboardType(.numberPad)
                    }
                    if !fieldOverrides.isHidden("country", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor("country", defaultLabel: "Country", isB2C: isB2C), text: $country)
                    }
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
                    // Explicitly gate Consumer Champion too in case the
                    // backend's data_scope returns looser than 'own'.
                    if ClientFeatures.canReassignLeads && !ClientFeatures.isConsumerChampion {
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
                    let showMarketing = !fieldOverrides.isHidden("marketing_consent", isB2C: true)
                    let showWhatsapp = !fieldOverrides.isHidden("whatsapp_consent", isB2C: true)
                    if showMarketing || showWhatsapp {
                        Section("Consent & Preferences") {
                            if showMarketing {
                                Toggle(fieldOverrides.labelFor("marketing_consent", defaultLabel: "Marketing consent", isB2C: true), isOn: $marketingConsent)
                            }
                            if showWhatsapp {
                                Toggle(fieldOverrides.labelFor("whatsapp_consent", defaultLabel: "WhatsApp consent", isB2C: true), isOn: $whatsappConsent)
                            }
                        }
                    }
                }

                // ── Custom Fields — admin-defined per-tenant fields ──
                //     (e.g. Tata Tiscon's "First Visit Date", "Brand").
                //     Hidden when no defs apply to the rep's role.
                CustomFieldsSection(model: customFields)

                // ── Products of Interest — multi-row picker that drives
                //     custom_fields.product_lines plus the four legacy
                //     mirror keys (product_interested / quantity /
                //     measuring_unit / estimated_amount). Tata-only —
                //     no other tenant uses the inline basket capture.
                if isTata {
                    ProductLinesSection(model: productLines)
                }

                // ── Tata Tiscon: site-visit affordance on edit too ──
                if isTata {
                    Section {
                        Toggle("Also log a Site Visit", isOn: $logAsSiteVisit)
                    } footer: {
                        Text("Creates a completed Site Visit on this lead's timeline. When the First Visit Date custom field is filled in, the activity is recorded as a First Site Visit instead.")
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
        // Fire all five lookups in parallel — they're independent and
        // the form is usable without any of them while they load.
        async let ownersTask  = CRMService.shared.listAssignableUsers()
        async let sourcesTask = CRMService.shared.listLeadSources()
        async let cfTask: Void = customFields.load(entity: "lead")
        async let plTask: Void = productLines.load()
        async let foTask: Void = fieldOverrides.load()
        owners  = await ownersTask
        sources = await sourcesTask
        _ = await cfTask
        _ = await plTask
        _ = await foTask
        // Hydrate the form with the lead's existing custom-field values
        // after the defs land, so each value lands in the right type
        // bucket (text / bool / multi).
        customFields.hydrate(from: lead.customFields)
        productLines.hydrate(from: lead.customFields)
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
            // Admin-defined custom fields plus the product-lines block.
            // Merge productLines.jsonValues last so its product_lines /
            // mirror keys overwrite any stale values left in the generic
            // bag — same shape the create form sends.
            "custom_fields": ({
                var merged = customFields.jsonValues
                for (k, v) in productLines.jsonValues { merged[k] = v }
                return merged
            })(),
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
        } catch let urlError as URLError where [
            .notConnectedToInternet, .timedOut, .cannotConnectToHost,
            .networkConnectionLost, .dataNotAllowed,
        ].contains(urlError.code) {
            // Offline / weak signal — queue the PATCH so the rep's
            // edits don't vanish between the form and the wire. The
            // header chip surfaces the pending count.
            let label = "Lead edit · " + (firstName.isEmpty ? lastName : firstName)
            OfflineMutationQueue.shared.enqueue(
                method: "PATCH",
                path: "/api/v1/crm/leads/\(lead.id)",
                body: body,
                displayLabel: label.isEmpty ? "Lead edit" : label,
                clientId: Session.currentUser?.clientId,
                lastError: urlError.localizedDescription,
            )
            // Dismiss as if saved — the optimistic onSaved(lead) keeps
            // the parent screen in sync with the typed values until
            // the canonical server row arrives on next refresh.
            onSaved(lead)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
