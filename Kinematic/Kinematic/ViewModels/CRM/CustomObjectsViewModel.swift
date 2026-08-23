import Foundation
import Combine

/// Lists the admin-defined object types.
@MainActor
final class CustomObjectsViewModel: ObservableObject {
    @Published var objects: [CRMCustomObject] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

    func loadObjects() async {
        isLoading = true
        defer { isLoading = false }
        do { objects = try await api.listCustomObjects().filter { $0.isActive != false } }
        catch { errorMessage = error.localizedDescription }
    }
}

/// Records for a single custom object (identified by its key).
@MainActor
final class CustomObjectRecordsViewModel: ObservableObject {
    @Published var records: [CRMCustomRecord] = []
    @Published var search: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    let objectKey: String
    private let api = CRMService.shared

    init(objectKey: String) { self.objectKey = objectKey }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do { records = try await api.listCustomRecords(objectKey: objectKey, search: search.isEmpty ? nil : search) }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ rec: CRMCustomRecord) async {
        do {
            try await api.deleteCustomRecord(objectKey: objectKey, id: rec.id)
            records.removeAll { $0.id == rec.id }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Create (id == nil) or update a record. Returns true on success.
    func save(id: String?, body: [String: Any]) async -> Bool {
        do {
            if let id { _ = try await api.updateCustomRecord(objectKey: objectKey, id: id, body: body) }
            else { _ = try await api.createCustomRecord(objectKey: objectKey, body: body) }
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
