import SwiftUI
import Foundation

// MARK: - API helper for parity views
// These views need ad-hoc API access. We replicate the auth pattern from
// KinematicRepository.performRequest (Bearer + X-Org-Id) without coupling to
// the private method.

private enum ParityAPI {
    static func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        as: T.Type
    ) async -> T? {
        let baseURL = "https://api.kinematic.app/api/v1"
        guard var components = URLComponents(string: "\(baseURL)\(path)") else { return nil }
        guard let url = components.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(AnyEncodable(body))
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            // The backend wraps responses as { success, data, ... }
            if let wrapper = try? JSONDecoder().decode(ApiResponse<T>.self, from: data) {
                return wrapper.data
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("ParityAPI \(method) \(path) failed: \(error)")
            return nil
        }
    }
}

// Type-erased Encodable (Swift's Encodable can't be used directly as a generic
// constraint inside `request` because closures can't carry existentials cleanly
// across actor boundaries on older toolchains).
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<E: Encodable>(_ wrapped: E) { _encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

// MARK: - Leaderboard

struct LeaderboardEntry: Codable, Identifiable {
    let id: String?
    let user_id: String?
    let name: String?
    let employee_id: String?
    let zone: String?
    let score: Double?
    let tff: Int?
    let engagements: Int?
    let rank: Int?
}

@MainActor
class LeaderboardViewModel: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let result: [LeaderboardEntry] = await ParityAPI.request(path: "/leaderboard", as: [LeaderboardEntry].self) {
            entries = result
        }
    }
}

struct LeaderboardView: View {
    @StateObject var vm = LeaderboardViewModel()
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if vm.isLoading && vm.entries.isEmpty {
                    ProgressView().tint(.red).padding(.top, 40)
                } else if vm.entries.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(vm.entries.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardRow(rank: entry.rank ?? (index + 1), entry: entry)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle("Leaderboard")
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.fill").font(.system(size: 50)).foregroundColor(.yellow.opacity(0.4))
            Text("No leaderboard data yet").font(.subheadline).foregroundColor(.gray)
        }.frame(maxWidth: .infinity).padding(.top, 80)
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(rankColor.opacity(0.15)).frame(width: 38, height: 38)
                Text("\(rank)").font(.system(size: 14, weight: .black)).foregroundColor(rankColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name ?? "Unknown").font(.subheadline).fontWeight(.bold)
                if let zone = entry.zone, !zone.isEmpty {
                    Text(zone).font(.caption2).foregroundColor(.gray)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.tff ?? entry.engagements ?? 0)").font(.system(size: 16, weight: .black)).foregroundColor(.green)
                Text("TFF").font(.caption2).foregroundColor(.gray)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(14)
    }
    private var rankColor: Color {
        switch rank { case 1: return .yellow; case 2: return .gray; case 3: return .orange; default: return .blue }
    }
}

// MARK: - Notifications

struct AppNotification: Codable, Identifiable {
    let id: String
    let title: String?
    let body: String?
    let is_read: Bool?
    let created_at: String?
    let type: String?
}

@MainActor
class NotificationsViewModel: ObservableObject {
    @Published var items: [AppNotification] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let result: [AppNotification] = await ParityAPI.request(path: "/notifications", as: [AppNotification].self) {
            items = result
        }
    }

    func markAllRead() async {
        struct Body: Encodable { let all: Bool = true }
        _ = await ParityAPI.request(path: "/notifications/read", method: "PATCH", body: Body(), as: [String: String].self)
        await load()
    }
}

