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
    /// Spark & Ray: the account's required "Outcome". Blank blocks Save with an inline error.
    @State private var outcome = ""
    @State private var showOutcomeError = false
    /// Built-in field overrides (hide / relabel / require) for account columns.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()

    let onSubmit: ([String: Any]) async -> Void

    /// Outcome is a built-in account column, so it is gated like every other one: Spark & Ray only, held
    /// back until the overrides loaded, and hideable / relabelable by the admin.
    private var showsOutcome: Bool {
        SparkJourney.isActive
            && fieldOverrides.didLoad
            && !fieldOverrides.isHidden(entity: "account", "outcome")
    }

    private var outcomeError: String? {
        showsOutcome ? SparkAccountOutcome.validationError(outcome) : nil
    }

    @ViewBuilder
    private var outcomeSection: some View {
        if showsOutcome {
            Section {
                TextField("What is the outcome?", text: $outcome, axis: .vertical)
                    .lineLimit(2...5)
                if showOutcomeError, let err = outcomeError {
                    Text(err).font(.footnote).foregroundColor(.red)
                }
            } header: {
                Text(fieldOverrides.labelFor(entity: "account", "outcome", "Outcome") + " (required)")
            }
        }
    }

    private func saveTapped() {
        if outcomeError != nil {
            showOutcomeError = true
            return
        }
        Task {
            await onSubmit(buildBody())
            dismiss()
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if !fieldOverrides.isHidden(entity: "account", "name") {
                        TextField(fieldOverrides.labelFor(entity: "account", "name", "Company name"), text: $name)
                    }
                    // Curated industry list — mirrors the web dashboard so
                    // a contact's industry on iOS bucket-matches the same
                    // analytics groupings on the desktop reports.
                    if !fieldOverrides.isHidden(entity: "account", "industry") {
                        Picker(fieldOverrides.labelFor(entity: "account", "industry", "Industry"), selection: $industry) {
                            Text("— Select industry —").tag("")
                            ForEach(CRM_INDUSTRIES, id: \.self) { i in
                                Text(i).tag(i)
                            }
                        }
                    }
                    if !fieldOverrides.isHidden(entity: "account", "website") {
                        TextField(fieldOverrides.labelFor(entity: "account", "website", "Website"), text: $website).autocapitalization(.none).keyboardType(.URL)
                    }
                    if !fieldOverrides.isHidden(entity: "account", "phone") {
                        TextField(fieldOverrides.labelFor(entity: "account", "phone", "Phone"), text: $phone).keyboardType(.phonePad)
                    }
                }
                Section("Profile") {
                    if !fieldOverrides.isHidden(entity: "account", "annual_revenue") {
                        HStack {
                            Text(fieldOverrides.labelFor(entity: "account", "annual_revenue", "Annual revenue (₹)"))
                            Spacer()
                            TextField("0", value: $annualRevenue, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if !fieldOverrides.isHidden(entity: "account", "employees") {
                        Stepper(value: $employees, in: 0...1_000_000) {
                            HStack {
                                Text(fieldOverrides.labelFor(entity: "account", "employees", "Employees"))
                                Spacer()
                                Text("\(employees)").foregroundColor(.secondary)
                            }
                        }
                    }
                }
                outcomeSection
                Section("Description") {
                    TextField("Notes about this account…", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .task { await fieldOverrides.load() }
            .navigationTitle("New Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTapped() }.disabled(!fieldOverrides.isHidden(entity: "account", "name") && name.isEmpty)
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
        if showsOutcome { SparkAccountOutcome.apply(to: &body, outcome: outcome) }
        return body
    }
}
