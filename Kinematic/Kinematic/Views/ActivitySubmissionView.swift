import SwiftUI
import UIKit
import CoreLocation
import PhotosUI

struct ActivitySubmissionView: View {
    let activity: RouteActivity
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: KiniAppState
    @State private var template: FormTemplate? = nil
    @State private var responses: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var isLoading = true
    @State private var cachedImages: [String: [UIImage]] = [:]
    // How many times this activity has been submitted in the current visit.
    // Users can submit the same activity multiple times per outlet (e.g. one
    // submission per shelf for a planogram audit); we surface the count in
    // the submit button so they know their last save landed.
    @State private var submissionsThisVisit: Int = 0
    @State private var lastSubmitFlashed: Bool = false
    // What stops the form from being sent (unmet required fields, a bad phone / e-mail / number), shown inline above
    // the submit button. See FormFieldLogic.banner.
    @State private var formBanner: FormFieldLogic.Banner? = nil
    // Feature 3: drives the blocking "turn on location to submit" gate. Local
    // to this view because the form is presented inside a fullScreenCover, so
    // the root-level attendance gate would not surface above it.
    @State private var locationGate: LocationGatePrompt? = nil
    // Check-in / check-out on every form (attendance rule `form_checkin_required`). With the rule off none of this
    // shows and the form is exactly what it always was. See FormVisit.
    @StateObject private var visit: FormVisitTracker
    @ObservedObject private var attendanceRules = AttendanceRulesStore.shared
    @State private var visitNotice: String? = nil

    init(activity: RouteActivity) {
        self.activity = activity
        let outlet = KiniAppState.shared.selectedOutlet
        _visit = StateObject(wrappedValue: FormVisitTracker(
            key: activity.id ?? "",
            outletId: outlet?.rawId,
            name: outlet?.storeName ?? activity.name
        ))
    }

    /// The rule is on for this client: the form is filled between a "Start visit" and the submit.
    private var visitMode: Bool { attendanceRules.rules.formCheckinRequired }

    /// The rule is on and this form's visit has not been started: the questions are hidden.
    private var locked: Bool { visitMode && visit.session == nil }

    /// A photo / signature / file question counts as answered while it holds a picture the form has not sent yet.
    private func hasAsset(_ fieldId: String) -> Bool {
        cachedImages[fieldId]?.isEmpty == false
    }

    private var progress: Double {
        guard let fields = template?.fields else { return 0 }
        return FormFieldLogic.completion(fields: fields, responses: responses, hasAsset: { id in hasAsset(id) })
    }

    var body: some View {
        // Clean Apple-HIG full-screen page: NavigationStack hosts the
        // scrolling form; the system grouped background is applied via
        // .background() rather than stacked in a ZStack (which had been
        // causing layout offset). Submit bar is .safeAreaInset(.bottom)
        // so it floats above the keyboard and respects the home
        // indicator automatically.
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(.red).scaleEffect(1.2)
                        Text("Loading form…").font(.footnote).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let t = template {
                    formScroll(template: t)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(activity.name ?? "Audit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.selectedActivity = nil
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if template != nil && !isLoading {
                    submitBar
                }
            }
            .task { await loadTemplate() }
            // The attendance rules decide whether this form needs a visit; ask (throttled) in case Home has not yet.
            .task { await attendanceRules.refresh() }
            .locationGateAlert($locationGate)
            .alert("Form submitted", isPresented: Binding<Bool>(
                get: { visit.summary != nil },
                set: { shown in if !shown { visit.dismissSummary() } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(visit.summary.map { FormVisit.summaryMessage($0) } ?? "")
            }
        }
    }

    @ViewBuilder
    private func formScroll(template t: FormTemplate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.name)
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let desc = t.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if visitMode, let started = visit.session {
                    // The running time of the open visit.
                    VisitTimerChip(checkInAt: started.checkInAt)
                }

                if locked {
                    // Nothing to fill until the visit is started: nothing hidden behind a dimmed form either.
                    FormVisitLockedView()
                } else {
                    completionBar
                    if let fields = t.fields {
                        fieldList(fields)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }

    private var completionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Completion")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(.red)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.15)).frame(height: 5)
                    Capsule().fill(Color.red)
                        .frame(width: geo.size.width * CGFloat(progress), height: 5)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 5)
        }
    }