struct NotificationsView: View {
    @StateObject var vm = NotificationsViewModel()
    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().tint(.red)
            } else if vm.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash.fill").font(.system(size: 50)).foregroundColor(.gray.opacity(0.4))
                    Text("You're all caught up").font(.subheadline).foregroundColor(.gray)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.items) { n in NotificationRow(n: n) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Mark all read") { Task { await vm.markAllRead() } }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}

private struct NotificationRow: View {
    let n: AppNotification
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill((n.is_read == true) ? Color.gray.opacity(0.3) : Color.blue).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(n.title ?? "Notification").font(.subheadline).fontWeight((n.is_read == true) ? .regular : .bold)
                if let body = n.body, !body.isEmpty {
                    Text(body).font(.caption).foregroundColor(.gray)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Grievance

@MainActor
class GrievanceViewModel: ObservableObject {
    @Published var category: String = "harassment"
    @Published var description: String = ""
    @Published var isAnonymous: Bool = false
    @Published var isSubmitting = false
    @Published var success = false
    @Published var error: String?

    let categories = ["harassment", "discrimination", "safety", "compensation", "policy", "other"]

    func submit() async {
        guard description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 else {
            error = "Please describe your grievance (10+ characters)"
            return
        }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        struct Body: Encodable {
            let category: String
            let description: String
            let is_anonymous: Bool
        }
        let payload = Body(category: category, description: description, is_anonymous: isAnonymous)
        if let _: [String: String] = await ParityAPI.request(path: "/grievances", method: "POST", body: payload, as: [String: String].self) {
            success = true
            description = ""
        } else {
            error = "Failed to submit. Please try again."
        }
    }
}

struct GrievanceView: View {
    @StateObject var vm = GrievanceViewModel()
    var body: some View {
        Form {
            Section(header: Text("Category")) {
                Picker("Category", selection: $vm.category) {
                    ForEach(vm.categories, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            Section(header: Text("Description")) {
                TextEditor(text: $vm.description).frame(minHeight: 140)
            }
            Section {
                Toggle("Submit anonymously", isOn: $vm.isAnonymous)
            }
            if let err = vm.error {
                Text(err).foregroundColor(.red).font(.caption)
            }
            if vm.success {
                Text("Submitted. HR will review and respond.").foregroundColor(.green).font(.caption)
            }
            Section {
                Button(action: { Task { await vm.submit() } }) {
                    HStack {
                        if vm.isSubmitting { ProgressView().tint(.white) }
                        Text(vm.isSubmitting ? "Submitting…" : "Submit Grievance")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(vm.isSubmitting)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Grievance")
    }
}

// MARK: - Visit Log

struct VisitLogEntry: Codable, Identifiable {
    let id: String
    let executive_id: String?
    let executive_name: String?
    let outlet_name: String?
    let rating: String?
    let remarks: String?
    let created_at: String?
}

@MainActor
class VisitLogViewModel: ObservableObject {
    @Published var entries: [VisitLogEntry] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let result: [VisitLogEntry] = await ParityAPI.request(path: "/visits/team", as: [VisitLogEntry].self) {
            entries = result
        } else if let myList: [VisitLogEntry] = await ParityAPI.request(path: "/visits", as: [VisitLogEntry].self) {
            entries = myList
        }
    }
}

struct VisitLogView: View {
    @StateObject var vm = VisitLogViewModel()
    var body: some View {
        Group {
            if vm.isLoading && vm.entries.isEmpty {
                ProgressView().tint(.red)
            } else if vm.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle").font(.system(size: 50)).foregroundColor(.gray.opacity(0.4))
                    Text("No visit logs yet").font(.subheadline).foregroundColor(.gray)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.entries) { e in VisitLogRow(e: e) }.listStyle(.plain)
            }
        }
        .navigationTitle("Visit Log")
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}

private struct VisitLogRow: View {
    let e: VisitLogEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(e.outlet_name ?? "Visit").font(.subheadline).fontWeight(.semibold)
                Spacer()
                if let r = e.rating { ratingBadge(r) }
            }
            if let exec = e.executive_name { Text(exec).font(.caption).foregroundColor(.gray) }
            if let remarks = e.remarks, !remarks.isEmpty { Text(remarks).font(.caption2).foregroundColor(.secondary) }
        }
        .padding(.vertical, 4)
    }
    private func ratingBadge(_ rating: String) -> some View {
        let color: Color = {
            switch rating { case "excellent": return .green; case "good": return .blue; case "average": return .orange; default: return .red }
        }()
        return Text(rating.capitalized).font(.caption2).fontWeight(.semibold).padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(6)
    }
}

// MARK: - Stock / Inventory

struct StockItem: Codable, Identifiable {
    let id: String
    let item_name: String?
    let sku: String?
    let quantity: Int?
    let quantity_accepted: Int?
    let status: String?
    let allocated_at: String?
}

@MainActor
class StockViewModel: ObservableObject {
    @Published var items: [StockItem] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let result: [StockItem] = await ParityAPI.request(path: "/stock/my", as: [StockItem].self) {
            items = result
        }
    }

    func updateItem(_ item: StockItem, status: String) async {
        struct Body: Encodable { let status: String }
        _ = await ParityAPI.request(path: "/stock/items/\(item.id)", method: "PATCH", body: Body(status: status), as: [String: String].self)
        await load()
    }
}

struct StockView: View {
    @StateObject var vm = StockViewModel()
    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().tint(.red)
            } else if vm.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox").font(.system(size: 50)).foregroundColor(.gray.opacity(0.4))
                    Text("No stock allocations").font(.subheadline).foregroundColor(.gray)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.items) { item in StockRow(item: item, vm: vm) }
                }.listStyle(.plain)
            }
        }
        .navigationTitle("Stock")
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}

private struct StockRow: View {
    let item: StockItem
    @ObservedObject var vm: StockViewModel
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.item_name ?? "Item").font(.subheadline).fontWeight(.semibold)
                HStack(spacing: 8) {
                    if let sku = item.sku { Text(sku).font(.caption2).foregroundColor(.gray) }
                    if let q = item.quantity { Text("Qty: \(q)").font(.caption2).foregroundColor(.gray) }
                }
                if let s = item.status { statusBadge(s) }
            }
            Spacer()
            if (item.status ?? "").lowercased() == "pending" {
                HStack(spacing: 6) {
                    Button { Task { await vm.updateItem(item, status: "accepted") } } label: {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    }
                    Button { Task { await vm.updateItem(item, status: "rejected") } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    }
                }.buttonStyle(.borderless)
            }
        }
    }
    private func statusBadge(_ s: String) -> some View {
        let c: Color = { switch s.lowercased() { case "accepted": return .green; case "rejected": return .red; case "partially_accepted": return .orange; default: return .blue } }()
        return Text(s.capitalized).font(.caption2).fontWeight(.semibold).padding(.horizontal, 6).padding(.vertical, 2)
            .background(c.opacity(0.15)).foregroundColor(c).cornerRadius(4)
    }
}
