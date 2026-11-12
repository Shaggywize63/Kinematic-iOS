import SwiftUI

struct ActivityComposeView: View {
    @Environment(\.dismiss) private var dismiss

    /// Optional prefill — call buttons pass `initialType="call"` and a
    /// subject like "Call with <Name>". Default to "call" type + empty
    /// subject so existing callers (e.g. ActivitiesView's "Add" button)
    /// keep their previous behavior.
    let initialType: String
    let initialSubject: String
    /// Optional prefilled description + date. The KINI ✨ Suggest chips on the
    /// lead detail pass a drafted body (and a due date for tasks) so the rep
    /// lands on a ready-to-save composer. Defaults keep every existing caller
    /// unchanged (empty body, "now").
    let initialDescription: String
    let initialWhen: Date?
    /// When true, the composer offers a lead picker (used by the global
    /// Activities "+", where there's no parent record). Detail screens pass
    /// false — they already supply the linked entity themselves.
    let allowLeadPicker: Bool
    /// Scheduling mode. When true the composer creates a *future, open*
    /// activity (a reminder) rather than *logging* a completed one: the title,
    /// button and date label change, the date defaults to the near future, and
    /// "note" (which never reminds) is dropped from the type picker. The caller
    /// routes the submit to `schedule(...)` (status=open + due_at) so the
    /// backend reminder cron picks it up.
    let scheduled: Bool
    /// Callback receives type, subject, description, optional imageUrl, the
    /// chosen "when" date, an optional picked lead id (nil unless a lead was
    /// chosen via the picker), and the entered admin-defined activity
    /// custom-field values keyed by `field_key` (empty when the tenant has
    /// none configured). Mirrors how the lead form threads `custom_fields`.
    let onSubmit: (String, String, String, String?, Date, String?, [String: Any]) async -> Void

    // MARK: Spark & Ray extras (opt-in)
    // Set through `sparkSubmit(...)` — never through `init`, so every existing call site is
    // untouched. When a host opts in AND the client is Spark & Ray, the composer adds
    // "Assign to (multiple)", "Product interested" and "Form serial", and on save calls this
    // throwing handler (with the extras) INSTEAD of `onSubmit`. A throw keeps the sheet open and
    // shows the server's message by the field (a bad form serial comes back as HTTP 400).
    var onSparkSubmit: ((ActivityComposeResult) async throws -> Void)? = nil
    /// Extras to start from when editing an existing activity.
    var sparkInitial = SparkActivityExtras()
    /// id -> name for people / products already on the activity being edited, shown before
    /// (or without) the pickers' lists loading.
    var sparkNames: [String: String] = [:]

    // MARK: Assignee on an existing activity (opt-in)
    // Set through `editingAssignment(...)` by the host that edits an EXISTING activity. Creating keeps today's
    // behaviour for everyone. Editing: only admins / managers (`RecordOwnerRules`) can change who it is
    // assigned to — Spark & Ray's multi-assignee picker is then read-only (names only) for everyone else, and
    // every other client gets a single "Assigned to" picker for admins / managers (read-only name otherwise).
    var editsExisting = false
    var existingAssignedToId: String? = nil
    var existingAssignedToName: String? = nil
    /// The user id picked in the single "Assigned to" picker; nil = unchanged. The host reads it on save.
    var assigneeSelection: Binding<String?>? = nil

    /// The photo already on the activity being edited (shown, and kept unless a new one replaces it).
    var existingImageUrl: String? = nil

    /// Editing only: the activity being edited is already completed (so its Spark Outcome is required).
    var existingCompleted = false

    // MARK: Follow-up (Log mode, opt-in)
    // Set through `allowingFollowUp(_:)`. Logging offers an optional "Schedule a follow-up" (Scheduled / due)
    // date next to the Activity (done) date. The two never clear each other; with BOTH set the host creates
    // two activities (see `ActivityLogPlan`). The host owns the binding and reads it on save.
    var followUpAt: Binding<Date?>? = nil

    // MARK: Edit extras (opt-in)
    // Set through `editingExtras(_:showsDate:)` by the host that edits an EXISTING activity: the "Linked
    // entity" (Lead / Contact / Deal / Account / None) and the "Activity date & time", which is shown only
    // when the activity already has `completed_at` and cannot be in the future.
    var editState: Binding<ActivityEditState>? = nil
    var showsEditDate = false
    @State private var showLinkPicker = false

