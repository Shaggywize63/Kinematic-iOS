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
                Section("Personal") {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                    TextField("Email", text: $email).keyboardType(.emailAddress).autocapitalization(.none)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    Picker("Status", selection: $status) {
                        ForEach(["new","working","qualified","unqualified","converted"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                }
                if !isB2C {
                    Section("Business") {
                        TextField("Company", text: $company)
                        TextField("Job title", text: $title)
                        TextField("Industry", text: $industry)
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
                    }
                    Section("Address") {
                        TextField("Address line 1", text: $addressLine1)
                        LocationPicker(state: $state, city: $city)
                        TextField("Postal code", text: $postalCode)
                        TextField("Country", text: $country)
                    }
                    Section("Consent") {
                        Toggle("Marketing consent", isOn: $marketingConsent)
                        Toggle("WhatsApp consent", isOn: $whatsappConsent)
                    }
                }
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
            .alert("Update failed", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: Any] = [
            "first_name": firstName.isEmpty ? NSNull() : firstName,
            "last_name": lastName.isEmpty ? NSNull() : lastName,
            "email": email.isEmpty ? NSNull() : email,
            "phone": phone.isEmpty ? NSNull() : phone,
            "status": status,
            "is_b2c": isB2C,
        ]
        if !isB2C {
            body["company"] = company.isEmpty ? NSNull() : company
            body["title"] = title.isEmpty ? NSNull() : title
            if !industry.isEmpty { body["industry"] = industry }
        } else {
            body["date_of_birth"] = dateOfBirth.isEmpty ? NSNull() : dateOfBirth
            body["gender"] = gender.isEmpty ? NSNull() : gender
            body["address_line1"] = addressLine1.isEmpty ? NSNull() : addressLine1
            body["city"] = city.isEmpty ? NSNull() : city
            body["state"] = state.isEmpty ? NSNull() : state
            body["postal_code"] = postalCode.isEmpty ? NSNull() : postalCode
            body["country"] = country.isEmpty ? NSNull() : country
            body["preferred_contact_method"] = preferredContactMethod.isEmpty ? NSNull() : preferredContactMethod
            body["marketing_consent"] = marketingConsent
            body["whatsapp_consent"] = whatsappConsent
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
