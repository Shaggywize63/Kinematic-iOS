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
            }
            .navigationTitle("New Lead")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
        return body
    }
}
