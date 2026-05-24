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

    // Photo (optional, uploaded via /api/v1/upload/photo).
    @State private var photoUrl: String?

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

                CRMPhotoSection(title: "Contact Photo (optional)", photoUrl: $photoUrl)

                Section("Identity") {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                }
                Section("Contact") {
                    TextField("Email", text: $email).keyboardType(.emailAddress).autocapitalization(.none)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                }
                Section("Account") {
                    TextField("Account ID (optional)", text: $accountId)
                }

                if !isB2C {
                    Section("Business") {
                        TextField("Job title", text: $title)
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
        if let url = photoUrl, !url.isEmpty {
            body["photo_url"] = url
        }
        return body
    }
}