    @State private var type: String
    @State private var subject: String
    @State private var desc: String
    /// The org's activity types (built-ins + custom ones from Settings). Falls back to the built-ins until loaded.
    @ObservedObject private var typeStore = ActivityTypesStore.shared
    /// Picked lead (only when allowLeadPicker). Its phone shows in the row.
    @State private var selectedLead: Lead? = nil
    @State private var showLeadPicker = false
    /// Editable timestamp for the activity. Defaults to now so the common
    /// case (logging right after the action) is one tap. The picker is
    /// surfaced for every non-task type; tasks reuse this as `due_at`.
    @State private var when: Date

    // Image attachment state — mirrors the web activity composer.
    @State private var pickedImage: UIImage? = nil
    @State private var showCameraSheet: Bool = false
    @State private var showLibrarySheet: Bool = false
    @State private var uploading: Bool = false
    @State private var imageUrl: String? = nil
    @State private var showSourceSheet: Bool = false
    /// The last photo upload failed while online — Save stays off until it is retried or the photo removed.
    @State private var uploadFailed: Bool = false

    /// Admin-defined custom fields for activities (e.g. a Dealer lookup,
    /// Visit kind select, First visit toggle), scoped to the user's org
    /// role. Loaded on appear; `jsonValues` is threaded into the save
    /// payload under `custom_fields`. Same model + section the lead
    /// create form uses.
    @StateObject private var customFields = CustomFieldsModel()

    // Spark extras state (only used when `showsSparkExtras`).
    @State private var sparkExtras = SparkActivityExtras()
    @State private var sparkSeeded = false
    @State private var sparkUsers: [AssignableUser] = []
    @State private var sparkProducts: [Product] = []
    @State private var showAssigneePicker = false
    @State private var showProductPicker = false
    @State private var sparkSerialError: String? = nil
    @State private var sparkGeneralError: String? = nil
    @State private var submitting = false
    /// People for the single "Assigned to" picker (non-Spark edit by an admin / manager).
    @State private var assignableUsers: [AssignableUser] = []

    init(
        initialType: String = "meeting",
        initialSubject: String = "",
        initialDescription: String = "",
        initialWhen: Date? = nil,
        allowLeadPicker: Bool = false,
        scheduled: Bool = false,
        onSubmit: @escaping (String, String, String, String?, Date, String?, [String: Any]) async -> Void
    ) {
        self.initialType = initialType
        self.initialSubject = initialSubject
        self.initialDescription = initialDescription
        self.initialWhen = initialWhen
        self.allowLeadPicker = allowLeadPicker
        self.scheduled = scheduled
        self.onSubmit = onSubmit
        // Steel-dealer tenants (Tata Tiscon / BMW) run a fixed site-visit
        // flow: the type is locked to "site_visit" and the subject defaults
        // to "First Visit". Every other tenant keeps the caller-provided
        // type + subject unchanged. When scheduling (not steel-dealer), default
        // the type to "task" — the natural "remind me to…" shape.
        let steelDealer = ClientFeatures.isTataTiscon
        let defaultType = steelDealer ? "site_visit" : (scheduled && initialType == "meeting" ? "task" : initialType)
        _type = State(initialValue: defaultType)
        _subject = State(initialValue: (initialSubject.isEmpty && steelDealer) ? "First Visit" : initialSubject)
        _desc = State(initialValue: initialDescription)
        // Scheduling defaults to a near-future time (next hour, on the hour) so
        // the reminder is actually ahead of "now"; logging defaults to now.
        _when = State(initialValue: initialWhen ?? (scheduled ? Self.defaultReminderTime() : Date()))
    }

    /// Next round hour from now — a sensible default target for a new reminder.
    private static func defaultReminderTime() -> Date {
        let cal = Calendar.current
        let inOneHour = Date().addingTimeInterval(3600)
        return cal.date(bySetting: .minute, value: 0, of: inOneHour) ?? inOneHour
    }

    /// A filled lookup-typed custom field (the Dealer / People Directory
    /// picker) anchors the activity just like a lead — steel-dealer reps
    /// log directory-only visits with no lead attached, and the backend
    /// accepts a lookup custom field as the link.
    private var hasDirectoryLink: Bool {
        customFields.defs.contains { d in
            d.fieldType == "lookup" && !(customFields.text[d.fieldKey] ?? "").isEmpty
        }
    }

