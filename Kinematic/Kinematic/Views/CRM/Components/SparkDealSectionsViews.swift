import SwiftUI
import Combine

// Spark & Ray deal sections UI:
//   - DealSectionsModel          loads `config.deal_sections` (enabled / label / position) from /crm/settings
//   - SparkDealSectionsForm      the Quotation / Pricing / Product trial / Approvals sections of the deal
//                                create + edit forms (a run of `Section`s, in the admin's order)
//   - SparkDealSectionsDetail    the same sections, read-only, on the deal detail
//
// Every host shows these ONLY for the Spark & Ray client (`SparkJourney.isActive`). The pure logic
// (config parsing / ordering, final price, trial validation, request bodies) is in
// `Models/CRM/SparkDealSections.swift`. Each field is a built-in deal field, so it is gated through
// `LeadFieldOverridesModel` (hidden / relabel) and held back until both the overrides and the section
// config have loaded.

// MARK: - Config loader

@MainActor
final class DealSectionsModel: ObservableObject {
    @Published private(set) var config = DealSectionsConfig()
    /// True once the settings request has completed (success or not). Until then the forms render no
    /// section, so a section the admin disabled never flashes up.
    @Published private(set) var didLoad = false

    func load(using fetch: () async -> CRMService.CRMSettingsRaw? = { await CRMService.shared.getCRMSettings() }) async {
        let raw = await fetch()
        config = DealSectionsConfig.parse(settings: raw)
        didLoad = true
    }
}

// MARK: - Optional date row

/// A "YYYY-MM-DD" value that can be unset: a toggle plus a date picker. `minDate` keeps the picker from
/// going before another date (trial end >= start).
private struct SparkOptionalDateRow: View {
    let title: String
    @Binding var value: String
    var minDate: Date? = nil

    private var isOn: Binding<Bool> {
        Binding(
            get: { !value.isEmpty },
            set: { on in
                value = on ? SparkDealDate.format(minDate ?? Date()) : ""
            }
        )
    }

    private var date: Binding<Date> {
        Binding(
            get: { SparkDealDate.parse(value) ?? Date() },
            set: { value = SparkDealDate.format($0) }
        )
    }

    var body: some View {
        Toggle(title, isOn: isOn)
        if !value.isEmpty {
            if let minDate {
                DatePicker("\(title) date", selection: date, in: minDate..., displayedComponents: .date)
            } else {
                DatePicker("\(title) date", selection: date, displayedComponents: .date)
            }
        }
    }
}

// MARK: - Person row

/// One "who" dropdown: None + the org's users. A person who is stored but not in the list (outside the
/// caller's team, or the list is still loading) stays selectable so the picker never points at a missing tag.
private struct SparkPersonPickerRow: View {
    let label: String
    let users: [AssignableUser]
    let knownNames: [String: String]
    @Binding var selectedId: String

    private var selectedIsListed: Bool {
        selectedId.isEmpty || users.contains { $0.id == selectedId }
    }

    var body: some View {
        Picker(label, selection: $selectedId) {
            Text("— None —").tag("")
            if !selectedIsListed {
                Text(knownNames[selectedId] ?? "Current person").tag(selectedId)
            }
            ForEach(users) { u in
                Text(u.displayName).tag(u.id)
            }
        }
    }
}

// MARK: - Form sections

struct SparkDealSectionsForm: View {
    @ObservedObject var model: DealSectionsModel
    @ObservedObject var fieldOverrides: LeadFieldOverridesModel
    @Binding var draft: SparkDealSectionsDraft
    /// The org's assignable users (the same source the owner / assignee pickers use).
    let users: [AssignableUser]
    /// id -> name for people already on the deal who may not be in `users` (edit form).
    var knownNames: [String: String] = [:]
    /// The quotation number is typed on create only; the edit form leaves it to the backend's rules.
    var includeQuotation: Bool = true

    private func visible(_ key: String) -> Bool {
        !fieldOverrides.isHidden(entity: "deal", key)
    }

    private func label(_ key: String, _ fallback: String) -> String {
        fieldOverrides.labelFor(entity: "deal", key, fallback)
    }

