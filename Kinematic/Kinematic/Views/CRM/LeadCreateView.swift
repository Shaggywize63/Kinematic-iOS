import SwiftUI
import Combine
import CoreLocation

struct LeadCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locator = OneShotLocationProvider()
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var source = "web"
    @State private var isB2C = false
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

    /// Admin-defined custom fields for leads, scoped to the user's org role.
    @StateObject private var customFields = CustomFieldsModel()

    let onSubmit: ([String: Any]) async -> Void

    // Tata Tiscon requires the submission location to be captured automatically
    // and is non-editable + mandatory (parity with the web lead form). Other
    // clients keep the optional "Use current location" + manual entry flow.
    private var isTata: Bool { ClientFeatures.isTataTiscon }
    private var hasValidCoords: Bool {
        Double(latitude.trimmingCharacters(in: .whitespaces)) != nil &&
        Double(longitude.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
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

                // Tata Tiscon is consumer-only — never offer the B2B option.
                // isB2C is forced true on appear (below).
                if !isTata {
                    Section {
                        Picker("Lead type", selection: $isB2C) {
                            Text("B2B (Business)").tag(false)
                            Text("B2C (Consumer)").tag(true)
                        }.pickerStyle(.segmented)
                    }
                }

                Section("Identity") {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                }
                Section("Contact") {
                    TextField("Email", text: $email).keyboardType(.emailAddress).autocapitalization(.none)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    Picker("Source", selection: $source) {
                        ForEach(["web", "referral", "event", "cold_call", "social", "whatsapp", "other"], id: \.self) {
                            Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                        }
                    }
                }
                if !isB2C {
                    Section("Business Details") {
                        TextField("Company", text: $company)
                        TextField("Job Title", text: $title)
                        TextField("Industry", text: $industry)
                    }
                } else {
                    Section("Customer Details") {
                        Toggle("Set date of birth", isOn: $hasDOB)
                        if hasDOB {
                            DatePicker("Date of birth", selection: $dateOfBirth, displayedComponents: .date)
                        }
                        Picker("Gender", selection: $gender) {
                            Text("Male").tag("male")
                            Text("Female").tag("female")
                            Text("Other").tag("other")
                            Text("Prefer not to say").tag("prefer_not_to_say")
                        }
                        Picker("Preferred channel", selection: $preferredChannel) {
                            ForEach(["email", "phone", "whatsapp", "sms"], id: \.self) { Text($0.capitalized).tag($0) }
                        }
                    }
                    Section("Address") {
                        TextField("Address line 1", text: $addressLine1)
                        TextField("Address line 2", text: $addressLine2)
                        TextField("City", text: $city)
                        TextField("State", text: $state)
                        TextField("Postal code", text: $postalCode).keyboardType(.numberPad)
                        TextField("Country", text: $country)
                    }
                    Section("Consent") {
                        Toggle("Marketing emails", isOn: $marketingConsent)
                        Toggle("WhatsApp messages", isOn: $whatsappConsent)
                    }
                }

                // Admin-defined custom fields for this user's hierarchy role.
                CustomFieldsSection(model: customFields)

                // Geo-location is captured automatically — no button, no manual
                // entry. We start a one-shot GPS fix when the form opens so the
                // coordinates are ready by the time the rep taps Save.
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
                }
            }
            .navigationTitle("New Lead")
            .task { target = await CRMService.shared.myTarget() }
            .task { await customFields.load(entity: "lead") }
            .onAppear {
                // Tata Tiscon only ever creates B2C (consumer) leads.
                if isTata { isB2C = true }
                // Auto-capture the submission location as soon as the form
                // opens so it's attached by the time the rep taps Save.
                if !hasValidCoords && !locator.isLocating {
                    locator.requestLocation()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Fetch the location on Save if we still don't have a
                        // fix (e.g. permission was just granted) — best effort.
                        if !hasValidCoords { locator.requestLocation() }
                        Task {
                            await onSubmit(buildBody())
                            dismiss()
                        }
                    }
                    .disabled(firstName.isEmpty && email.isEmpty)
                }
            }
        }
    }

    private func buildBody() -> [String: Any] {
        var body: [String: Any] = [
            "first_name": firstName,
            "last_name":  lastName,
            "email":      email,
            "phone":      phone,
            "source":     source,
            "status":     "new",
            "is_b2c":     isB2C,
        ]
        if !isB2C {
            body["company"]  = company
            body["title"]    = title
            body["industry"] = industry
        } else {
            if hasDOB {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                body["date_of_birth"] = f.string(from: dateOfBirth)
            }
            body["gender"] = gender
            body["preferred_contact_method"] = preferredChannel
            body["address_line1"] = addressLine1
            body["address_line2"] = addressLine2
            body["city"]          = city
            body["state"]         = state
            body["postal_code"]   = postalCode
            body["country"]       = country
            body["marketing_consent"] = marketingConsent
            body["whatsapp_consent"]  = whatsappConsent
        }
        // Geo coordinates (both B2B + B2C). Only sent when they parse as
        // valid numbers, so a half-typed value never reaches the API.
        if let lat = Double(latitude.trimmingCharacters(in: .whitespaces)) { body["latitude"] = lat }
        if let lon = Double(longitude.trimmingCharacters(in: .whitespaces)) { body["longitude"] = lon }
        // Admin-defined custom fields (scoped to the user's role).
        let cf = customFields.jsonValues
        if !cf.isEmpty { body["custom_fields"] = cf }
        return body
    }
}
