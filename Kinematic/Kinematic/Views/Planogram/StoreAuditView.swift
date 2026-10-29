//
//  StoreAuditView.swift
//  Kinematic
//
//  Bahwancy / AVOD "Store audit" home — a planogram-only shell (see
//  ContentView → `ClientFeatures.isBahwancy`). Unlike MoiSoi's storeless
//  one-tap capture, the rep picks a STORE from the backend list
//  (GET /api/v1/stores, gated on the granted `stores` module), then runs an
//  AI shelf audit tagged with that store's id. No attendance / route / CRM
//  surface; sign-out is the only way back to Login.
//

import SwiftUI

/// Minimal store row for the "Store audit" picker (GET /api/v1/stores). Extra
/// columns the backend returns (city, zone, geo, approval) are ignored.
struct StoreLite: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let storeType: String?
    enum CodingKeys: String, CodingKey {
        case id, name
        case storeType = "store_type"
    }
}

@MainActor
final class StoreAuditModel: ObservableObject {
    enum Phase: Equatable { case loading, loaded, error(String) }
    @Published var phase: Phase = .loading
    @Published var stores: [StoreLite] = []

    func load() async {
        phase = .loading
        do {
            let list: [StoreLite] = try await CRMService.shared.getList("/api/v1/stores")
            stores = list.filter { !($0.name ?? "").isEmpty }
            phase = .loaded
        } catch {
            phase = .error("Couldn't load stores. Tap retry.")
        }
    }
}

struct StoreAuditView: View {
    @EnvironmentObject var appState: KiniAppState
    @StateObject private var model = StoreAuditModel()
    @State private var selected: StoreLite?
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Store audit")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                appState.logout()
                            } label: {
                                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
        }
        .task {
            if case .loading = model.phase { await model.load() }
        }
        .fullScreenCover(isPresented: $showCapture) {
            PlanogramCaptureView(storeId: selected?.id, visitId: nil, planogramId: nil)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            messageView(
                title: "Couldn't load stores",
                message: msg,
                icon: "exclamationmark.triangle"
            )
        case .loaded:
            if model.stores.isEmpty {
                messageView(
                    title: "No stores yet",
                    message: "No stores are set up for your account. Ask your admin to add stores, then retry.",
                    icon: "storefront"
                )
            } else {
                picker
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose the store you're auditing, then start the shelf capture — point your camera at the shelf for instant compliance analysis.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(model.stores) { store in
                    Button {
                        selected = store
                    } label: {
                        Text(store.name ?? "Unnamed store")
                    }
                }
            } label: {
                HStack {
                    Text(selected?.name ?? "Select a store")
                        .foregroundStyle(selected == nil ? Color.secondary : Color.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.4))
                )
            }

            Button {
                showCapture = true
            } label: {
                Label("Start Store audit", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected == nil)

            Spacer()
        }
        .padding()
    }

    private func messageView(title: String, message: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await model.load() } }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