    private func anyVisible(_ keys: [String]) -> Bool {
        keys.contains { visible($0) }
    }

    var body: some View {
        if model.didLoad && fieldOverrides.didLoad {
            ForEach(model.config.ordered, id: \.self) { key in
                sectionView(key)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ key: DealSectionKey) -> some View {
        switch key {
        case .quotation:
            if includeQuotation && visible(SparkDealSectionsDraft.quotationKey) { quotationSection }
        case .pricing:
            if anyVisible(SparkDealSectionsDraft.pricingKeys) { pricingSection }
        case .productTrial:
            if anyVisible(SparkDealSectionsDraft.trialKeys) { trialSection }
        case .approvals:
            if anyVisible(SparkDealSectionsDraft.peopleKeys) { approvalsSection }
        }
    }

    // MARK: Quotation

    private var quotationSection: some View {
        Section(model.config.label(.quotation)) {
            TextField(label(SparkDealSectionsDraft.quotationKey, "Quotation number"), text: $draft.quotationNo)
                .autocorrectionDisabled()
        }
    }

    // MARK: Pricing

    private func amountRow(_ key: String, _ fallback: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label(key, fallback))
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private var pricingSection: some View {
        Section(model.config.label(.pricing)) {
            if visible("pricing_quoted") {
                amountRow("pricing_quoted", "Quoted price (₹)", text: $draft.quotedText, placeholder: "0")
            }
            if visible("pricing_discount_pct") {
                amountRow("pricing_discount_pct", "Discount (%)", text: $draft.discountText, placeholder: "0")
            }
            if visible("pricing_final") {
                HStack {
                    Text(label("pricing_final", "Final price (₹)"))
                    Spacer()
                    Text(draft.finalPrice.map { CurrencyFormatter.formatINR($0) } ?? "—")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Brand.red)
                }
            }
            if visible("pricing_valid_till") {
                SparkOptionalDateRow(title: label("pricing_valid_till", "Valid till"), value: $draft.validTill)
            }
            if let err = SparkPricing.validate(quotedText: draft.quotedText, discountText: draft.discountText) {
                Text(err).font(.footnote).foregroundColor(.red)
            }
        }
    }

    // MARK: Product trial

    private var trialRequiredBinding: Binding<Int> {
        Binding(
            get: {
                switch draft.trialRequired {
                case .some(true): return 1
                case .some(false): return 2
                case .none: return 0
                }
            },
            set: { v in
                switch v {
                case 1: draft.trialRequired = true
                case 2: draft.trialRequired = false
                default: draft.trialRequired = nil
                }
            }
        )
    }

    /// A trial that is on but has no result yet reads as Pending (what is sent).
    private var trialResultBinding: Binding<String> {
        Binding(
            get: { draft.effectiveTrialResult },
            set: { draft.trialResult = $0 }
        )
    }

    private var trialMinEnd: Date? {
        SparkDealDate.parse(draft.trialStart)
    }

    private var trialSection: some View {
        Section(model.config.label(.productTrial)) {
            if visible("trial_required") {
                Picker(label("trial_required", "Trial needed"), selection: trialRequiredBinding) {
                    Text("—").tag(0)
                    Text("Yes").tag(1)
                    Text("No").tag(2)
                }
            }
            if draft.trialRequired == true {
                trialDetailRows
            }
        }
    }

    @ViewBuilder
    private var trialDetailRows: some View {
        if visible("trial_start") {
            SparkOptionalDateRow(title: label("trial_start", "Trial start"), value: $draft.trialStart)
        }
        if visible("trial_end") {
            SparkOptionalDateRow(title: label("trial_end", "Trial end"), value: $draft.trialEnd, minDate: trialMinEnd)
        }
        if visible("trial_result") {
            Picker(label("trial_result", "Result"), selection: trialResultBinding) {
                ForEach(SparkTrialResult.allCases, id: \.rawValue) { r in
                    Text(r.label).tag(r.rawValue)
                }
            }
        }
        if visible("trial_notes") {
            TextField(label("trial_notes", "Trial notes"), text: $draft.trialNotes, axis: .vertical)
                .lineLimit(2...5)
        }
        if let err = SparkTrial.validate(start: draft.trialStart, end: draft.trialEnd) {
            Text(err).font(.footnote).foregroundColor(.red)
        }
    }

    // MARK: Approvals / people

    private var approvalsSection: some View {
        Section(model.config.label(.approvals)) {
            if visible("technical_approval_by") {
                SparkPersonPickerRow(
                    label: label("technical_approval_by", "Technical approval given by"),
                    users: users, knownNames: knownNames, selectedId: $draft.technicalApprovalBy)
            }
            if visible("prepared_by") {
                SparkPersonPickerRow(
                    label: label("prepared_by", "Prepared by"),
                    users: users, knownNames: knownNames, selectedId: $draft.preparedBy)
            }
            if visible("checked_by") {
                SparkPersonPickerRow(
                    label: label("checked_by", "Checked by"),
                    users: users, knownNames: knownNames, selectedId: $draft.checkedBy)
            }
            if visible("supervisor_id") {
                SparkPersonPickerRow(
                    label: label("supervisor_id", "Supervisor name"),
                    users: users, knownNames: knownNames, selectedId: $draft.supervisorId)
            }
        }
    }
}

// MARK: - Detail (read-only)

struct SparkDealSectionsDetail: View {
    let deal: Deal
    @ObservedObject var model: DealSectionsModel
    @ObservedObject var fieldOverrides: LeadFieldOverridesModel