    /// Human label for an activity type slug — used to derive the subject now
    /// that the Subject field is gone. `capitalized` handles the built-ins
    /// ("meeting" → "Meeting"); "site_visit" is special-cased so it doesn't
    /// render as "Site_visit".
    private func labelForType(_ t: String) -> String {
        typeStore.name(for: t)
    }

    /// The subject we persist. A caller-supplied subject wins (the call button
    /// / site-visit prefill sets a descriptive one); otherwise fall back to the
    /// selected type's display name so the timeline and reports still read.
    private var effectiveSubject: String {
        let s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? labelForType(type) : s
    }

    /// Opt this composer into the Spark & Ray extras. `handler` replaces `onSubmit` for Spark
    /// users (it may throw — the sheet then stays open and shows the message); for every other
    /// client `onSubmit` runs exactly as before. `initial` / `names` seed an edit.
    func sparkSubmit(
        initial: SparkActivityExtras = SparkActivityExtras(),
        names: [String: String] = [:],
        _ handler: @escaping (ActivityComposeResult) async throws -> Void
    ) -> ActivityComposeView {
        var copy = self
        copy.onSparkSubmit = handler
        copy.sparkInitial = initial
        copy.sparkNames = names
        return copy
    }

    /// Opt this composer into "editing an existing activity": the assignee control is then changeable only for
    /// admins / managers. `selection` receives the single picker's choice (nil = unchanged).
    func editingAssignment(
        assignedToId: String?,
        assignedToName: String?,
        selection: Binding<String?>
    ) -> ActivityComposeView {
        var copy = self
        copy.editsExisting = true
        copy.existingAssignedToId = assignedToId
        copy.existingAssignedToName = assignedToName
        copy.assigneeSelection = selection
        return copy
    }

    /// Show the photo already attached to the activity being edited.
    func withExistingPhoto(_ url: String?) -> ActivityComposeView {
        var copy = self
        copy.existingImageUrl = url
        return copy
    }

    /// Editing an existing activity: whether it is already completed, which makes the Spark Outcome required.
    func withExistingCompletion(_ completed: Bool) -> ActivityComposeView {
        var copy = self
        copy.existingCompleted = completed
        return copy
    }

    /// Log mode: offer the optional Scheduled (follow-up) date. `date` is nil until the person turns it on.
    func allowingFollowUp(_ date: Binding<Date?>) -> ActivityComposeView {
        var copy = self
        copy.followUpAt = date
        return copy
    }

    /// Editing an existing activity: the "Linked entity" control and (when `showsDate`) the "Activity date &
    /// time". `state` is read by the host on save.
    func editingExtras(_ state: Binding<ActivityEditState>, showsDate: Bool) -> ActivityComposeView {
        var copy = self
        copy.editState = state
        copy.showsEditDate = showsDate
        return copy
    }

    /// The Spark extras show only for the Spark & Ray client, and only when the host handles them.
    private var showsSparkExtras: Bool {
        onSparkSubmit != nil && SparkJourney.isActive
    }

    /// Creating: anyone, as before. Editing an existing activity: admins / managers only.
    private var canChangeAssignees: Bool {
        !editsExisting || RecordOwnerRules.currentUserCanChange
    }

    /// Spark: the Outcome must be filled in when the activity is being logged / is completed (see
    /// `SparkActivityOutcome.isRequired`); optional while it is only scheduled.
    private var outcomeRequired: Bool {
        showsSparkExtras && SparkActivityOutcome.isRequired(
            creating: !editsExisting, scheduled: scheduled, type: type, existingCompleted: existingCompleted
        )
    }

    private var outcomeError: String? {
        // Not before the extras are seeded: an edit starts empty for a moment and must not flash the error.
        (showsSparkExtras && sparkSeeded)
            ? SparkActivityOutcome.validationError(sparkExtras.outcome, required: outcomeRequired) : nil
    }

    /// Logging: a non-task activity is stamped done at `when`, which cannot be in the future.
    private var logsCompletedActivity: Bool {
        !editsExisting && !scheduled && type != "task"
    }

