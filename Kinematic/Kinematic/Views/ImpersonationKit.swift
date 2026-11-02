import SwiftUI
import Combine

// MARK: - Master-admin "View as User" (read-only impersonation)
//
// The backend already implements this end-to-end (src/routes/auth.routes.ts:
// GET /auth/impersonate/search + POST /auth/impersonate/start, and the
// readOnlyGuard mounted on the whole /api/v1 surface). This client only:
//   1. searches users (master-gated server-side),
//   2. starts a read-only session by swapping the bearer to the minted
//      `ro:true` token (per-project, 1h, no refresh),
//   3. reloads the app AS the target, shows a READ-ONLY banner,
//   4. refuses writes locally and restores the master on Exit (or when the
//      short-lived token dies).
//
// The read-only guarantee is server-side (the minted token forces
// users.is_read_only → every write 403s). The local write-refusal + banner are
// UX so the master gets a clean message instead of a server error.

let KM_MASTER_ADMIN_EMAIL = "s@kinematicapp.com"

/// In-memory (process-lifetime) read-only flag, readable from the networking
/// layer on any thread without hopping to the main actor. Reset on relaunch so
/// a crash mid-impersonation can never leave the app stuck read-only.
enum ImpersonationState {
    nonisolated(unsafe) static var readOnly = false
}

// MARK: - Decoded response models

struct ImpersonateSearchUser: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let email: String?
    let role: String?
    let orgId: String?
    let clientId: String?
    let orgRoleName: String?
    let project: String?
    enum CodingKeys: String, CodingKey {
        case id, name, email, role, project
        case orgId = "org_id"
        case clientId = "client_id"
        case orgRoleName = "org_role_name"
    }
}

struct ImpersonateStartUser: Codable {
    let id: String?
    let name: String?
    let email: String?
    let role: String?
    let orgId: String?
    let clientId: String?
    enum CodingKeys: String, CodingKey {
        case id, name, email, role
        case orgId = "org_id"
        case clientId = "client_id"
    }
}

struct ImpersonateStartData: Codable {
    let token: String
    let project: String?
    let readOnly: Bool?
    let user: ImpersonateStartUser?
    enum CodingKeys: String, CodingKey {
        case token, project, user
        case readOnly = "read_only"
    }
}

// MARK: - Manager

@MainActor
final class ImpersonationManager: ObservableObject {
    static let shared = ImpersonationManager()
    private init() {}

    struct ActiveSession: Equatable {
        let name: String
        let email: String
        let readOnly: Bool
    }

    /// Non-nil while a "View as User" session is active — drives the banner.
    @Published private(set) var active: ActiveSession?

    var isImpersonating: Bool { active != nil }
    var isReadOnly: Bool { active?.readOnly ?? false }

    // The master's own live session, stashed so Exit (or an expired read-only
    // token) restores it exactly. Memory-only, for the app process lifetime.
    private struct MasterStash {
        let token: String
        let refresh: String
        let sessionId: String?
        let project: String?
        let user: User?
    }
    private var stash: MasterStash?

    /// Start a read-only "View as" session as `target`. Throws on failure
    /// (network / not-master / target not found) leaving the master intact.
    func start(_ target: ImpersonateSearchUser) async throws {
        let data = try await KinematicRepository.shared.impersonateStart(userId: target.id, project: target.project)

        // Stash the master's live session BEFORE overwriting it.
        stash = MasterStash(
            token: Session.sharedToken,
            refresh: Session.refreshToken,
            sessionId: Session.sessionId,
            project: Session.project,
            user: Session.currentUser
        )

        // Swap to the minted target token. It is per-project and has no refresh
        // token (≈1h TTL); the 401/dead-session path returns to the master.
        Session.project      = data.project ?? target.project
        Session.sharedToken  = data.token
        Session.refreshToken = ""
        Session.sessionId    = nil
        // Drop the master's tenant pick / city filter so they don't bleed in.
        CRMClientScope.setSelectedClientId(nil)
        CRMLocationStore.shared.clear()

        // Re-hydrate AS the target (authoritative /auth/me: entitlements, UI config).
        _ = await KinematicRepository.shared.refreshMe()

        let session = ActiveSession(
            name: data.user?.name ?? target.name ?? "user",
            email: data.user?.email ?? target.email ?? "",
            readOnly: data.readOnly ?? true
        )
        ImpersonationState.readOnly = session.readOnly
        active = session

        KiniAppState.shared.checkAuth()
        // Rebuild the authenticated shell as the target on the NEXT runloop so
        // the presenting search sheet finishes dismissing first (avoids tearing
        // down its host mid-presentation).
        DispatchQueue.main.async { KiniAppState.shared.identityEpoch = UUID() }
    }

