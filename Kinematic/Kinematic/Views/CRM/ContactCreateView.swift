import SwiftUI

struct ContactCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName  = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var accountId = ""
    @State private var isB2C = false

    // B2B
    @State private var title = ""

    // B2C
    @State private var dateOfBirth = Date()
    @State private var hasDOB = false
    @State private var gender = "prefer_not_to_say"
    @State private var preferredChannel = "email"
    @State private var referralSource = ""
    @State private var addressLine1 = ""
    @State private var addressLine2 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var postalCode = ""
    @State private var country = "India"
    @State private var marketingConsent = false
    @State private var whatsappConsent = false
    /// Built-in field overrides (hide / relabel / require) for contact
    /// columns, scoped by the contact's B2B/B2C mode like the lead form.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()

    let onSubmit: ([String: Any]) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Contact type", selection: $isB2C) {
                        Text("B2B (Business)").tag(false)
                        Text("B2C (Consumer)").tag(true)
                    }.pickerStyle(.segmented)
                }

                Section("Identity") {
                    if !fieldOverrides.isHidden(entity: "contact", "first_name", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor(entity: "contact", "first_name", "First name", isB2C: isB2C), text: $firstName)
                    }
                    if !fieldOverrides.isHidden(entity: "contact", "last_name", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor(entity: "contact", "last_name", "Last name", isB2C: isB2C), text: $lastName)
                    }
                }
                Section("Contact") {
                    if !fieldOverrides.isHidden(entity: "contact", "email", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor(entity: "contact", "email", "Email", isB2C: isB2C), text: $email).keyboardType(.emailAddress).autocapitalization(.none)
                    }
                    if !fieldOverrides.isHidden(entity: "contact", "phone", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor(entity: "contact", "phone", "Phone", isB2C: isB2C), text: $phone).keyboardType(.phonePad)
                    }
                }
                if !fieldOverrides.isHidden(entity: "contact", "account_id", isB2C: isB2C) {
                    Section("Account") {
                        TextField(fieldOverrides.labelFor(entity: "contact", "account_id", "Account ID (optional)", isB2C: isB2C), text: $accountId)
                    }
                }

                if !isB2C {
                    if !fieldOverrides.isHidden(entity: "contact", "title", isB2C: isB2C) {
                        Section("Business") {
                            TextField(fieldOverrides.labelFor(entity: "contact", "title", "Job title", isB2C: isB2C), text: $title)
                        }
                    }
                } else {
                    Section("Customer Details") {
                        Toggle("Set date of birth", isOn: $hasDOB)
                        if hasDOB {
                            DatePicker("Date of birth", selection: $dateOfBirth, displayedComponents: .date)
                        }
                        Picker("Gender", selection: $gender) {
                            Text("Male").tag("male"); Text("Female").tag("female"); Text("Other").tag("other"); Text("Prefer not to say").tag("prefer_not_to_say")
                        }
                        Picker("Preferred channel", selection: $preferredChannel) {
                            ForEach(["email","phone","whatsapp","sms"], id: \.self) { Text($0.capitalized).tag($0) }
                        }
                        TextField("Referral source", text: $referralSource)
                    }
                    Section("Address") {
                        TextField("Address line 1", text: $addressLine1)
                        TextField("Address line 2", text: $addressLine2)
                        if !fieldOverrides.isHidden(entity: "contact", "city", isB2C: isB2C) {
                            TextField(fieldOverrides.labelFor(entity: "contact", "city", "City", isB2C: isB2C), text: $city)
                        }
                        if !fieldOverrides.isHidden(entity: "contact", "state", isB2C: isB2C) {
                            TextField(fieldOverrides.labelFor(entity: "contact", "state", "State", isB2C: isB2C), text: $state)
                        }
                        TextField("Postal code", text: $postalCode).keyboardType(.numberPad)
                        if !fieldOverrides.isHidden(entity: "contact", "country", isB2C: isB2C) {
                            TextField(fieldOverrides.labelFor(entity: "contact", "country", "Country", isB2C: isB2C), text: $country)
                        }
                    }
                    if !fieldOverrides.isHidden(entity: "contact", "marketing_consent", isB2C: isB2C) || !fieldOverrides.isHidden(entity: "contact", "whatsapp_consent", isB2C: isB2C) {
                        Section("Consent") {
                            if !fieldOverrides.isHidden(entity: "contact", "marketing_consent", isB2C: isB2C) {
                                Toggle(fieldOverrides.labelFor(entity: "contact", "marketing_consent", "Marketing emails", isB2C: isB2C), isOn: $marketingConsent)
                            }
                            if !fieldOverrides.isHidden(entity: "contact", "whatsapp_consent", isB2C: isB2C) {
                                Toggle(fieldOverrides.labelFor(entity: "contact", "whatsapp_consent", "WhatsApp messages", isB2C: isB2C), isOn: $whatsappConsent)
                            }
                        }
                    }
                }
            }
            .task { await fieldOverrides.load() }
            .navigationTitle("New Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSubmit(buildBody())
                            dismiss()
                        }
                    }
                    .disabled(firstName.isEmpty && lastName.isEmpty && email.isEmpty)
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
            "is_b2c":     isB2C,
        ]
        if !accountId.isEmpty { body["account_id"] = accountId }
        if !isB2C {
            body["title"] = title
        } else {
            if hasDOB {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                body["date_of_birth"] = f.string(from: dateOfBirth)
            }
            body["gender"] = gender
            body["preferred_contact_method"] = preferredChannel
            body["referral_source"] = referralSource
            body["address_line1"] = addressLine1
            body["address_line2"] = addressLine2
            body["city"] = city
            body["state"] = state
            body["postal_code"] = postalCode
            body["country"] = country
            body["marketing_consent"] = marketingConsent
            body["whatsapp_consent"]  = whatsappConsent
        }
        return body
    }
}
