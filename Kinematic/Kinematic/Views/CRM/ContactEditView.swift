import SwiftUI

struct ContactEditView: View {
    let contact: Contact
    let onSaved: (Contact) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String
    @State private var lastName: String
    @State private var email: String
    @State private var phone: String
    @State private var mobile: String
    @State private var title: String
    @State private var department: String
    @State private var isB2C: Bool
    @State private var dateOfBirth: String
    @State private var gender: String
    @State private var addressLine1: String
    @State private var city: String
    @State private var state: String
    @State private var postalCode: String
    @State private var country: String
    @State private var preferredContactMethod: String
    @State private var loyaltyTier: String
    @State private var referralSource: String
    @State private var marketingConsent: Bool
    @State private var whatsappConsent: Bool
    @State private var saving = false
    @State private var errorMessage: String?
    /// Built-in field overrides (hide / relabel / require) for contact
    /// columns, scoped by the contact's B2B/B2C mode.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()

    init(contact: Contact, onSaved: @escaping (Contact) -> Void) {
        self.contact = contact
        self.onSaved = onSaved
        _firstName = State(initialValue: contact.firstName ?? "")
        _lastName = State(initialValue: contact.lastName ?? "")
        _email = State(initialValue: contact.email ?? "")
        _phone = State(initialValue: contact.phone ?? "")
        _mobile = State(initialValue: contact.mobile ?? "")
        _title = State(initialValue: contact.title ?? "")
        _department = State(initialValue: contact.department ?? "")
        _isB2C = State(initialValue: contact.isB2c ?? false)
        _dateOfBirth = State(initialValue: contact.dateOfBirth ?? "")
        _gender = State(initialValue: contact.gender ?? "")
        _addressLine1 = State(initialValue: contact.addressLine1 ?? "")
        _city = State(initialValue: contact.city ?? "")
        _state = State(initialValue: contact.state ?? "")
        _postalCode = State(initialValue: contact.postalCode ?? "")
        _country = State(initialValue: contact.country ?? "India")
        _preferredContactMethod = State(initialValue: contact.preferredContactMethod ?? "")
        _loyaltyTier = State(initialValue: contact.loyaltyTier ?? "")
        _referralSource = State(initialValue: contact.referralSource ?? "")
        _marketingConsent = State(initialValue: contact.marketingConsent ?? false)
        _whatsappConsent = State(initialValue: contact.whatsappConsent ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $isB2C) {
                        Text("B2B Contact").tag(false)
                        Text("B2C Customer").tag(true)
                    }.pickerStyle(.segmented)
                }
                Section("Personal") {
                    if !fieldOverrides.isHidden(entity: "contact", "first_name", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor(entity: "contact", "first_name", "First name", isB2C: isB2C), text: $firstName)
                    }
                    if !fieldOverrides.isHidden(entity: "contact", "last_name", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor(entity: "contact", "last_name", "Last name", isB2C: isB2C), text: $lastName)
                    }
                    if !fieldOverrides.isHidden(entity: "contact", "email", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor(entity: "contact", "email", "Email", isB2C: isB2C), text: $email).keyboardType(.emailAddress).autocapitalization(.none)
                    }
                    if !fieldOverrides.isHidden(entity: "contact", "phone", isB2C: isB2C) {
                        TextField(fieldOverrides.labelFor(entity: "contact", "phone", "Phone", isB2C: isB2C), text: $phone).keyboardType(.phonePad)
                    }
                    TextField("Mobile", text: $mobile).keyboardType(.phonePad)
                }
                if !isB2C {
                    if !fieldOverrides.isHidden(entity: "contact", "title", isB2C: isB2C) || !fieldOverrides.isHidden(entity: "contact", "department", isB2C: isB2C) {
                        Section("Work") {
                            if !fieldOverrides.isHidden(entity: "contact", "title", isB2C: isB2C) {
                                TextField(fieldOverrides.labelFor(entity: "contact", "title", "Job title", isB2C: isB2C), text: $title)
                            }
                            if !fieldOverrides.isHidden(entity: "contact", "department", isB2C: isB2C) {
                                TextField(fieldOverrides.labelFor(entity: "contact", "department", "Department", isB2C: isB2C), text: $department)
                            }
                        }
                    }
                } else {
                    Section("Customer") {
                        TextField("Date of birth (YYYY-MM-DD)", text: $dateOfBirth)
                        Picker("Gender", selection: $gender) {
                            ForEach(["","male","female","other","prefer_not_to_say"], id: \.self) {
                                Text($0.isEmpty ? "—" : $0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                            }
                        }
                        Picker("Preferred channel", selection: $preferredContactMethod) {
                            ForEach(["","email","phone","whatsapp","sms"], id: \.self) {
                                Text($0.isEmpty ? "—" : $0.capitalized).tag($0)
                            }
                        }
                        Picker("Loyalty tier", selection: $loyaltyTier) {
                            ForEach(["","bronze","silver","gold","platinum","vip"], id: \.self) {
                                Text($0.isEmpty ? "—" : $0.capitalized).tag($0)
                            }
                        }
                        TextField("Referral source", text: $referralSource)
                    }
                    Section("Address") {
                        TextField("Address line 1", text: $addressLine1)
                        if !fieldOverrides.isHidden(entity: "contact", "city", isB2C: isB2C) {
                            LocationPicker(state: $state, city: $city)
                        }
                        TextField("Postal code", text: $postalCode)
                        if !fieldOverrides.isHidden(entity: "contact", "country", isB2C: isB2C) {
                            TextField(fieldOverrides.labelFor(entity: "contact", "country", "Country", isB2C: isB2C), text: $country)
                        }
                    }
                    if !fieldOverrides.isHidden(entity: "contact", "marketing_consent", isB2C: isB2C) || !fieldOverrides.isHidden(entity: "contact", "whatsapp_consent", isB2C: isB2C) {
                        Section("Consent") {
                            if !fieldOverrides.isHidden(entity: "contact", "marketing_consent", isB2C: isB2C) {
                                Toggle(fieldOverrides.labelFor(entity: "contact", "marketing_consent", "Marketing consent", isB2C: isB2C), isOn: $marketingConsent)
                            }
                            if !fieldOverrides.isHidden(entity: "contact", "whatsapp_consent", isB2C: isB2C) {
                                Toggle(fieldOverrides.labelFor(entity: "contact", "whatsapp_consent", "WhatsApp consent", isB2C: isB2C), isOn: $whatsappConsent)
                            }
                        }
                    }
                }
            }
            .task { await fieldOverrides.load() }
            .navigationTitle("Edit Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if saving { ProgressView() } else { Text("Save") } }
                        .disabled(saving)
                }
            }
            .alert("Update failed", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        var body: [String: Any] = [
            "first_name": firstName.isEmpty ? NSNull() : firstName,
            "last_name": lastName.isEmpty ? NSNull() : lastName,
            "email": email.isEmpty ? NSNull() : email,
            "phone": phone.isEmpty ? NSNull() : phone,
            "mobile": mobile.isEmpty ? NSNull() : mobile,
            "is_b2c": isB2C,
        ]
        if !isB2C {
            body["title"] = title.isEmpty ? NSNull() : title
            body["department"] = department.isEmpty ? NSNull() : department
        } else {
            body["date_of_birth"] = dateOfBirth.isEmpty ? NSNull() : dateOfBirth
            body["gender"] = gender.isEmpty ? NSNull() : gender
            body["address_line1"] = addressLine1.isEmpty ? NSNull() : addressLine1
            body["city"] = city.isEmpty ? NSNull() : city
            body["state"] = state.isEmpty ? NSNull() : state
            body["postal_code"] = postalCode.isEmpty ? NSNull() : postalCode
            body["country"] = country.isEmpty ? NSNull() : country
            body["preferred_contact_method"] = preferredContactMethod.isEmpty ? NSNull() : preferredContactMethod
            body["loyalty_tier"] = loyaltyTier.isEmpty ? NSNull() : loyaltyTier
            body["referral_source"] = referralSource.isEmpty ? NSNull() : referralSource
            body["marketing_consent"] = marketingConsent
            body["whatsapp_consent"] = whatsappConsent
        }
        do {
            let updated = try await CRMService.shared.patchContact(id: contact.id, body: body)
            onSaved(updated)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
