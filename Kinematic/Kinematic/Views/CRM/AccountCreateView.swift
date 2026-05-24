import SwiftUI

struct AccountCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var industry = ""
    @State private var website = ""
    @State private var phone = ""
    @State private var annualRevenue: Double = 0
    @State private var employees: Int = 0
    @State private var description = ""

    // Photo (optional, uploaded via /api/v1/upload/photo).
    @State private var photoUrl: String?

    let onSubmit: ([String: Any]) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                CRMPhotoSection(title: "Account Logo / Photo (optional)", photoUrl: $photoUrl)
                Section("Account") {
                    TextField("Company name", text: $name)
                    TextField("Industry", text: $industry)
                    TextField("Website", text: $website).autocapitalization(.none).keyboardType(.URL)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                }
                Section("Profile") {
                    HStack {
                        Text("Annual revenue (₹)")
                        Spacer()
                        TextField("0", value: $annualRevenue, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Stepper(value: $employees, in: 0...1_000_000) {
                        HStack {
                            Text("Employees")
                            Spacer()
                            Text("\(employees)").foregroundColor(.secondary)
                        }
                    }
                }
                Section("Description") {
                    TextField("Notes about this account…", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSubmit(buildBody())
                            dismiss()
                        }
                    }.disabled(name.isEmpty)
                }
            }
        }
    }

    private func buildBody() -> [String: Any] {
        var body: [String: Any] = ["name": name]
        if !industry.isEmpty { body["industry"] = industry }
        if !website.isEmpty  { body["website"]  = website }
        if !phone.isEmpty    { body["phone"]    = phone }
        if annualRevenue > 0 { body["annual_revenue"] = annualRevenue }
        if employees > 0     { body["employees"] = employees }
        if !description.isEmpty { body["description"] = description }
        if let url = photoUrl, !url.isEmpty {
            body["photo_url"] = url
        }
        return body
    }
}
