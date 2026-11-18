import SwiftUI

/// "Owners" card on a lead / account / contact / deal: the single primary owner plus any co-owners (peers who
/// also see the record). An admin or the primary owner can add / remove co-owners; everyone else sees the
/// chips read-only. Owner is a built-in field, so the card is withheld when the admin hides `owner_id` (the
/// field-override contract) and deferred until the overrides load.
///
/// `entity` is the API path segment (leads|accounts|contacts|deals); `overrideEntity` the field-override
/// entity (lead|account|contact|deal). Self-loading over `CRMService`.
struct CoOwnersCard: View {
    let entity: String
    let overrideEntity: String
    let recordId: String
    let primaryOwnerId: String?
    let primaryOwnerName: String?
    @ObservedObject var fieldOverrides: LeadFieldOverridesModel

    @State private var owners: [CoOwner] = []
    @State private var users: [AssignableUser] = []
    @State private var saving = false
    @State private var loaded = false

    private var canEdit: Bool { RecordOwnerRules.currentUserCanChange }

    private var pickable: [AssignableUser] {
        let taken = Set([primaryOwnerId].compactMap { $0 } + owners.map { $0.userId })
        return users.filter { !taken.contains($0.id) }
    }

    var body: some View {
        if fieldOverrides.didLoad && !fieldOverrides.isHidden(entity: overrideEntity, "owner_id") {
            VStack(alignment: .leading, spacing: 10) {
                Text("OWNERS")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .foregroundColor(Brand.red)

                // Primary owner, shown first and marked (change it on the owner control).
                if let name = primaryOwnerName, !name.isEmpty {
                    HStack {
                        Text(name).font(.subheadline.weight(.semibold))
                        Text("PRIMARY").font(.caption2.weight(.bold)).foregroundColor(.secondary)
                        Spacer()
                    }
                }

                ForEach(owners) { o in
                    HStack {
                        Text(o.name ?? "User").font(.subheadline)
                        Spacer()
                        if canEdit {
                            Button {
                                Task { await save(owners.filter { $0.userId != o.userId }.map { $0.userId }) }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(saving)
                        }
                    }
                }

                if owners.isEmpty && !canEdit {
                    Text("No co-owners").font(.subheadline).foregroundColor(.secondary)
                }

                if canEdit {
                    Menu {
                        if pickable.isEmpty {
                            Text("No one to add")
                        } else {
                            ForEach(pickable) { u in
                                Button(u.displayName) {
                                    Task { await save(owners.map { $0.userId } + [u.id]) }
                                }
                            }
                        }
                    } label: {
                        Label(saving ? "Saving…" : "Add a co-owner", systemImage: "person.badge.plus")
                            .font(.caption.weight(.semibold))
                    }
                    .disabled(saving)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
            .task(id: recordId) { await load() }
        }
    }

    private func load() async {
        owners = (try? await CRMService.shared.coOwners(entity: entity, id: recordId)) ?? []
        if canEdit, users.isEmpty {
            users = await CRMService.shared.listAssignableUsers()
        }
        loaded = true
    }

    private func save(_ userIds: [String]) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        if let refreshed = try? await CRMService.shared.setCoOwners(entity: entity, id: recordId, userIds: userIds) {
            owners = refreshed
        }
    }
}
