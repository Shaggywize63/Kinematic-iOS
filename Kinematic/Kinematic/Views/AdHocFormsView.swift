import SwiftUI
import UIKit
import CoreLocation

/// Ad-hoc form flow for route-less field-force tenants (ByteBack), reached from
/// the ➕ tab.
///
///  - `AdHocFormsView` lists every published form template for the org (no
///    activity / outlet filter) and lets the rep pick one.
///  - `AdHocFormFillView` renders that template, captures a GPS fix, and submits
///    it with NO outlet / activity binding.
///
/// Reuses the existing `FieldCard` / `SectionHeaderRow` renderers and the
/// `KinematicRepository.submitForm(request:)` path (the same one the outlet-bound
/// `ActivitySubmissionView` uses) — only the outlet/activity fields are nil. It
/// deliberately does NOT use the outlet-visit / StoreVisitView lifecycle, since
/// an ad-hoc submission has no outlet to check into.
struct AdHocFormsView: View {
    @State private var templates: [FormTemplate] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(.red).scaleEffect(1.2)
                        Text("Loading forms…").font(.footnote).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if templates.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 52))
                            .foregroundColor(.secondary)
                        Text("No forms available")
                            .font(.title3.bold())
                        Text("Your administrator hasn't published any forms yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(templates, id: \.id) { t in
                                NavigationLink(destination: AdHocFormFillView(template: t)) {
                                    templateRow(t)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("New Form")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func templateRow(_ t: FormTemplate) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 46, height: 46)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(t.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                if let desc = t.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func load() async {
        let list = await KinematicRepository.shared.getAllFormTemplates()
        await MainActor.run {
            self.templates = list
            self.isLoading = false
        }
    }
}

/// Fills and submits a single ad-hoc form (no outlet / activity binding).
///
/// For a client whose attendance rule says `form_checkin_required`, the form is locked behind "Start visit (Check-in)"
/// (time + GPS, no API call, no photo) and the submit is the check-out; that visit is stored under
/// `FormVisit.adHocKey(templateId)` so it never mixes with a route-plan visit. With the rule off none of that exists.
struct AdHocFormFillView: View {
    let template: FormTemplate
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: KiniAppState

    @State private var responses: [String: String] = [:]
    @State private var cachedImages: [String: [UIImage]] = [:]
    @State private var isSubmitting = false
    // What stops the form from being sent (unmet required fields, a bad phone / e-mail / number); see FormFieldLogic.banner.
    @State private var formBanner: FormFieldLogic.Banner? = nil
    @State private var locationGate: LocationGatePrompt? = nil
    @State private var didSubmit = false
    // Check-in / check-out on every form (attendance rule `form_checkin_required`); see FormVisit.
    @StateObject private var visit: FormVisitTracker
    @ObservedObject private var attendanceRules = AttendanceRulesStore.shared
    @State private var visitNotice: String? = nil

    init(template: FormTemplate) {
        self.template = template
        _visit = StateObject(wrappedValue: FormVisitTracker(
            key: FormVisit.adHocKey(template.id),
            outletId: nil,
            name: template.name
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

    var body: some View {
        Group {
            if didSubmit {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.green)
                    Text("Form submitted")
                        .font(.title2.bold())
                    Text("Thanks — your response was recorded.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let summary = visit.summary {
                        // The visit this form closed: how long it took, and when it started and ended.
                        FormVisitSummaryView(summary: summary)
                            .padding(.top, 4)
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                formScroll
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !didSubmit { submitBar }
        }
        .onAppear {
            if let fields = template.fields {
                for f in fields where responses[f.id] == nil { responses[f.id] = "" }
            }
            visit.reload()
        }
        // The attendance rules decide whether this form needs a visit; ask (throttled) in case Home has not yet.
        .task { await attendanceRules.refresh() }
        .locationGateAlert($locationGate)
    }

    private var formScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let desc = template.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if visitMode, let started = visit.session {
                    // The running time of the open visit.
                    VisitTimerChip(checkInAt: started.checkInAt)
                }
                if locked {
                    // Nothing to fill until the visit is started: nothing hidden behind a dimmed form either.
                    FormVisitLockedView()
                } else if let fields = template.fields {
                    fieldList(fields)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
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
                            ),
                            allFields: fields,
                            setResponse: { id, val in responses[id] = val }
                        )
                    }
                }
            }
        }
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider()
            if let banner = formBanner, !locked {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(banner.title)
                            .font(.caption.weight(.bold)).foregroundColor(.red)
                        Text(banner.detail)
                            .font(.caption2).foregroundColor(.secondary).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.top, 8)
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
                    if isSubmitting || visit.starting { ProgressView().tint(.white).scaleEffect(0.85) }
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
        return "Submit Form"
    }

    private func shouldShow(field: FormField) -> Bool {
        FormFieldLogic.isVisible(field, responses: responses)
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

        // Required answers, a 10-digit phone, an e-mail, a number: only the questions on screen count.
        let fields: [FormField] = template.fields ?? []
        if let banner = FormFieldLogic.banner(fields: fields, responses: responses, hasAsset: { id in hasAsset(id) }) {
            formBanner = banner
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        formBanner = nil

        // Geo-stamped submission: refuse to send a location-less row when
        // location is off. Block, prompt, and report (parity with the outlet form).
        if let prompt = LocationGate.promptIfBlocked(verb: "submit") {
            locationGate = prompt
            return
        }

        isSubmitting = true
        Task {
            var finalResponses: [String: FormResponse] = [:]
            await withTaskGroup(of: (String, FormResponse).self) { group in
                for (id, val) in responses {
                    let field = template.fields?.first(where: { $0.id == id })
                    let images = cachedImages[id] ?? []
                    group.addTask {
                        var photoValue: String? = nil
                        if !images.isEmpty && (field?.fieldType == "image" || field?.fieldType == "photo") {
                            var uploadedUrls: [String] = []
                            for img in images {
                                if let url = await KinematicRepository.shared.uploadImage(image: img, type: "activity_form") {
                                    uploadedUrls.append(url)
                                } else if let data = img.jpegData(compressionQuality: 0.7) {
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
            // With the rule on, the submit IS the check-out: stamp this form's own visit (nothing is stamped otherwise).
            let stamp: FormVisit.Stamp = visit.stamp(lat: lat, lng: lng)

            let request = FormSubmissionRequest(
                templateId: template.id,
                activityId: nil,
                outletId: nil,
                outletName: nil,
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
                if outcome == .locationRequired {
                    locationGate = LocationGatePrompt(verb: "submit")
                    LocationTrackingService.shared.reportLocationStatus()
                    return
                }
                if outcome == .success {
                    // The visit this form closed is over; keep how long it took for the success state.
                    visit.saved(with: stamp)
                    // A form that reached the server (not one only saved for later) is a good moment for the
                    // rate-the-app prompt (counted only for clients that opted in).
                    if RatePrompt.formReachedServer(pendingBefore: pendingBefore, pendingAfter: pendingAfter) {
                        RatePromptCoordinator.shared.notePositiveMoment()
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation { didSubmit = true }
                    // Without a visit summary to read, pop back to the picker after a brief confirmation; with one the
                    // rep reads it and taps Done.
                    if visit.summary == nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
                    }
                }
            }
        }
    }
}
