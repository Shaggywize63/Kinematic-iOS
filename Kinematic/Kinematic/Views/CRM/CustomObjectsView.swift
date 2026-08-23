import SwiftUI

// MARK: - Object-type list

struct CustomObjectsListView: View {
    @StateObject private var vm = CustomObjectsViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if vm.isLoading && vm.objects.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if vm.objects.isEmpty {
                    Text("No custom objects yet.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    ForEach(vm.objects) { obj in
                        NavigationLink {
                            CustomObjectRecordsView(object: obj)
                        } label: {
                            CustomObjectCard(object: obj)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Custom Objects")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadObjects() }
        .refreshable { await vm.loadObjects() }
    }
}

private struct CustomObjectCard: View {
    let object: CRMCustomObject
    var body: some View {
        HStack(spacing: 12) {
            Text(object.icon ?? "🧩").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(object.displayPlural).font(.headline)
                if let d = object.description, !d.isEmpty {
                    Text(d).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Records for one object

struct CustomObjectRecordsView: View {
    let object: CRMCustomObject
    @StateObject private var vm: CustomObjectRecordsViewModel
    @State private var showForm = false
    @State private var editing: CRMCustomRecord?

    init(object: CRMCustomObject) {
        self.object = object
        _vm = StateObject(wrappedValue: CustomObjectRecordsViewModel(objectKey: object.key))
    }

    var body: some View {
        List {
            if vm.records.isEmpty && !vm.isLoading {
                Text("No records yet.").foregroundStyle(.secondary)
            }
            ForEach(vm.records) { rec in
                Button {
                    editing = rec
                    showForm = true
                } label: {
                    CustomRecordRow(record: rec)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await vm.delete(rec) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $vm.search)
        .onChange(of: vm.search) { _, _ in Task { await vm.refresh() } }
        .navigationTitle(object.displayPlural)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = nil
                    showForm = true
                } label: { Image(systemName: "plus") }
            }
        }
        .task { await vm.refresh() }
        .sheet(isPresented: $showForm) {
            CustomObjectRecordForm(objectKey: object.key, objectLabel: object.label, editing: editing) { id, body in
                await vm.save(id: id, body: body)
            }
        }
    }
}

private struct CustomRecordRow: View {
    let record: CRMCustomRecord
    var body: some View {
        let preview = recordPreview(record)
        return VStack(alignment: .leading, spacing: 3) {
            Text((record.title?.isEmpty == false) ? record.title! : "(untitled)").font(.headline)
            if !preview.isEmpty {
                Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A compact "key: value" preview of the first few field values on a record.
private func recordPreview(_ record: CRMCustomRecord) -> String {
    guard let data = record.data else { return "" }
    let parts: [String] = data.prefix(4).compactMap { (k, v) in
        guard let s = v.value, !s.isEmpty else { return nil }
        return "\(k): \(s)"
    }
    return parts.joined(separator: "  ·  ")
}

// MARK: - Dynamic add/edit form (reuses CustomFieldsModel + CustomFieldsSection)

struct CustomObjectRecordForm: View {
    let objectKey: String
    let objectLabel: String
    let editing: CRMCustomRecord?
    let onSubmit: (_ id: String?, _ body: [String: Any]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var customFields = CustomFieldsModel()
    @State private var title: String = ""
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Title", text: $title) }
                CustomFieldsSection(model: customFields)
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle(editing == nil ? "New \(objectLabel)" : "Edit \(objectLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await submit() } }.disabled(saving)
                }
            }
            .task {
                await customFields.load(entity: objectKey)
                if let editing { customFields.hydrate(from: editing.data) }
                title = editing?.title ?? ""
            }
        }
    }

    private func submit() async {
        let missing = customFields.missingRequiredLabels
        if !missing.isEmpty {
            errorText = "Required: " + missing.joined(separator: ", ")
            return
        }
        saving = true
        defer { saving = false }
        var body: [String: Any] = [:]
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { body["title"] = t }
        body["data"] = customFields.jsonValues
        let ok = await onSubmit(editing?.id, body)
        if ok { dismiss() } else { errorText = "Save failed. Please try again." }
    }
}
