//
//  TelecallerTabView.swift
//  Kinematic CRM
//
//  The focused shell for a TELECALLER (outbound "Call Tracker", phase 1) — a
//  phone agent with no field visits / GPS. Four tabs only:
//    • My Calls   — the leads an admin assigned to them (own-scoped server-side)
//    • Follow-ups — their scheduled call activities
//    • Targets    — Scheme Amount ₹ progress + "Calls this month"
//    • More       — profile / change password / sign out
//  Every field-force / GPS surface is hidden. Mirrors CRMTabView's iOS 26
//  Tab(value:) + Liquid Glass tab bar, so it feels like the same product.
//

import SwiftUI

struct TelecallerTabView: View {
    @EnvironmentObject var appState: KiniAppState
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("My Calls", systemImage: "phone.arrow.up.right.fill", value: 0) {
                NavigationStack { TelecallerCallsView() }
            }
            // Follow-ups reuses the scheduled-activities surface, focused on
            // calls — the follow-ups a Log Call saves are open "call" activities.
            Tab("Follow-ups", systemImage: "bell.badge.fill", value: 1) {
                NavigationStack { ActivitiesView(initialFilter: "call") }
            }
            Tab("Targets", systemImage: "indianrupeesign.circle.fill", value: 2) {
                NavigationStack { TelecallerTargetsView() }
            }
            Tab("More", systemImage: "ellipsis.circle", value: 3) {
                NavigationStack { TelecallerMoreView() }
            }
        }
        .tint(Brand.red)
        .tabBarMinimizeOnScrollIfAvailable()
        // Re-assert the chosen theme at the shell root (as CRMTabView does), in
        // case this shell is presented where it doesn't inherit the root scheme.
        .preferredColorScheme(appState.theme == .system ? nil : (appState.theme == .dark ? .dark : .light))
    }
}

/// Lean "More" for telecallers — only the account rows a phone agent needs,
/// reusing the same ProfileView / ChangePasswordView the CRM More menu pushes.
struct TelecallerMoreView: View {
    @EnvironmentObject var appState: KiniAppState
    @State private var showLogoutConfirm = false

    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = (info["CFBundleShortVersionString"] as? String) ?? "?"
        let b = (info["CFBundleVersion"] as? String) ?? "?"
        return "\(v) (\(b))"
    }

    private var profileAvatar: some View {
        let initials = String((Session.currentUser?.name ?? "U").prefix(1)).uppercased()
        return ZStack {
            Circle().fill(Brand.red.opacity(0.15))
            if let s = Session.currentUser?.avatarUrl, !s.isEmpty {
                SignedAsyncImage(urlString: s) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Text(initials).font(.system(size: 18, weight: .black)).foregroundColor(Brand.red)
                    }
                }
            } else {
                Text(initials).font(.system(size: 18, weight: .black)).foregroundColor(Brand.red)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ProfileView()
                } label: {
                    HStack(spacing: 12) {
                        profileAvatar
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Session.currentUser?.name ?? "My Profile")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            Text((Session.currentUser?.orgRoleName ?? Session.currentUser?.role ?? "Tap to edit your photo")
                                    .replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                NavigationLink {
                    ChangePasswordView()
                } label: { telecallerMoreRow(icon: "key.fill", title: "Change password") }
            }

            Section {
                Button {
                    showLogoutConfirm = true
                } label: {
                    HStack {
                        telecallerMoreRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out", tint: .red)
                        Spacer()
                    }
                }
                .foregroundColor(.red)
            }

            Section {
                HStack {
                    Spacer()
                    Text("Kinematic v\(appVersionDisplay)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign out?", isPresented: $showLogoutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) { appState.logout() }
        } message: {
            Text("You'll need to sign back in to access your calls.")
        }
    }

    private func telecallerMoreRow(icon: String, title: String, tint: Color = Brand.red) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon).foregroundColor(tint).font(.system(size: 14, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 15, weight: .medium))
        }
    }
}
