import SwiftUI
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
struct AdHocFormFillView: View {
    let template: FormTemplate
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: KiniAppState

    @State private var responses: [String: String] = [:]
    @State private var cachedImages: [String: [UIImage]] = [:]
    @State private var isSubmitting = false
    @State private var missingRequiredLabels: [String] = []
    @State private var locationGate: LocationGatePrompt? = nil
    @State private var didSubmit = false

    private var unmetRequiredFields: [FormField] {
        guard let fields = template.fields else { return [] }
        return fields.filter { field in
            guard field.isRequired, field.fieldType != "section_header" else { return false }
            let val = (responses[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasImages = cachedImages[field.id]?.isEmpty == false
            let assetTypes: Set<String> = ["image", "photo", "camera", "signature", "file"]
            if assetTypes.contains(field.fieldType.lowercased()) {
                return val.isEmpty && !hasImages
            }
            return val.isEmpty
        }
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
        }
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
                if let fields = template.fields {
                    LazyVStack(spacing: 16) {
                        ForEach(fields) { field in
                            if shouldShow(field: field) {
                                if field.fieldType == "section_header" {
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider()
            if !missingRequiredLabels.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fill these required field\(missingRequiredLabels.count == 1 ? "" : "s") first")
                            .font(.caption.weight(.bold)).foregroundColor(.red)
                        Text(missingRequiredLabels.joined(separator: " • "))
                            .font(.caption2).foregroundColor(.secondary).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
            Button(action: { submit() }) {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().tint(.white).scaleEffect(0.85) }
                    Text(isSubmitting ? "Submitting…" : "Submit Form")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSubmitting ? Color.red.opacity(0.7) : Color.red)
                )
                .padding(.horizontal, 20)
            }
            .disabled(isSubmitting)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func shouldShow(field: FormField) -> Bool {
        guard let depId = field.dependsOnId, !depId.isEmpty else { return true }
        return (responses[depId] ?? "") == field.dependsOnValue
    }

    private func submit() {
        let unmet = unmetRequiredFields
        if !unmet.isEmpty {
            missingRequiredLabels = unmet.map { $0.label }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        missingRequiredLabels = []

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

            let request = FormSubmissionRequest(
                templateId: template.id,
                activityId: nil,
                outletId: nil,
                outletName: nil,
                latitude: LocationTrackingService.shared.lastLocation?.coordinate.latitude,
                longitude: LocationTrackingService.shared.lastLocation?.coordinate.longitude,
                submittedAt: ISO8601DateFormatter().string(from: Date()),
                isConverted: false,
                responses: processedResponses
            )

            let outcome = await KinematicRepository.shared.submitForm(request: request)
            await MainActor.run {
                isSubmitting = false
                if outcome == .locationRequired {
                    locationGate = LocationGatePrompt(verb: "submit")
                    LocationTrackingService.shared.reportLocationStatus()
                    return
                }
                if outcome == .success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation { didSubmit = true }
                    // Pop back to the picker after a brief confirmation.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
                }
            }
        }
    }
}
