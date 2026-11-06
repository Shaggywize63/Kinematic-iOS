import SwiftUI

// Spark & Ray activity row extras:
//   - SparkActivityCompanyOutcome     "Company: <name>" (a link to the account when there is one) and the Outcome
//   - AccountDetailLoader             opens an account's detail from just its id
//   - SparkAwareCompletionButton      "Mark complete" that asks for the Outcome first when it is missing
//   - SparkOutcomePromptSheet         the Outcome prompt itself
//
// Every host shows these ONLY for the Spark & Ray client (`SparkJourney.isActive`); the pure logic behind them
// lives in `Models/CRM/SparkActivityRound3.swift`.

// MARK: - Company + Outcome lines

/// The Company line and the Outcome of an activity row / detail. Renders nothing outside Spark & Ray or when the
/// activity has neither.
struct SparkActivityCompanyOutcome: View {
    let activity: Activity

    private var company: ActivityCompany.Display {
        ActivityCompany.display(for: activity, spark: SparkJourney.isActive)
    }

    private var outcomeText: String? {
        guard SparkJourney.isActive else { return nil }
        let t = (activity.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var hasContent: Bool {
        company != .hidden || outcomeText != nil
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 6) {
                companyLine
                if let outcome = outcomeText {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "target")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Outcome: \(outcome)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var companyLine: some View {
        switch company {
        case .link(let id, let name):
            NavigationLink(destination: AccountDetailLoader(accountId: id, name: name)) {
                companyLabel(name, isLink: true)
            }
            .buttonStyle(.plain)
        case .text(let name):
            companyLabel(name, isLink: false)
        case .hidden:
            EmptyView()
        }
    }

    private func companyLabel(_ name: String, isLink: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isLink ? Brand.red : .secondary)
            Text("Company: \(name)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isLink ? Brand.red : .secondary)
                .lineLimit(1)
            if isLink {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Brand.red)
            }
        }
    }
}

// MARK: - Account detail by id

/// Opens `AccountDetailView` for an account known only by id (a company link on an activity / contact row):
/// fetches the account, with a retry when that fails.
struct AccountDetailLoader: View {
    let accountId: String
    let name: String

    @State private var account: CRMAccount? = nil
    @State private var failed = false

    init(accountId: String, name: String) {
        self.accountId = accountId
        self.name = name
    }

    var body: some View {
        Group {
            if let account {
                AccountDetailView(account: account)
            } else if failed {
                VStack(spacing: 10) {
                    Text("Couldn't open \(name).").foregroundColor(.secondary)
                    Button("Retry") { Task { await load() } }
                }
            } else {
                ProgressView().task { await load() }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        failed = false
        do {
            account = try await CRMService.shared.getAccount(id: accountId)
        } catch {
            failed = true
        }
    }
}

// MARK: - Mark complete (asks for the Outcome)

/// The card's Mark complete / Reopen button. Outside Spark & Ray (and for Reopen, or an activity that already
/// has an Outcome) it is exactly `ActivityCompletionButton`. For Spark, completing an activity with no Outcome
/// first asks for one: it is saved on the activity, then the completion goes out.
struct SparkAwareCompletionButton: View {
    let activity: Activity
    let kind: ActivityCompletion.Action
    let handler: (Activity, Bool) async -> Void

    @State private var asking = false

    init(activity: Activity, kind: ActivityCompletion.Action, handler: @escaping (Activity, Bool) async -> Void) {
        self.activity = activity
        self.kind = kind
        self.handler = handler
    }

    private var needsOutcome: Bool {
        SparkActivityOutcome.needsPromptOnComplete(
            spark: SparkJourney.isActive, action: kind, existingOutcome: activity.outcome
        )
    }

    var body: some View {
        ActivityCompletionButton(kind: kind) {
            if needsOutcome {
                asking = true
            } else {
                await handler(activity, kind.targetCompleted)
            }
        }
        .sheet(isPresented: $asking) {
            SparkOutcomePromptSheet(subject: activity.subject ?? "Activity") { text in
                _ = try await CRMService.shared.updateActivity(
                    id: activity.id, body: SparkActivityOutcome.saveBody(text)
                )
                await handler(activity, true)
            }
        }
    }
}

/// "What was the outcome?" — required before an activity is marked complete.
struct SparkOutcomePromptSheet: View {
    let subject: String
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var errorText: String? = nil

    init(subject: String, onSave: @escaping (String) async throws -> Void) {
        self.subject = subject
        self.onSave = onSave
    }

    private var canSave: Bool {
        !saving && !SparkActivityOutcome.trimmed(text).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was the outcome?", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                    if let err = errorText {
                        Text(err).font(.footnote).foregroundColor(.red)
                    }
                } header: {
                    Text("Outcome (required)")
                } footer: {
                    Text("Completing \"\(subject)\" needs an outcome.")
                }
            }
            .navigationTitle("Complete activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Complete").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: text) { _, newValue in
                if newValue.count > SparkActivityOutcome.maxLength {
                    text = String(newValue.prefix(SparkActivityOutcome.maxLength))
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorText = nil
        defer { saving = false }
        do {
            try await onSave(text)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