    /// The follow-up (Scheduled / due) control: Log mode, creating, not a task, and only when the host opted in.
    private var followUpVisible: Bool {
        followUpAt != nil && logsCompletedActivity
    }

    /// Inline error for the Activity date: in the future when logging, or an edited date in the future.
    private var activityDateError: String? {
        if logsCompletedActivity { return ActivityLogPlan.activityDateError(when) }
        if editsExisting, showsEditDate, let state = editState?.wrappedValue, state.dateEdited {
            return ActivityDateEditing.validationError(for: when)
        }
        return nil
    }

    private var followUpError: String? {
        guard followUpVisible, let due = followUpAt?.wrappedValue else { return nil }
        return ActivityLogPlan.scheduledDateError(due)
    }

    /// "Pick a <type> to link, or choose None." while a type is chosen without a record.
    private var linkError: String? {
        editState?.wrappedValue.link.validationError
    }

    /// Save stays off until the Spark extras are seeded from the activity being edited — saving earlier would
    /// look like "everyone removed" and clear the assignees.
    private var saveDisabled: Bool {
        if uploading || submitting { return true }
        if activityDateError != nil || followUpError != nil || linkError != nil { return true }
        if !ActivityPhotoRules.canSave(hasPickedPhoto: pickedImage != nil, imageUrl: imageUrl, uploading: uploading) { return true }
        if showsSparkExtras && !sparkSeeded { return true }
        if outcomeError != nil { return true }
        return allowLeadPicker && selectedLead == nil && !hasDirectoryLink
    }

    private var singleAssigneeBinding: Binding<String> {
        Binding(
            get: { assigneeSelection?.wrappedValue ?? existingAssignedToId ?? "" },
            set: { picked in
                if let sel = assigneeSelection {
                    sel.wrappedValue = RecordOwnerRules.selectionAfterPick(picked, original: existingAssignedToId)
                }
            }
        )
    }

