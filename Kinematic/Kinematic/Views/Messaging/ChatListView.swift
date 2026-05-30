//
//  ChatListView.swift
//  Kinematic
//
//  Inbox: list of every DM + team chat the rep is a member of.
//  Tap a row to open the thread. Plus button → compose sheet.
//

import SwiftUI
// iOS 26's MemberImportVisibility doesn't re-export ObservableObject /
// @Published through SwiftUI anymore, so we have to import Combine
// explicitly even though the file otherwise only touches SwiftUI types.
import Combine

@MainActor
final class ChatListViewModel: ObservableObject {
    @Published var threads: [MessagingThread] = []
    @Published var loading = false
    @Published var error: String?
    private var pollTask: Task<Void, Never>?

    func start() {
        Task { await reload() }
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                await reload()
            }
        }
    }

    func stop() { pollTask?.cancel(); pollTask = nil }

    func reload() async {
        loading = threads.isEmpty
        do {
            threads = try await CRMService.shared.listMessagingThreads()
            error = nil
        } catch {
            self.error = (error as? CRMServiceError)?.localizedDescription ?? error.localizedDescription
        }
        loading = false
    }
}

/// Lightweight wrapper so a thread id can drive `.navigationDestination(item:)`,
/// which needs `Identifiable & Hashable` — bare `String` isn't `Identifiable`.
struct ChatThreadID: Identifiable, Hashable { let id: String }

struct ChatListView: View {
    @StateObject private var vm = ChatListViewModel()
    @State private var composeOpen = false
    @State private var openThread: ChatThreadID?

    var body: some View {
        ZStack {
            if vm.loading && vm.threads.isEmpty {
                ProgressView()
            } else if vm.threads.isEmpty {
                emptyState
            } else {
                List(vm.threads) { t in
                    Button { openThread = ChatThreadID(id: t.id) } label: { ThreadRowView(thread: t) }
                        .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { composeOpen = true } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $composeOpen) {
            ComposeThreadSheet { newId in
                composeOpen = false
                Task { await vm.reload() }
                openThread = ChatThreadID(id: newId)
            }
        }
        .navigationDestination(item: $openThread) { ref in
            ChatThreadView(threadId: ref.id)
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .refreshable { await vm.reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No conversations yet").font(.headline)
            Text("Tap the compose button to start a direct message or team chat.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button("New message") { composeOpen = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
    }
}

private struct ThreadRowView: View {
    let thread: MessagingThread
    var body: some View {
        HStack(spacing: 12) {
            let isTeam = thread.kind == "team"
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isTeam ? Color.orange.opacity(0.15) : Color.indigo.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(isTeam ? "T" : "DM")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isTeam ? Color.orange : Color.indigo)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(thread.title).font(.body.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if let u = thread.unreadCount, u > 0 {
                        Text(u > 99 ? "99+" : "\(u)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    }
                }
                Text(thread.lastMessagePreview ?? "No messages yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Compose sheet

private struct ComposeThreadSheet: View {
    let onCreated: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: String = "dm"
    @State private var teamName: String = ""
    @State private var query: String = ""
    @State private var results: [MessagingScopedUser] = []
    @State private var selected: [MessagingScopedUser] = []
    @State private var submitting = false
    @State private var loading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("", selection: $kind) {
                    Text("Direct message").tag("dm")
                    Text("Team chat").tag("team")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if kind == "team" {
                    TextField("Team chat name (optional)", text: $teamName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }

                if !selected.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(selected) { u in
                                HStack(spacing: 4) {
                                    Text(u.displayName).font(.caption)
                                    Button { selected.removeAll { $0.id == u.id } } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                            }
                        }.padding(.horizontal)
                    }
                }

                TextField(
                    kind == "dm" && !selected.isEmpty
                        ? "DM is 1-on-1 — remove to pick another"
                        : "Search by name or email",
                    text: $query
                )
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .disabled(kind == "dm" && !selected.isEmpty)
                .onChange(of: query) { _, _ in Task { await runSearch() } }

                List {
                    if loading { ProgressView() }
                    if results.isEmpty && !loading {
                        Text("No matches.").foregroundStyle(.secondary).font(.footnote)
                    }
                    ForEach(results) { u in
                        let alreadyIn = selected.contains { $0.id == u.id }
                        let locked = kind == "dm" && !selected.isEmpty
                        Button {
                            guard !alreadyIn, !locked else { return }
                            selected.append(u)
                            query = ""
                        } label: {
                            VStack(alignment: .leading) {
                                Text(u.displayName).font(.body.weight(.semibold))
                                if !u.citiesText.isEmpty {
                                    Text(u.citiesText).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(alreadyIn || locked)
                    }
                }
                .listStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .navigationTitle("New conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(kind == "dm" ? "Start DM" : "Create") {
                        Task { await create() }
                    }
                    .disabled(submitting || selected.isEmpty)
                }
            }
            .task { await runSearch() }
        }
    }

    private func runSearch() async {
        loading = true
        defer { loading = false }
        results = (try? await CRMService.shared.searchMessagingUsers(q: query)) ?? []
    }

    private func create() async {
        submitting = true
        defer { submitting = false }
        do {
            let id: String
            if kind == "dm", let first = selected.first {
                id = try await CRMService.shared.createMessagingDm(otherUserId: first.id)
            } else {
                let title = teamName.trimmingCharacters(in: .whitespaces)
                id = try await CRMService.shared.createMessagingTeam(
                    name: title.isEmpty ? "Team Chat" : title,
                    memberIds: selected.map { $0.id }
                )
            }
            onCreated(id)
        } catch {
            // Surface failures inline via the parent; the sheet stays open.
        }
    }
}