    @ViewBuilder
    private func fieldList(_ fields: [FormField]) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(fields) { field in
                if shouldShow(field: field) {
                    if FormFieldLogic.kindOf(field) == .section {
                        SectionHeaderRow(label: field.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } else {
                        FieldCard(
                            field: field,
                            value: Binding(
                                get: { responses[field.id] ?? "" },
                                set: { responses[field.id] = $0 }
                            ),
                            images: Binding(
                                get: { cachedImages[field.id] ?? [] },
                                set: { cachedImages[field.id] = $0 }
                            )
                        )
                    }
                }
            }
        }
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider()
            if submissionsThisVisit > 0 {
                // Subtle running tally so users know previous submissions
                // landed and the form is ready for the next entry.
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(submissionsThisVisit) submission\(submissionsThisVisit == 1 ? "" : "s") for this activity")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Done") {
                        appState.selectedActivity = nil
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            if let banner = formBanner, !locked {
                // Surface what stops the form from being sent inline so the
                // user knows exactly what to fix before the next attempt.
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(banner.title)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.red)
                        Text(banner.detail)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            if let notice = visitNotice, locked {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            Button(action: { submit() }) {
                HStack(spacing: 8) {
                    if isSubmitting || visit.starting {
                        ProgressView().tint(.white).scaleEffect(0.85)
                    } else if lastSubmitFlashed {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(submitLabel)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(submitColor)
                )
                .padding(.horizontal, 20)
            }
            .disabled(isSubmitting || visit.starting)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var submitColor: Color {
        if isSubmitting || visit.starting { return locked ? Color.green.opacity(0.7) : Color.red.opacity(0.7) }
        return locked ? Color.green : Color.red
    }

    private var submitLabel: String {
        if isSubmitting { return "Submitting…" }
        if visit.starting { return "Getting your location…" }
        if locked { return "Start visit (Check-in)" }
        if lastSubmitFlashed { return "Saved — submit another?" }
        if submissionsThisVisit > 0 { return "Submit Another" }
        return "Submit Audit"
    }

    private func shouldShow(field: FormField) -> Bool {
        FormFieldLogic.isVisible(field, responses: responses)
    }

    private func loadTemplate() async {
        let t = await KinematicRepository.shared.getFormTemplates(activityId: activity.id ?? "")
        await MainActor.run {
            self.template = t
            self.isLoading = false
            if let fields = t?.fields {
                for f in fields { responses[f.id] = "" }
            }
        }
    }

    /// Start this form's visit: the time and the position, nothing else.
    private func startVisit() async {
        visitNotice = nil
        let result: FormVisitTracker.StartResult = await visit.start()
        switch result {
        case .started:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .blocked(let prompt):
            locationGate = prompt
        case .noFix:
            visitNotice = "Couldn't get your location. Check that location is on and try again."
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func submit() {
        // The visit comes first when the client's rule asks for one: this tap starts it (no API call).
        if locked {
            Task { await startVisit() }
            return
        }

        // Block submission until every required field has a value (or
        // for asset-type fields, at least one attachment) and what was typed
        // is usable (a 10-digit phone, an e-mail, a number). Only questions
        // that are on screen count. The submit button previously bypassed
        // this entirely — empty submissions were landing in form_submissions.
        let fields: [FormField] = template?.fields ?? []
        if let banner = FormFieldLogic.banner(fields: fields, responses: responses, hasAsset: { id in hasAsset(id) }) {
            formBanner = banner
            // Warning haptic when validation fails so the rep feels the
            // block, not just sees the banner.
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        formBanner = nil

        // Feature 3 gate: the submission is geo-stamped, so refuse to send a
        // location-less row when location is off. Block, prompt, and report.
        if let prompt = LocationGate.promptIfBlocked(verb: "submit") {
            locationGate = prompt
            return
        }

        isSubmitting = true
        Task {
            var finalResponses: [String: FormResponse] = [:]
            await withTaskGroup(of: (String, FormResponse).self) { group in
                for (id, val) in responses {
                    let field = template?.fields?.first(where: { $0.id == id })
                    let images = cachedImages[id] ?? []
                    group.addTask {
                        var photoValue: String? = nil
                        if !images.isEmpty && (field?.fieldType == "image" || field?.fieldType == "photo") {
                            var uploadedUrls: [String] = []
                            for img in images {
                                if let url = await KinematicRepository.shared.uploadImage(image: img, type: "activity_form") {
                                    uploadedUrls.append(url)
                                } else if let data = img.jpegData(compressionQuality: 0.7) {
                                    // OFFLINE / upload failed — cache the photo and use a
                                    // `kinematic-offline://image-…` placeholder. The
                                    // OfflineMutationQueue uploads it and rewrites the URL
                                    // when the queued submission replays, so photos aren't
                                    // lost when the rep captures with no signal.
                                    uploadedUrls.append(OfflineImageCache.save(data))
                                }
                            }
                            photoValue = uploadedUrls.joined(separator: ",")
                        }
                        return (id, FormResponse(fieldId: id, value: val, photo: photoValue, gps: nil))
                    }
                }
                for await (id, response) in group { finalResponses[id] = response }
            }

            let processedResponses = responses.map { (id, _) in
                finalResponses[id] ?? FormResponse(fieldId: id, value: responses[id], photo: nil, gps: nil)
            }

            let lat: Double? = LocationTrackingService.shared.lastLocation?.coordinate.latitude
            let lng: Double? = LocationTrackingService.shared.lastLocation?.coordinate.longitude
            // With the rule on, the submit IS the check-out: stamp this form's visit (nothing is stamped otherwise).
            let stamp: FormVisit.Stamp = visit.stamp(lat: lat, lng: lng)

            let request = FormSubmissionRequest(
                templateId: template?.id,
                activityId: activity.id,
                outletId: KiniAppState.shared.selectedOutlet?.rawId,
                outletName: KiniAppState.shared.selectedOutlet?.storeName,
                latitude: lat,
                longitude: lng,
                submittedAt: ISO8601DateFormatter().string(from: Date()),
                isConverted: false,
                responses: processedResponses,
                checkInAt: stamp.checkInAt,
                checkOutAt: stamp.checkOutAt,
                checkInGps: stamp.checkInGps,
                checkOutGps: stamp.checkOutGps
            )

            let pendingBefore: Int = OfflineMutationQueue.shared.pendingCount
            let outcome = await KinematicRepository.shared.submitForm(request: request)
            let pendingAfter: Int = OfflineMutationQueue.shared.pendingCount
            await MainActor.run {
                isSubmitting = false
                // Server backstop: strict tenants reject a location-less
                // submission — show the same "turn on location" gate + report.
                if outcome == .locationRequired {
                    locationGate = LocationGatePrompt(verb: "submit")
                    LocationTrackingService.shared.reportLocationStatus()
                    return
                }
                if outcome == .success {
                    // The visit this form closed is over; remember how long it took for the success state.
                    visit.saved(with: stamp)
                    // A form that reached the server (not one only saved for later) is a good moment for the
                    // rate-the-app prompt (counted only for clients that opted in).
                    if RatePrompt.formReachedServer(pendingBefore: pendingBefore, pendingAfter: pendingAfter) {
                        RatePromptCoordinator.shared.notePositiveMoment()
                    }
                    // Field reps can submit the same activity multiple times
                    // per visit (e.g. one entry per shelf / aisle). After a
                    // successful save we:
                    //   1. mark the activity completed in app state so the
                    //      timeline reflects at least one submission landed,
                    //   2. reset all field values + cached images so the
                    //      form is a blank slate for the next entry,
                    //   3. flash a success state on the submit button for
                    //      ~1.5s so the user knows it landed,
                    //   4. leave the form open. The "Done" button + the
                    //      running tally above the submit button let the
                    //      user close the form when they're finished.
                    if let index = KiniAppState.shared.selectedOutlet?.activities?.firstIndex(where: { $0.id == activity.id }) {
                        KiniAppState.shared.selectedOutlet?.activities?[index].status = "completed"
                    }
                    submissionsThisVisit += 1
                    resetForm()
                    // Success haptic — sharp single tap so the rep gets
                    // tactile confirmation that the submission landed
                    // without needing to check the screen.
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeInOut(duration: 0.2)) { lastSubmitFlashed = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) { lastSubmitFlashed = false }
                    }
                }
            }
        }
    }

    private func resetForm() {
        guard let fields = template?.fields else { return }
        for field in fields {
            responses[field.id] = ""
            cachedImages[field.id] = []
        }
    }
}

// MARK: - Section Header

struct SectionHeaderRow: View {
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
                .cornerRadius(1)
        }
    }
}

// MARK: - Field Card

struct FieldCard: View {
    let field: FormField
    @Binding var value: String
    @Binding var images: [UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(field.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if field.isRequired {
                    Text("Required")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(4)
                }
                Spacer(minLength: 0)
            }

            if let help = field.helpText, !help.isEmpty {
                Text(help)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            fieldControl
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    /// The control for the question — chosen by `FormFieldLogic.kindOf`, the same rule the submit validation uses.
    @ViewBuilder
    private var fieldControl: some View {
        switch FormFieldLogic.kindOf(field) {
        case .dropdown:
            DropdownField(field: field, value: $value)
        case .radio:
            ChoiceListField(field: field, value: $value, multiSelect: false)
        case .multiSelect:
            // A builder checkbox WITH options ("Multi Select"): one box per option, the answer is the chosen option
            // values joined with commas.
            ChoiceListField(field: field, value: $value, multiSelect: true)
        case .checkbox:
            if field.fieldType.lowercased() == "consent" {
                ConsentToggleField(value: $value)
            } else {
                SingleCheckboxField(value: $value)
            }
        case .yesNo:
            YesNoField(value: $value)
        case .rating:
            // As many stars as the builder asked for (validation.max, 5 when it says nothing).
            RatingField(value: $value, maxStars: FormFieldLogic.ratingMax(field.validationMax))
        case .photo:
            PhotoCaptureField(images: $images, maxCount: field.imageCount ?? 5)
        case .file:
            FileAttachmentField(value: $value)
        case .signature:
            SignatureCaptureField(value: $value)
        case .longText:
            LongTextField(value: $value, placeholder: field.placeholder)
        case .location:
            LocationFetchField(value: $value)
        case .number:
            // A number question takes numbers only (checked again on submit, see FormFieldLogic.firstProblem).
            StyledTextField(value: $value, placeholder: field.placeholder ?? "0", keyboardType: .decimalPad)
        case .phone:
            StyledTextField(value: $value, placeholder: field.placeholder ?? "10-digit mobile number", keyboardType: .phonePad, maxDigits: 10)
        case .email:
            StyledTextField(value: $value, placeholder: field.placeholder ?? "Email address", keyboardType: .emailAddress)
        case .date:
            FormMomentField(mode: .date, value: $value, placeholder: "Select date")
        case .time:
            FormMomentField(mode: .time, value: $value, placeholder: "Select time")
        case .dateTime:
            FormMomentField(mode: .dateTime, value: $value, placeholder: "Select date and time")
        case .text, .section, .other:
            StyledTextField(value: $value, placeholder: field.placeholder ?? "Enter response", keyboardType: textKeyboard)
        }
    }

    /// A text box takes the keyboard the builder asked for (`keyboard_type`), as the other platforms do.
    private var textKeyboard: UIKeyboardType {
        switch (field.keyboardType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "phone":  return .phonePad
        case "number": return .decimalPad
        case "email":  return .emailAddress
        default:       return .default
        }
    }
}

// MARK: - Field Controls

struct StyledTextField: View {
    @Binding var value: String
    var placeholder: String = "Enter response"
    var keyboardType: UIKeyboardType = .default
    // When set (phone fields), keep digits only and cap the count so an 11th
    // digit can never be entered — matches the lead/user 10-digit mobile rule.
    var maxDigits: Int? = nil

    private var boundValue: Binding<String> {
        guard let maxDigits else { return $value }
        return Binding(
            get: { value },
            set: { newVal in value = String(newVal.filter { $0.isNumber }.prefix(maxDigits)) }
        )
    }

    var body: some View {
        TextField(placeholder, text: boundValue)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .sentences)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
    }
}

struct LongTextField: View {
    @Binding var value: String
    var placeholder: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if value.isEmpty, let ph = placeholder {
                Text(ph)
                    .foregroundColor(Color(uiColor: .placeholderText))
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $value)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
        }
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

struct DropdownField: View {
    let field: FormField
    @Binding var value: String

    /// The chosen option's label (what is stored is still the option's value); the placeholder while nothing is chosen.
    private var selectedLabel: String {
        if value.isEmpty { return field.placeholder ?? "Choose an option" }
        return FormFieldLogic.optionLabel(field.options, value: value)
    }

    var body: some View {
        Menu {
            ForEach(field.options ?? [], id: \.value) { opt in
                Button(opt.label) { value = opt.value }
            }
        } label: {
            HStack {
                Text(selectedLabel)
                    .foregroundColor(value.isEmpty ? .secondary : .primary)
                    .font(.body)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
        }
    }
}

struct ChoiceListField: View {
    let field: FormField
    @Binding var value: String
    let multiSelect: Bool

    private func isSelected(_ opt: FormOption) -> Bool {
        multiSelect
            ? FormFieldLogic.selectedValues(value).contains(opt.value)
            : value == opt.value
    }

    private func toggle(_ opt: FormOption) {
        if multiSelect {
            value = FormFieldLogic.toggleSelected(value, optionValue: opt.value, checked: !isSelected(opt))
        } else {
            value = opt.value
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array((field.options ?? []).enumerated()), id: \.element.value) { index, opt in
                Button(action: { toggle(opt) }) {
                    HStack(spacing: 12) {
                        Image(systemName: multiSelect
                            ? (isSelected(opt) ? "checkmark.square.fill" : "square")
                            : (isSelected(opt) ? "circle.inset.filled" : "circle"))
                            .foregroundColor(isSelected(opt) ? .red : .secondary)
                            .font(.system(size: 18))
                        Text(opt.label)
                            .foregroundColor(.primary)
                            .font(.body)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(isSelected(opt) ? Color.red.opacity(0.06) : Color(uiColor: .tertiarySystemGroupedBackground))
                }
                if index < (field.options?.count ?? 0) - 1 {
                    Divider().padding(.leading, 46)
                }
            }
        }
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.15), lineWidth: 1))
    }
}

struct YesNoField: View {
    @Binding var value: String
    var body: some View {
        HStack(spacing: 12) {
            YesNoButton(label: "Yes", isSelected: value == "yes") { value = "yes" }
            YesNoButton(label: "No", isSelected: value == "no") { value = "no" }
        }
    }
}

struct YesNoButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected
                    ? (label == "Yes" ? "checkmark.circle.fill" : "xmark.circle.fill")
                    : "circle")
                    .font(.system(size: 15))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(isSelected ? Color.red : Color(uiColor: .tertiarySystemGroupedBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

struct RatingField: View {
    @Binding var value: String
    /// How many stars (the question's `validation.max`, 5 when it says nothing; always 1...10).
    var maxStars: Int = 5

    var body: some View {
        HStack(spacing: maxStars > 5 ? 8 : 16) {
            ForEach(1...max(1, maxStars), id: \.self) { star in
                let filled = star <= (Int(value) ?? 0)
                Image(systemName: filled ? "star.fill" : "star")
                    .font(maxStars > 5 ? .title3 : .title2)
                    .foregroundColor(filled ? .orange : Color.gray.opacity(0.3))
                    .onTapGesture { value = "\(star)" }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct PhotoCaptureField: View {
    @Binding var images: [UIImage]
    let maxCount: Int
    @State private var showCamera = false
    @State private var showGallery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if images.count < maxCount {
                HStack(spacing: 10) {
                    Button(action: { showCamera = true }) {
                        Label("Camera", systemImage: "camera.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(10)
                    }
                    Button(action: { showGallery = true }) {
                        Label("Gallery", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(10)
                    }
                    Spacer()
                    Text("\(images.count)/\(maxCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<images.count, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: images[index])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(10)
                                    .clipped()
                                Button(action: { images.remove(at: index) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.3), radius: 2)
                                        .padding(4)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(
                image: Binding(get: { nil }, set: { if let img = $0 { images.append(img) } }),
                sourceType: .camera
            )
        }
        .sheet(isPresented: $showGallery) {
            PHPickerRepresentable(images: $images, maxCount: maxCount - images.count)
        }
    }
}

struct FileAttachmentField: View {
    @Binding var value: String
    @State private var showPicker = false

    private var hasFile: Bool { !value.isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            Button(action: { showPicker = true }) {
                HStack(spacing: 12) {
                    Image(systemName: hasFile ? "doc.fill" : "paperclip.circle.fill")
                        .font(.title3)
                        .foregroundColor(hasFile ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasFile ? value : "Choose a file")
                            .font(.subheadline)
                            .foregroundColor(hasFile ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(hasFile ? "Tap to replace" : "PDF, images, or documents")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    if hasFile {
                        Button(action: { value = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                value = url.lastPathComponent
            }
        }
    }
}

struct ConsentToggleField: View {
    @Binding var value: String

    private var isConsented: Bool {
        value == "true" || value == "yes" || value == "1"
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isConsented },
            set: { value = $0 ? "true" : "false" }
        )) {
            HStack(spacing: 8) {
                Image(systemName: isConsented ? "checkmark.seal.fill" : "seal")
                    .foregroundColor(isConsented ? .green : .secondary)
                Text(isConsented ? "Agreed" : "Tap to agree")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isConsented ? .primary : .secondary)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .green))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isConsented ? Color.green.opacity(0.07) : Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(10)
        .animation(.easeInOut(duration: 0.2), value: isConsented)
    }
}

/// The location question: a read-only `lat,lng` filled by tapping to capture the rep's position. A fresh fix is used
/// (the live-tracking one when it is recent); with location off the usual "turn on location" prompt names the problem,
/// and a position that cannot be had is said so — never a silent no-op, never an invented value.
struct LocationFetchField: View {
    @Binding var value: String
    @State private var isFetching = false
    @State private var gate: LocationGatePrompt? = nil
    @State private var failed = false

    var body: some View {
        Button(action: { Task { await capture() } }) {
            HStack(spacing: 12) {
                Image(systemName: "location.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.isEmpty ? "Tap to capture location" : FormFieldLogic.locationDisplay(value))
                        .font(.subheadline)
                        .foregroundColor(value.isEmpty ? .secondary : .primary)
                    if failed {
                        Text("Couldn't get your location. Check that location is on and try again.")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if !value.isEmpty {
                        Text("GPS coordinates captured · tap to capture again")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                Spacer()
                if isFetching {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: value.isEmpty ? "location" : "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(value.isEmpty ? .secondary : .green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
        }
        .disabled(isFetching)
        .locationGateAlert($gate)
    }

    private func capture() async {
        failed = false
        // Same honesty gate as every geo-stamped action: location off -> the "turn it on" prompt.
        if let prompt = LocationGate.promptIfBlocked(verb: "add your location") {
            gate = prompt
            return
        }
        isFetching = true
        let fix = await FormLocationFix.current()
        isFetching = false
        if let f = fix, let text = FormFieldLogic.formatLatLng(lat: f.lat, lng: f.lng) {
            value = text
        } else {
            failed = true
        }
    }
}

// (The date question is `FormMomentField` — see FormFieldControls.swift.)

// MARK: - PHPicker gallery wrapper

struct PHPickerRepresentable: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    let maxCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = max(1, maxCount)
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerRepresentable
        init(_ parent: PHPickerRepresentable) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            for result in results {
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        DispatchQueue.main.async { self.parent.images.append(image) }
                    }
                }
            }
        }
    }
}

// MARK: - Signature

struct SignatureCaptureField: View {
    @Binding var value: String
    @State private var lines: [SignatureLine] = []
    @State private var currentLine = SignatureLine(points: [])

    private var hasSignature: Bool { !value.isEmpty || !lines.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                Color(uiColor: .tertiarySystemGroupedBackground)
                Canvas { ctx, _ in
                    for line in lines {
                        var path = Path()
                        guard let first = line.points.first else { continue }
                        path.move(to: first)
                        for point in line.points.dropFirst() { path.addLine(to: point) }
                        ctx.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if !currentLine.points.isEmpty {
                        var path = Path()
                        path.move(to: currentLine.points[0])
                        for point in currentLine.points.dropFirst() { path.addLine(to: point) }
                        ctx.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
                if !hasSignature {
                    Text("Sign here")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 160)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        currentLine.points.append(gesture.location)
                        if value.isEmpty { value = "drawn" }
                    }
                    .onEnded { _ in
                        if !currentLine.points.isEmpty {
                            lines.append(currentLine)
                            currentLine = SignatureLine(points: [])
                        }
                    }
            )

            if hasSignature {
                Button(action: clear) {
                    Label("Clear signature", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func clear() {
        lines.removeAll()
        currentLine = SignatureLine(points: [])
        value = ""
    }
}

struct SignatureLine {
    var points: [CGPoint]
}

// MARK: - Backward-compat aliases
typealias DynamicFieldRow = FieldCard
typealias YesNoButtonRedesign = YesNoButton
typealias RatingStarsRedesign = RatingField
typealias MultiPhotoPickerRedesign = PhotoCaptureField
typealias LocationFetcherRedesign = LocationFetchField

struct Line { var points: [CGPoint] }

struct SuccessOverlay: View {
    let message: String
    let action: () -> Void
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 25) {
                Spacer()
                ZStack {
                    Circle().fill(Color.green.opacity(0.1)).frame(width: 120, height: 120)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 80)).foregroundColor(.green)
                }
                VStack(spacing: 12) {
                    Text("Thank You!").font(.title2).fontWeight(.black).foregroundColor(Color(uiColor: .label))
                    Text(message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 60)

                Button(action: action) {
                    Text("CONTINUE")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.green)
                        .cornerRadius(18)
                }
                .padding(.horizontal, 60)
                .padding(.top, 20)
                Spacer()
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .opacity))
    }
}