    private func visible(_ key: String) -> Bool {
        !fieldOverrides.isHidden(entity: "deal", key)
    }

    private func label(_ key: String, _ fallback: String) -> String {
        fieldOverrides.labelFor(entity: "deal", key, fallback)
    }

    /// (label, value) rows a section has for this deal; a section without any is not drawn.
    private func rows(_ key: DealSectionKey) -> [(String, String)] {
        var out: [(String, String)] = []
        func add(_ field: String, _ fallback: String, _ value: String?) {
            guard visible(field), let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
            out.append((label(field, fallback), v))
        }
        switch key {
        case .quotation:
            add(SparkDealSectionsDraft.quotationKey, "Quotation number", deal.quotationNo)
        case .pricing:
            add("pricing_quoted", "Quoted price", deal.pricingQuoted.map { CurrencyFormatter.formatINR($0) })
            add("pricing_discount_pct", "Discount", deal.pricingDiscountPct.map { SparkJourney.priceText($0) + "%" })
            add("pricing_final", "Final price", deal.pricingFinal.map { CurrencyFormatter.formatINR($0) })
            add("pricing_valid_till", "Valid till", SparkDealDate.normalized(deal.pricingValidTill))
        case .productTrial:
            if let required = deal.trialRequired {
                add("trial_required", "Trial needed", required ? "Yes" : "No")
                if required {
                    add("trial_start", "Trial start", SparkDealDate.normalized(deal.trialStart))
                    add("trial_end", "Trial end", SparkDealDate.normalized(deal.trialEnd))
                    let result = SparkTrialResult(rawValue: (deal.trialResult ?? "").lowercased())?.label
                    add("trial_result", "Result", result)
                    add("trial_notes", "Trial notes", deal.trialNotes)
                }
            }
        case .approvals:
            add("technical_approval_by", "Technical approval", deal.technicalApprovalByName)
            add("prepared_by", "Prepared by", deal.preparedByName)
            add("checked_by", "Checked by", deal.checkedByName)
            add("supervisor_id", "Supervisor", deal.supervisorIdName)
        }
        return out
    }

    var body: some View {
        if model.didLoad && fieldOverrides.didLoad {
            ForEach(model.config.ordered, id: \.self) { key in
                card(key)
            }
        }
    }

    @ViewBuilder
    private func card(_ key: DealSectionKey) -> some View {
        let items = rows(key)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.config.label(key).uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .foregroundColor(Brand.red)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(item.0.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.secondary)
                            .frame(width: 110, alignment: .leading)
                        Text(item.1)
                            .font(.system(size: 13, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
        }
    }
}