    /// Restore the master's own session. No-op (false) if not impersonating.
    @discardableResult
    func stop() -> Bool {
        guard let s = stash else { return false }
        Session.sharedToken  = s.token
        Session.refreshToken = s.refresh
        Session.sessionId    = s.sessionId
        Session.project      = s.project
        Session.currentUser  = s.user
        stash = nil
        active = nil
        ImpersonationState.readOnly = false
        CRMClientScope.setSelectedClientId(nil)
        CRMLocationStore.shared.clear()
        KiniAppState.shared.identityEpoch = UUID()
        KiniAppState.shared.checkAuth()
        return true
    }

    /// Called from the 401 / dead-session path: the minted read-only token
    /// expires (~1h, no refresh), so return to the master instead of signing
    /// out. Returns true if it handled the dead session.
    func returnToMasterIfImpersonating() -> Bool {
        guard isImpersonating else { return false }
        return stop()
    }
}

// MARK: - Search sheet (master-admin only; gated at the call site)

struct ImpersonationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ImpersonateSearchUser] = []
    @State private var loading = false
    @State private var starting: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search by name or email…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if let errorText {
                    Text(errorText)
                        .font(.footnote).foregroundColor(Brand.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.top, 8)
                }

                List {
                    if loading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Start typing a name or email to find a user.")
                            .font(.footnote).foregroundColor(.secondary)
                    } else if results.isEmpty {
                        Text("No users match.")
                            .font(.footnote).foregroundColor(.secondary)
                    } else {
                        ForEach(results) { u in
                            Button { Task { await startAs(u) } } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(u.name ?? "Unnamed user")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text([u.email, (u.orgRoleName ?? u.role)]
                                                .compactMap { $0 }
                                                .filter { !$0.isEmpty }
                                                .joined(separator: " · "))
                                            .font(.caption).foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if starting == u.id {
                                        ProgressView()
                                    } else {
                                        Text("View as →")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.purple)
                                    }
                                }
                            }
                            .disabled(starting != nil)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("View as User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                errorText = nil
                guard q.count >= 1 else { results = []; loading = false; return }
                try? await Task.sleep(nanoseconds: 300_000_000)   // debounce
                if Task.isCancelled { return }
                loading = true
                let r = await KinematicRepository.shared.impersonateSearch(q)
                if Task.isCancelled { return }
                results = r
                loading = false
            }
        }
    }

    private func startAs(_ u: ImpersonateSearchUser) async {
        starting = u.id
        errorText = nil
        do {
            try await ImpersonationManager.shared.start(u)
            dismiss()
        } catch {
            errorText = "Couldn't start the read-only session. \(error.localizedDescription)"
            starting = nil
        }
    }
}

// MARK: - Read-only banner (shown app-wide while impersonating)

struct ImpersonationBanner: View {
    let active: ImpersonationManager.ActiveSession
    var onExit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.fill").font(.system(size: 12, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
                Text("Viewing as \(active.name)")
                    .font(.system(size: 13, weight: .bold)).lineLimit(1)
                if !active.email.isEmpty {
                    Text(active.readOnly ? "\(active.email) · read-only" : active.email)
                        .font(.system(size: 11)).opacity(0.9).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: onExit) {
                Text("Exit")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.white.opacity(0.25))
                    .clipShape(Capsule())
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.purple)
    }
}
