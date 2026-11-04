import SwiftUI

struct DealCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var accountId = ""
    @State private var amount: Double = 0
    @State private var hasCloseDate = false
    @State private var expectedCloseDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var pipelines: [Pipeline] = []
    @State private var stages: [Stage] = []
    @State private var pipelineId: String = ""
    @State private var stageId: String = ""

    /// Admin-defined deal custom fields (e.g. the SRS Dealer lookup).
    /// Same model + section the lead / activity forms use; renders
    /// nothing when the tenant has no entity_type='deal' defs.
    @StateObject private var customFields = CustomFieldsModel()
    /// Built-in field overrides (hide / relabel / require) for deal columns,
    /// configured on the web Settings → Custom Fields page. Deals aren't
    /// B2B/B2C-scoped so no isB2C is passed.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()
    /// Multi-row product basket (product interest) for steel dealers —
    /// writes custom_fields.product_lines + the legacy single-product
    /// mirrors, and its estimated_amount total seeds the deal amount.
    @StateObject private var productLines = ProductLinesModel()

    // MARK: Spark & Ray (customer picker, quotation number, product lines)
    // Everything below is shown / sent ONLY for the Spark & Ray client (`isSpark`). The non-Spark
    // form is exactly as it was.
    @State private var selectedAccount: CRMAccount? = nil
    @State private var showAccountPicker = false
    @State private var quotationNo = ""
    @State private var lines: [DealLineDraft] = [DealLineDraft()]
    @State private var catalogue: [Product] = []
    @State private var pickingLineId: UUID? = nil
    @State private var didSeedPrefill = false
    @State private var submitting = false
    @State private var submitError: String? = nil
    /// Throwing save handler for Spark hosts (set via `sparkSubmit(_:)`): the sheet stays open and
    /// shows the server's message if it throws. Without it Spark falls back to `onSubmit`.
    private var onSparkSubmit: (([String: Any]) async throws -> Void)? = nil

    /// Customer to preselect (launched from an account's "New deal").
    var prefillAccount: CRMAccount? = nil
    /// Lead this deal comes from (launched from a lead's "New deal") — sent as `lead_id`. A
    /// converted lead's customer account is attached by the backend.
    var prefillLeadId: String? = nil

    let onSubmit: ([String: Any]) async -> Void

    private var isSpark: Bool { SparkJourney.isActive }

    /// Opt in to the throwing save path (Spark & Ray only; ignored for other clients).
    func sparkSubmit(_ handler: @escaping ([String: Any]) async throws -> Void) -> DealCreateView {
        var copy = self
        copy.onSparkSubmit = handler
        return copy
    }

    private var currentPipeline: Pipeline? {
        pipelines.first(where: { $0.id == pipelineId })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deal") {
                    if !fieldOverrides.isHidden(entity: "deal", "name") {
                        TextField(fieldOverrides.labelFor(entity: "deal", "name", "Deal name"), text: $name)
                    }
                    // Spark with product lines: the amount is the lines' total (shown under Products).
                    if !fieldOverrides.isHidden(entity: "deal", "amount") && !(isSpark && !DealLines.active(lines).isEmpty) {
                        HStack {
                            Text(fieldOverrides.labelFor(entity: "deal", "amount", "Amount (₹)"))
                            Spacer()
                            TextField("0", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if isSpark {
                        sparkCustomerRows
                    } else if !fieldOverrides.isHidden(entity: "deal", "account_id") {
                        TextField(fieldOverrides.labelFor(entity: "deal", "account_id", "Account ID (optional)"), text: $accountId)
                    }
                }

                if isSpark {
                    sparkProductsSection
                }

                // Spark picks the pipeline + stage on the server.
                if !isSpark && !pipelines.isEmpty && (!fieldOverrides.isHidden(entity: "deal", "pipeline_id") || !fieldOverrides.isHidden(entity: "deal", "stage_id")) {
                    Section("Pipeline") {
                        if !fieldOverrides.isHidden(entity: "deal", "pipeline_id") {
                            if pipelines.count == 1 {
                                // Single pipeline: show a read-only label instead of a
                                // useless picker. Matches the web dashboard's behaviour
                                // where the dropdown collapses to a static "Default
                                // pipeline" affordance when there's nothing to choose.
                                HStack {
                                    Text(currentPipeline?.name ?? "Default pipeline")
                                    Spacer()
                                    Text("· default")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            } else {
                                Picker(fieldOverrides.labelFor(entity: "deal", "pipeline_id", "Pipeline"), selection: $pipelineId) {
                                    ForEach(pipelines) { p in
                                        if p.isDefault == true {
                                            Text("\(p.name) (default)").tag(p.id)
                                        } else {
                                            Text(p.name).tag(p.id)
                                        }
                                    }
                                }
                                .onChange(of: pipelineId) { _, newId in
                                    Task { await loadStages(pipelineId: newId) }
                                }
                            }
                        }
                        if !fieldOverrides.isHidden(entity: "deal", "stage_id") && !stages.isEmpty {
                            Picker(fieldOverrides.labelFor(entity: "deal", "stage_id", "Stage"), selection: $stageId) {
                                ForEach(stages) { s in Text(s.name).tag(s.id) }
                            }
                        }
                    }
                }

                if !fieldOverrides.isHidden(entity: "deal", "expected_close_date") {
                    Section(fieldOverrides.labelFor(entity: "deal", "expected_close_date", "Close date")) {
                        Toggle("Set expected close date", isOn: $hasCloseDate)
                        if hasCloseDate {
                            DatePicker("Expected close", selection: $expectedCloseDate, displayedComponents: .date)
                        }
                    }
                }

                // Admin-defined deal custom fields (Dealer lookup, …).
                // Self-gates on loaded defs; renders nothing when none exist.
                CustomFieldsSection(model: customFields)

                // Steel dealers (Tata Tiscon + BMW) capture the product
                // basket on the deal itself — multiple products with
                // per-line qty/unit and weight- or piece-based pricing.
                // Mirrors the web dashboard's deal-create form.
                if ClientFeatures.isTataTiscon {
                    ProductLinesSection(model: productLines)
                }
            }
            .navigationTitle("New Deal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }.disabled(submitting || (!fieldOverrides.isHidden(entity: "deal", "name") && name.isEmpty))
                }
            }
            .sheet(isPresented: $showAccountPicker) {
                SparkAccountPickerSheet { account in
                    selectedAccount = account
                    accountId = account.id
                }
            }
            .sheet(isPresented: Binding(
                get: { pickingLineId != nil },
                set: { if !$0 { pickingLineId = nil } }
            )) {
                SparkLineProductPicker(products: catalogue) { product in
                    if let id = pickingLineId, let i = lines.firstIndex(where: { $0.id == id }) {
                        lines[i].apply(product: product)
                    }
                }
            }
            .task {
                if !didSeedPrefill {
                    didSeedPrefill = true
                    if let a = prefillAccount {
                        selectedAccount = a
                        accountId = a.id
                    }
                }
            }
            .task { if !isSpark { await loadPipelines() } }
            .task { await customFields.load(entity: "deal") }
            .task { await fieldOverrides.load() }
            .task { await productLines.load() }
            .task {
                if isSpark {
                    let all = (try? await CRMService.shared.listProducts()) ?? []
                    catalogue = all.filter { $0.isActive != false }
                }
            }
        }
    }

    // MARK: Spark & Ray rows

    /// Customer (account) picker + quotation number. Both are built-in deal columns, so they are
    /// gated through the field overrides (and held back until the overrides have loaded).
    @ViewBuilder
    private var sparkCustomerRows: some View {
        if fieldOverrides.didLoad {
            if !fieldOverrides.isHidden(entity: "deal", "account_id") {
                Button {
                    showAccountPicker = true
                } label: {
                    HStack {
                        Text(fieldOverrides.labelFor(entity: "deal", "account_id", "Customer"))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(selectedAccount?.name ?? "Select")
                            .foregroundColor(selectedAccount == nil ? .secondary : .primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
                if selectedAccount == nil && prefillLeadId != nil {
                    Text("A converted lead's customer is attached automatically.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            if !fieldOverrides.isHidden(entity: "deal", "quotation_no") {
                TextField(fieldOverrides.labelFor(entity: "deal", "quotation_no", "Quotation number"), text: $quotationNo)
                    .autocorrectionDisabled()
            }
        }
    }

    /// Product lines editor: add / remove rows, product picker prefills name + price, qty and unit
    /// price editable, per-line and grand totals.
    @ViewBuilder
    private var sparkProductsSection: some View {
        Section {
            ForEach($lines) { $line in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TextField("Product / item", text: $line.name)
                        Button {
                            pickingLineId = line.id
                        } label: {
                            Image(systemName: "shippingbox").foregroundColor(Brand.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Pick from catalogue")
                        Button(role: .destructive) {
                            removeLine(line.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove line")
                    }
                    HStack(spacing: 8) {
                        TextField("Qty", text: $line.quantityText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                        Text("×").foregroundColor(.secondary)
                        TextField("Unit price (₹)", text: $line.unitPriceText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Spacer(minLength: 4)
                        Text(CurrencyFormatter.formatINR(line.lineTotal))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Brand.red)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
            }
            Button {
                lines.append(DealLineDraft())
            } label: {
                Label("Add product line", systemImage: "plus.circle.fill")
            }
            HStack {
                Text("Total").font(.system(size: 14, weight: .bold))
                Spacer()
                Text(CurrencyFormatter.formatINR(DealLines.grandTotal(lines)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Brand.red)
            }
            if let err = submitError {
                Text(err).font(.footnote).foregroundColor(.red)
            }
        } header: {
            Text("Products")
        }
    }

    private func removeLine(_ id: UUID) {
        lines.removeAll { $0.id == id }
        if lines.isEmpty { lines = [DealLineDraft()] }
    }

    /// Save. Spark validates the lines first and, with a throwing handler, keeps the sheet open on
    /// an error; every other client keeps the original fire-and-dismiss path.
    @MainActor
    private func save() async {
        if isSpark {
            if let problem = DealLines.firstProblem(lines) {
                submitError = problem
                return
            }
            submitError = nil
        }
        let body = buildBody()
        if isSpark, let handler = onSparkSubmit {
            submitting = true
            defer { submitting = false }
            do {
                try await handler(body)
                dismiss()
            } catch {
                submitError = error.localizedDescription
            }
            return
        }
        await onSubmit(body)
        dismiss()
    }

    private func loadPipelines() async {
        pipelines = (try? await CRMService.shared.listPipelines()) ?? []
        if pipelineId.isEmpty {
            // Prefer the org's default pipeline; fall back to the first one so
            // we never end up with an empty selection when at least one
            // pipeline exists.
            let preferred = pipelines.first(where: { $0.isDefault == true }) ?? pipelines.first
            if let preferred { pipelineId = preferred.id }
        }
        if !pipelineId.isEmpty { await loadStages(pipelineId: pipelineId) }
    }

    private func loadStages(pipelineId: String) async {
        stages = (try? await CRMService.shared.listStages(pipelineId: pipelineId)) ?? []
        if stageId.isEmpty, let first = stages.first { stageId = first.id }
    }

    private func buildBody() -> [String: Any] {
        var body: [String: Any] = ["name": name, "amount": amount, "status": "open"]
        if !accountId.isEmpty { body["account_id"] = accountId }
        // Spark leaves pipeline + stage to the server.
        if !isSpark && !pipelineId.isEmpty { body["pipeline_id"] = pipelineId }
        if !isSpark && !stageId.isEmpty { body["stage_id"] = stageId }
        if hasCloseDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            body["expected_close_date"] = f.string(from: expectedCloseDate)
        }
        // Merge the product basket into custom_fields last so its
        // product_lines + legacy mirrors win over any stale generic values.
        var cf = customFields.jsonValues
        for (k, v) in productLines.jsonValues { cf[k] = v }
        if !cf.isEmpty { body["custom_fields"] = cf }
        // When the rep didn't type an amount, default it to the basket
        // total so the deal value matches the picked products.
        if amount == 0, let total = productLines.jsonValues["estimated_amount"] as? Double, total > 0 {
            body["amount"] = total
        }
        // Spark & Ray: customer account, originating lead, quotation number and product lines
        // (its total becomes the amount; the backend recomputes it from `items`).
        if isSpark {
            SparkDealBody.apply(
                to: &body,
                accountId: selectedAccount?.id,
                leadId: prefillLeadId,
                quotationNo: quotationNo,
                lines: lines
            )
        }
        return body
    }
}

/// Single-select catalogue picker for a deal line: tapping a product fills the line's name + price.
private struct SparkLineProductPicker: View {
    let products: [Product]
    let onPick: (Product) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Product] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return products }
        return products.filter {
            $0.name.lowercased().contains(q) || ($0.sku ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if products.isEmpty {
                    Text("No products in the catalogue.").font(.caption).foregroundColor(.secondary)
                }
                ForEach(filtered) { p in
                    Button {
                        onPick(p)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).foregroundColor(.primary)
                                if let sku = p.sku, !sku.isEmpty {
                                    Text(sku).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if let price = p.unitPrice {
                                Text(CurrencyFormatter.formatINR(price)).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search products")
            .navigationTitle("Select product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