    private var existingAssigneeLabel: String {
        let n = (existingAssignedToName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Current assignee" : n
    }

    /// Non-Spark edit: one "Assigned to" picker for an admin / manager, the plain name for everyone else.
    @ViewBuilder
    private var singleAssigneeSection: some View {
        if editsExisting && !showsSparkExtras && assigneeSelection != nil {
            let current = (existingAssignedToId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if RecordOwnerRules.currentUserCanChange && !assignableUsers.isEmpty {
                Section("Assignment") {
                    Picker("Assigned to", selection: singleAssigneeBinding) {
                        if current.isEmpty {
                            Text("Unassigned").tag("")
                        } else if !assignableUsers.contains(where: { $0.id == current }) {
                            Text(existingAssigneeLabel).tag(current)
                        }
                        ForEach(assignableUsers) { u in
                            Text(u.displayName).tag(u.id)
                        }
                    }
                }
            } else if !RecordOwnerRules.currentUserCanChange && !current.isEmpty {
                Section("Assignment") {
                    HStack {
                        Text("Assigned to")
                        Spacer()
                        Text(existingAssigneeLabel).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func sparkPersonName(_ id: String) -> String {
        if let u = sparkUsers.first(where: { $0.id == id }) { return u.displayName }
        if let n = sparkNames[id], !n.isEmpty { return n }
        return "User"
    }

    private func sparkProductName(_ id: String) -> String {
        if let p = sparkProducts.first(where: { $0.id == id }) { return p.name }
        if let n = sparkNames[id], !n.isEmpty { return n }
        return "Product"
    }

    /// "Asha (Primary), Ravi" — the first person picked is the Primary assignee.
    private var sparkAssigneeSummary: String {
        var parts: [String] = []
        for (i, id) in sparkExtras.assigneeIds.enumerated() {
            let n = sparkPersonName(id)
            parts.append(i == 0 ? "\(n) (Primary)" : n)
        }
        return parts.joined(separator: ", ")
    }

    /// Save. Spark hosts get the throwing handler (errors stay inline); everyone else the
    /// original fire-and-dismiss `onSubmit`.
    @MainActor
    private func submit() async {
        // A follow-up only applies to a logged, non-task activity; never carry a stale one to the host.
        if !followUpVisible { followUpAt?.wrappedValue = nil }
        if showsSparkExtras, let handler = onSparkSubmit {
            submitting = true
            sparkSerialError = nil
            sparkGeneralError = nil
            defer { submitting = false }
            let result = ActivityComposeResult(
                type: type,
                subject: effectiveSubject,
                description: desc,
                imageUrl: imageUrl,
                when: when,
                leadId: selectedLead?.id,
                customFields: customFields.jsonValues,
                extras: sparkExtras.cleaned
            )
            do {
                try await handler(result)
                dismiss()
            } catch {
                let message = error.localizedDescription
                if SparkJourney.isSerialError(message) {
                    sparkSerialError = message
                } else {
                    sparkGeneralError = message
                }
            }
            return
        }
        await onSubmit(type, effectiveSubject, desc, imageUrl, when, selectedLead?.id, customFields.jsonValues)
        dismiss()
    }

    /// "Assigned to" names, primary first, for the activity as it was loaded (never changes while editing).
    private var sparkLoadedAssigneeSummary: String {
        let ids = sparkInitial.cleaned.assigneeIds
        if ids.isEmpty { return "Unassigned" }
        var parts: [String] = []
        for (i, id) in ids.enumerated() {
            let n = sparkPersonName(id)
            parts.append(i == 0 && ids.count > 1 ? "\(n) (Primary)" : n)
        }
        return parts.joined(separator: ", ")
    }

    /// The assignee rows of the Spark section. Changeable when creating and for admins / managers on an
    /// edit (they can replace or remove people — removing all leaves it unassigned); a plain list of names
    /// for everyone else on an edit.
    @ViewBuilder
    private var sparkAssigneeRows: some View {
        if canChangeAssignees {
            Button {
                showAssigneePicker = true
            } label: {
                HStack {
                    Text("Assign to (multiple)").foregroundColor(.primary)
                    Spacer()
                    Text(sparkExtras.assigneeIds.isEmpty ? "Optional" : "\(sparkExtras.assigneeIds.count) selected")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }
            if !sparkExtras.assigneeIds.isEmpty {
                Text(sparkAssigneeSummary)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(alignment: .top) {
                Text("Assigned to")
                Spacer()
                Text(sparkLoadedAssigneeSummary)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// Spark: the Outcome text area (required once the activity is completed, optional while scheduled).
    @ViewBuilder
    private var sparkOutcomeSection: some View {
        Section {
            TextField("What was the outcome?", text: $sparkExtras.outcome, axis: .vertical)
                .lineLimit(2...5)
                .onChange(of: sparkExtras.outcome) { _, newValue in
                    if newValue.count > SparkActivityOutcome.maxLength {
                        sparkExtras.outcome = String(newValue.prefix(SparkActivityOutcome.maxLength))
                    }
                }
            if let err = outcomeError {
                Text(err).font(.footnote).foregroundColor(.red)
            }
        } header: {
            Text(outcomeRequired ? "Outcome (required)" : "Outcome")
        }
    }

    /// Everything Spark adds to the composer: the Outcome, then the assignees / product / serial.
    @ViewBuilder
    private var sparkSections: some View {
        if showsSparkExtras {
            sparkOutcomeSection
            sparkExtrasSection
        }
    }

    @ViewBuilder
    private var sparkExtrasSection: some View {
        Section {
            sparkAssigneeRows

            Button {
                showProductPicker = true
            } label: {
                HStack {
                    Text("Product interested").foregroundColor(.primary)
                    Spacer()
                    Text(sparkExtras.productIds.isEmpty ? "Optional" : "\(sparkExtras.productIds.count) selected")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }
            if !sparkExtras.productIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sparkExtras.productIds, id: \.self) { pid in
                            SparkChip(icon: "shippingbox.fill", text: sparkProductName(pid), tint: Brand.red)
                        }
                    }
                }
            }

            TextField("Form serial (e.g. SRPR2627-12)", text: $sparkExtras.formSerial)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .onChange(of: sparkExtras.formSerial) { _, newValue in
                    // Keep the field upper-case as the rep types; whitespace is stripped on save.
                    let upper = newValue.uppercased()
                    if upper != newValue { sparkExtras.formSerial = upper }
                    sparkSerialError = nil
                }
            if let err = sparkSerialError {
                Text(err).font(.footnote).foregroundColor(.red)
            }
            if let err = sparkGeneralError {
                Text(err).font(.footnote).foregroundColor(.red)
            }
        } header: {
            Text("Assign & link")
        }
    }

    /// The types on offer: loaded from /crm/activity-types (built-ins + custom, e.g. "Industry Visit"), with the
    /// built-in set as the fallback. Scheduling drops "note" (it never reminds).
    private var typeChoices: [ActivityTypeDef] {
        typeStore.composerTypes(scheduled: scheduled, ensuring: type)
    }

    /// The type picker: segmented for the classic handful, a menu once custom types make it longer.
    @ViewBuilder
    private var typePicker: some View {
        let choices = typeChoices
        if choices.count <= 5 {
            Picker("Type", selection: $type) {
                ForEach(choices) { t in Text(t.name).tag(t.slug) }
            }
            .pickerStyle(.segmented)
        } else {
            Picker("Type", selection: $type) {
                ForEach(choices) { t in Text(t.name).tag(t.slug) }
            }
            .pickerStyle(.menu)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    if ClientFeatures.isTataTiscon {
                        // Type is fixed to Site Visit for steel-dealer tenants —
                        // show a single locked row instead of the type picker.
                        HStack {
                            Text("Site Visit")
                            Spacer()
                            Image(systemName: "checkmark").foregroundColor(.secondary)
                        }
                    } else {
                        typePicker
                    }
                }
                if allowLeadPicker {
                    Section("Linked lead") {
                        Button {
                            showLeadPicker = true
                        } label: {
                            HStack {
                                if let l = selectedLead {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(l.displayName).foregroundColor(.primary)
                                        if let phone = l.phone, !phone.isEmpty {
                                            Text(phone).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                } else {
                                    // The backend needs an anchor: a lead /
                                    // contact / account / deal, OR a filled
                                    // Dealer / People Directory lookup custom
                                    // field (steel-dealer flow). Reflect which
                                    // options this tenant actually has.
                                    Text(customFields.defs.contains { $0.fieldType == "lookup" }
                                        ? "Select a lead (or pick from Directory below)"
                                        : "Select a lead (required)")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Section("Details") {
                    // Subject is no longer its own field — Type and Subject
                    // were near-duplicates, so the rep now picks only the Type
                    // above and the subject is derived from it on save (see
                    // effectiveSubject). A subject passed in by the caller (the
                    // call button / site-visit prefill) is still honoured.
                    TextField("Description", text: $desc, axis: .vertical).lineLimit(3...6)
                    // Editable time. Logging defaults to now (tap to back-date a
                    // call logged after the fact); scheduling defaults to the
                    // near future and is constrained to future times so the
                    // reminder can't be set in the past.
                    if scheduled {
                        DatePicker(
                            "Remind me at",
                            selection: $when,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    } else if editState != nil && editsExisting {
                        // Editing: the date appears only for an activity that already has `completed_at`, and
                        // an untouched date is never sent.
                        editDateRows
                    } else if logsCompletedActivity {
                        DatePicker(
                            followUpAt != nil ? "Activity date" : "When",
                            selection: $when,
                            in: ...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        if let err = activityDateError {
                            Text(err).font(.footnote).foregroundColor(.red)
                        }
                        followUpRows
                    } else {
                        DatePicker(
                            type == "task" ? "Due" : "When",
                            selection: $when,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
                linkedEntitySection
                if scheduled {
                    Section {
                        Label("You'll get a reminder around this time.", systemImage: "bell.badge")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                // Spark & Ray only: outcome, multi-assignee, product interested, form serial.
                sparkSections
                // Every other client, editing: one "Assigned to" picker for admins / managers.
                singleAssigneeSection
                // Admin-defined activity custom fields (Dealer lookup, Visit
                // kind, First visit, …). Renders through the same section the
                // lead form uses; it self-gates on loaded defs (renders
                // nothing until /crm/custom-fields resolves), so there's no
                // flash of fields the admin never configured.
                CustomFieldsSection(model: customFields)
                attachmentSection
            }
            .navigationTitle(scheduled ? "Schedule Activity" : "Log Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(scheduled ? "Schedule" : "Log") {
                        Task { await submit() }
                    }.disabled(saveDisabled)
                }
            }
            .confirmationDialog("Attach image", isPresented: $showSourceSheet, titleVisibility: .visible) {
                Button("Take photo") { showCameraSheet = true }
                Button("Choose from library") { showLibrarySheet = true }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showCameraSheet) {
                ImagePicker(image: $pickedImage, sourceType: .camera, cameraDevice: .rear)
            }
            .sheet(isPresented: $showLibrarySheet) {
                ImagePicker(image: $pickedImage, sourceType: .photoLibrary)
            }
            .sheet(isPresented: $showLeadPicker) {
                LeadSearchPickerSheet { lead in selectedLead = lead }
            }
            .sheet(isPresented: $showAssigneePicker) {
                SparkAssigneePickerSheet(
                    users: sparkUsers,
                    knownNames: sparkNames,
                    selectedIds: $sparkExtras.assigneeIds
                )
            }
            .sheet(isPresented: $showProductPicker) {
                SparkProductPickerSheet(products: sparkProducts, selectedIds: $sparkExtras.productIds)
            }
            .task { await customFields.load(entity: "activity") }
            .task { await typeStore.load() }
            .task {
                // Editing, not Spark, admin / manager: who can be picked as the assignee.
                guard editsExisting, !showsSparkExtras, RecordOwnerRules.currentUserCanChange else { return }
                assignableUsers = await CRMService.shared.listAssignableUsers()
            }
            .task {
                // Spark extras: seed once (edit prefill), then load the people + catalogue pickers.
                guard showsSparkExtras else { return }
                if !sparkSeeded {
                    sparkExtras = sparkInitial
                    sparkSeeded = true
                }
                sparkUsers = await CRMService.shared.listAssignableUsers()
                let catalogue = (try? await CRMService.shared.listProducts()) ?? []
                sparkProducts = catalogue.filter { $0.isActive != false }
            }
            .onChange(of: pickedImage) { _, newImage in
                guard let img = newImage else { return }
                Task { await upload(image: img) }
            }
        }
    }

    /// Editing: "Activity date & time" (only when the activity already has `completed_at`; never in the future).
    @ViewBuilder
    private var editDateRows: some View {
        if showsEditDate {
            DatePicker(
                "Activity date & time",
                selection: Binding(
                    get: { when },
                    set: { newValue in
                        when = newValue
                        editState?.wrappedValue.dateEdited = true
                    }
                ),
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            if let err = activityDateError {
                Text(err).font(.footnote).foregroundColor(.red)
            }
        } else if type == "task" {
            // A task has no completion time yet: its date is the Due date, editable as before (and sent as
            // `due_at` only when changed).
            DatePicker(
                "Due",
                selection: Binding(
                    get: { when },
                    set: { newValue in
                        when = newValue
                        editState?.wrappedValue.dateEdited = true
                    }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }

    /// Logging: the optional Scheduled (follow-up) date. Turning it on or off never touches the Activity date.
    @ViewBuilder
    private var followUpRows: some View {
        if followUpVisible, let binding = followUpAt {
            Toggle(
                "Schedule a follow-up",
                isOn: Binding(
                    get: { binding.wrappedValue != nil },
                    set: { on in binding.wrappedValue = on ? Self.defaultReminderTime() : nil }
                )
            )
            if let due = binding.wrappedValue {
                DatePicker(
                    "Scheduled for",
                    selection: Binding(
                        get: { binding.wrappedValue ?? due },
                        set: { binding.wrappedValue = $0 }
                    ),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                if let err = followUpError {
                    Text(err).font(.footnote).foregroundColor(.red)
                }
                Text("Saving creates two activities: this one as done, and a planned follow-up.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var linkTypeBinding: Binding<ActivityLinkType?> {
        Binding(
            get: { editState?.wrappedValue.link.type },
            set: { newValue in editState?.wrappedValue.link.select(newValue) }
        )
    }

    /// Editing: the "Linked entity" control — Lead / Contact / Deal / Account / None, then search and pick the
    /// record — pre-filled from the activity's current link.
    @ViewBuilder
    private var linkedEntitySection: some View {
        if editsExisting, let state = editState {
            Section("Linked entity") {
                Picker("Link to", selection: linkTypeBinding) {
                    Text("None").tag(Optional<ActivityLinkType>.none)
                    ForEach(ActivityLinkType.allCases) { t in
                        Text(t.title).tag(Optional(t))
                    }
                }
                .pickerStyle(.segmented)
                .task {
                    // The row did not carry the linked record's name: fetch it once.
                    let draft = state.wrappedValue.link
                    guard draft.needsNameLookup, let original = draft.original else { return }
                    if let name = await ActivityLinkLookup.name(for: original) {
                        state.wrappedValue.link.applyResolvedName(name)
                    }
                }
                if let chosen = state.wrappedValue.link.type {
                    Button {
                        showLinkPicker = true
                    } label: {
                        HStack {
                            Text(state.wrappedValue.link.displayName ?? "Select a \(chosen.rawValue)")
                                .foregroundColor(state.wrappedValue.link.displayName == nil ? .secondary : .primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .sheet(isPresented: $showLinkPicker) {
                        ActivityLinkPickerSheet(type: chosen) { id, name in
                            state.wrappedValue.link.pick(id: id, name: name)
                        }
                    }
                }
                if let err = linkError {
                    Text(err).font(.footnote).foregroundColor(.red)
                }
            }
        }
    }

    /// The photo attachment section (camera / library, thumbnail, upload failure + retry). Kept out of `body`
    /// so its modifier chain stays within the type-checker budget.
    @ViewBuilder
    private var attachmentSection: some View {
        Section("Attachment") {
            if let img = pickedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(10)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            pickedImage = nil
                            imageUrl = nil
                            uploadFailed = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                        .padding(8)
                    }
                    .overlay {
                        if uploading {
                            ZStack {
                                Color.black.opacity(0.35).cornerRadius(10)
                                ProgressView().tint(.white)
                            }
                        }
                    }
            } else {
                existingPhotoRow
                Button {
                    showSourceSheet = true
                } label: {
                    Label((existingImageUrl ?? "").isEmpty ? "Attach image" : "Replace image", systemImage: "photo.badge.plus")
                }
            }
            if uploadFailed, let img = pickedImage {
                Text("Couldn't upload the photo. Check your connection and retry, or remove it.")
                    .font(.footnote)
                    .foregroundColor(.red)
                Button("Retry upload") { Task { await upload(image: img) } }
            }
        }
    }

    /// The photo already on the activity being edited, as a thumbnail (private-bucket URLs are signed).
    @ViewBuilder
    private var existingPhotoRow: some View {
        if let url = existingImageUrl, !url.isEmpty {
            SignedAsyncImage(urlString: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(10)
                } else {
                    Label("Current photo", systemImage: "photo").foregroundColor(.secondary)
                }
            }
        }
    }

    private func upload(image: UIImage) async {
        uploading = true
        uploadFailed = false
        imageUrl = nil
        defer { uploading = false }
        // Live upload first -> the public URL goes on the activity as `image_url`. With no network the picture is
        // kept on the device and the offline queue re-uploads + swaps the URL when MutationSyncWorker drains. An
        // upload that fails while ONLINE is surfaced (and blocks Save until retried or removed) instead of saving
        // the activity without — or with a placeholder for — the photo the rep attached.
        let uploaded = await KinematicRepository.shared.uploadImage(image: image, type: "activity_form")
        switch ActivityPhotoRules.outcome(uploadedUrl: uploaded, online: AttendanceCache.shared.isOnline) {
        case .uploaded(let url):
            imageUrl = url
        case .keepOnDevice:
            if let data = image.jpegData(compressionQuality: 0.85) {
                imageUrl = OfflineImageCache.save(data, ext: "jpg")
            } else {
                uploadFailed = true
            }
        case .failed:
            uploadFailed = true
        }
    }
}

/// Searchable lead list for attaching a lead to a global activity. Shows each
/// lead's name + phone so the rep can pick the right one. Server-side search
/// via `?q=` (matches name and phone). Reused by the Activities list
/// "Search by lead" filter, so this is module-internal (not file-private).
struct LeadSearchPickerSheet: View {
    let onPick: (Lead) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var leads: [Lead] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List(leads) { lead in
                Button {
                    onPick(lead)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lead.displayName).foregroundColor(.primary)
                        if let phone = lead.phone, !phone.isEmpty {
                            Text(phone).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .overlay { if loading { ProgressView() } }
            .searchable(text: $search, prompt: "Search by name or phone")
            .onChange(of: search) { _ in Task { await load() } }
            .navigationTitle("Select lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        leads = (try? await CRMService.shared.listLeads(search: search.isEmpty ? nil : search, limit: 50)) ?? []
    }
}
