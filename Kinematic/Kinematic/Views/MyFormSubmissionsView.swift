//
//  MyFormSubmissionsView.swift
//  Kinematic
//
//  "My Reports" — a field executive's own filled-form entries. Reached from the ad-hoc form picker
//  (AdHocFormsView) toolbar. Lists every form the rep has submitted, each named by its backend reference (the
//  "form number", e.g. SRPR2627-1) plus the day; opening one shows the answers and photos, lets the rep edit
//  their own text / outlet, and exports a single report to the iOS share sheet.
//
//  All shapes + pure logic live in FormSubmissionModels.swift / FormSubmissionLogic.swift (unit-tested); this
//  file is only presentation + the repository calls. No built-in CRM fields here, so no field-override gate.
//

import SwiftUI
import UIKit

// MARK: - List

struct MyFormSubmissionsView: View {
    @State private var items: [FormSubmissionSummary] = []
    @State private var page: Int = 1
    @State private var isLoading = true
    @State private var isPaging = false
    @State private var canLoadMore = false
    @State private var loadFailed = false

    private let pageSize = 20

    var body: some View {
        Group {
            if isLoading {
                loadingState
            } else if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("My Reports")
        .navigationBarTitleDisplayMode(.inline)
        .task { if isLoading { await reload() } }
        .refreshable { await reload() }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.red).scaleEffect(1.2)
            Text("Loading your reports…").font(.footnote).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: loadFailed ? "wifi.exclamationmark" : "tray")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text(loadFailed ? "Couldn't load your reports" : "No reports yet")
                .font(.title3.bold())
            Text(loadFailed
                 ? "Check your connection and pull to refresh."
                 : "Forms you submit will show up here with their form number.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink(destination: FormSubmissionDetailView(id: item.id, listed: item)) {
                        SubmissionRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
                if canLoadMore {
                    ProgressView()
                        .tint(.red)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .task { await loadMore() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func reload() async {
        let result = await KinematicRepository.shared.getMyFormSubmissions(page: 1, limit: pageSize)
        await MainActor.run {
            isLoading = false
            if let result = result {
                loadFailed = false
                items = result.data
                page = 1
                canLoadMore = result.data.count >= pageSize
            } else {
                loadFailed = true
                if items.isEmpty { canLoadMore = false }
            }
        }
    }

    private func loadMore() async {
        if isPaging || !canLoadMore { return }
        isPaging = true
        let next = page + 1
        let result = await KinematicRepository.shared.getMyFormSubmissions(page: next, limit: pageSize)
        await MainActor.run {
            isPaging = false
            guard let result = result else { canLoadMore = false; return }
            // De-dup defensively in case the list shifted between pages.
            let known = Set(items.map { $0.id })
            items.append(contentsOf: result.data.filter { !known.contains($0.id) })
            page = next
            canLoadMore = result.data.count >= pageSize
        }
    }
}

private struct SubmissionRow: View {
    let item: FormSubmissionSummary

    var body: some View {
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
                Text(item.formTitle?.isEmpty == false ? item.formTitle! : "Form submission")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(FormRefDisplay.title(refNo: item.refNo, submittedAt: item.submittedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let outlet = item.outletName, !outlet.isEmpty {
                    Text(outlet)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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
}

// MARK: - Detail

struct FormSubmissionDetailView: View {
    let id: String
    /// The list row we came from — shown immediately while the full detail loads.
    let listed: FormSubmissionSummary?

    @State private var detail: FormSubmissionDetail?
    @State private var isLoading = true
    @State private var loadFailed = false

    // Edit
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var draftValues: [String: String] = [:]   // field_id -> text
    @State private var draftOutlet: String = ""
    @State private var saveError: String?

    // Export / share
    @State private var isExporting = false
    @State private var shareItems: [Any]?
    @State private var exportError: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(.red).scaleEffect(1.2)
                    Text("Loading…").font(.footnote).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = detail {
                content(detail)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44)).foregroundColor(.secondary)
                    Text("Couldn't load this report").font(.headline)
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.bordered).tint(.red)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(headlineTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if detail != nil { trailingMenu }
            }
        }
        .task { if isLoading { await load() } }
        .sheet(isPresented: shareBinding) {
            if let shareItems = shareItems { FormShareSheet(items: shareItems) }
        }
        .alert("Export failed", isPresented: exportErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "Please try again.") }
    }

    @ViewBuilder
    private var trailingMenu: some View {
        if isEditing {
            HStack(spacing: 16) {
                Button("Cancel") { cancelEdit() }.disabled(isSaving)
                Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
            }
        } else {
            Menu {
                Button {
                    beginEdit()
                } label: { Label("Edit report", systemImage: "pencil") }
                Button {
                    Task { await exportAndShare() }
                } label: { Label("Export / Share", systemImage: "square.and.arrow.up") }
            } label: {
                if isExporting { ProgressView().tint(.red) } else { Image(systemName: "ellipsis.circle") }
            }
            .disabled(isExporting)
        }
    }

    private func content(_ d: FormSubmissionDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(d)
                if let saveError = saveError, isEditing {
                    bannerRow(saveError)
                }
                outletCard(d)
                answersCard(d)
                submissionPhotosCard(d)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }

    private func header(_ d: FormSubmissionDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(d.formTitle?.isEmpty == false ? d.formTitle! : "Form submission")
                .font(.title3.bold())
            let ref = (d.refNo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !ref.isEmpty {
                Label("Form No: \(ref)", systemImage: "number")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            let day = FormRefDisplay.dayText(d.submittedAt)
            if !day.isEmpty {
                Label("Submitted \(day)", systemImage: "calendar")
                    .font(.subheadline).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    @ViewBuilder
    private func outletCard(_ d: FormSubmissionDetail) -> some View {
        if isEditing {
            VStack(alignment: .leading, spacing: 8) {
                Text("OUTLET").font(.caption).foregroundColor(.secondary)
                TextField("Outlet name", text: $draftOutlet)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
        } else if let outlet = d.outletName, !outlet.isEmpty {
            labelledCard(title: "OUTLET", value: outlet)
        }
    }

    @ViewBuilder
    private func answersCard(_ d: FormSubmissionDetail) -> some View {
        let answers = d.responses ?? []
        if answers.isEmpty {
            labelledCard(title: "ANSWERS", value: "No answers recorded.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("ANSWERS").font(.caption).foregroundColor(.secondary)
                ForEach(answers) { answer in
                    answerRow(answer)
                    if answer.identity != answers.last?.identity { Divider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
    }

    @ViewBuilder
    private func answerRow(_ answer: FormSubmissionAnswer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FormSubmissionLogic.label(for: answer))
                .font(.subheadline.weight(.semibold))
            let editable = isEditing && FormSubmissionLogic.isEditable(answer)
            if editable, let fid = answer.fieldId {
                TextField("Enter value", text: Binding(
                    get: { draftValues[fid] ?? FormSubmissionLogic.displayValue(answer) },
                    set: { draftValues[fid] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            } else {
                let value = FormSubmissionLogic.displayValue(answer)
                if !value.isEmpty {
                    Text(value).font(.body).foregroundColor(.primary)
                } else if (answer.photos?.isEmpty ?? true) {
                    Text("—").font(.body).foregroundColor(.secondary)
                }
            }
            photoStrip(answer.photos)
        }
    }

    @ViewBuilder
    private func submissionPhotosCard(_ d: FormSubmissionDetail) -> some View {
        // Submission-level photos that aren't already shown under an answer.
        let answerURLs = Set((d.responses ?? []).flatMap { ($0.photos ?? []).map { $0.url } })
        let extras = (d.photos ?? []).filter { !answerURLs.contains($0.url) }
        if !extras.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("PHOTOS").font(.caption).foregroundColor(.secondary)
                photoStrip(extras)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
    }

    @ViewBuilder
    private func photoStrip(_ photos: [SignedPhoto]?) -> some View {
        if let photos = photos, !photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in
                        AsyncImage(url: URL(string: photo.renderURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                ZStack {
                                    Color(uiColor: .tertiarySystemFill)
                                    Image(systemName: "photo").foregroundColor(.secondary)
                                }
                            default:
                                ZStack {
                                    Color(uiColor: .tertiarySystemFill)
                                    ProgressView().tint(.secondary)
                                }
                            }
                        }
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func labelledCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func bannerRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
            Text(text).font(.caption).foregroundColor(.red)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .cornerRadius(12)
    }

    private var headlineTitle: String {
        let ref = (detail?.refNo ?? listed?.refNo)
        let at = (detail?.submittedAt ?? listed?.submittedAt)
        let title = FormRefDisplay.title(refNo: ref, submittedAt: at)
        return title.isEmpty ? "Report" : title
    }

    // MARK: data

    private func load() async {
        await MainActor.run { isLoading = true }
        let result = await KinematicRepository.shared.getFormSubmission(id: id)
        await MainActor.run {
            isLoading = false
            if let result = result { detail = result; loadFailed = false } else { loadFailed = true }
        }
    }

    private func beginEdit() {
        guard let d = detail else { return }
        draftOutlet = d.outletName ?? ""
        draftValues = [:]
        for a in d.responses ?? [] where FormSubmissionLogic.isEditable(a) {
            if let fid = a.fieldId { draftValues[fid] = FormSubmissionLogic.displayValue(a) }
        }
        saveError = nil
        isEditing = true
    }

    private func cancelEdit() {
        isEditing = false
        saveError = nil
        draftValues = [:]
    }

    private func save() async {
        guard let d = detail else { return }
        var edit = FormSubmissionEditRequest()

        // Only changed text answers.
        var changed: [FormSubmissionEditAnswer] = []
        for a in d.responses ?? [] where FormSubmissionLogic.isEditable(a) {
            guard let fid = a.fieldId, let newValue = draftValues[fid] else { continue }
            if newValue != FormSubmissionLogic.displayValue(a) {
                changed.append(FormSubmissionEditAnswer(fieldId: fid, value: newValue))
            }
        }
        if !changed.isEmpty { edit.responses = changed }

        let trimmedOutlet = draftOutlet.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutlet != (d.outletName ?? "") { edit.outletName = trimmedOutlet }

        if edit.isEmpty {
            await MainActor.run { isEditing = false }
            return
        }

        await MainActor.run { isSaving = true; saveError = nil }
        let updated = await KinematicRepository.shared.updateFormSubmission(id: id, edit)
        await MainActor.run {
            isSaving = false
            if let updated = updated {
                detail = updated
                isEditing = false
                draftValues = [:]
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                saveError = "Couldn't save your changes. You can only edit your own report; check your connection and try again."
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }

    private func exportAndShare() async {
        await MainActor.run { isExporting = true; exportError = nil }
        let export = await KinematicRepository.shared.exportFormSubmission(id: id)
        await MainActor.run {
            isExporting = false
            guard let export = export else {
                exportError = "Couldn't build the export. Check your connection and try again."
                return
            }
            shareItems = [FormSubmissionLogic.exportText(export)]
        }
    }

    private var shareBinding: Binding<Bool> {
        Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })
    }
    private var exportErrorBinding: Binding<Bool> {
        Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
    }
}

// MARK: - Share sheet

/// Presents `UIActivityViewController` so a single report can be shared / saved (text, or a file).
private struct FormShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
