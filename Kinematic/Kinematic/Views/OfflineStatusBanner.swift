//
//  OfflineStatusBanner.swift
//  Kinematic
//
//  Pill-shaped banner that overlays the top of every screen whenever the
//  device is offline OR any of the three pending-mutation queues has
//  rows still owed to the server. Tap → opens a sheet listing the
//  pending rows with retry / delete buttons.
//
//  Mount once on the root `ContentView` via a ZStack overlay; safe to
//  embed deeper for visibility on modal sheets that don't share the root
//  ZStack.
//

import SwiftUI

struct OfflineStatusBanner: View {
    @ObservedObject private var reachability = NetworkReachability.shared
    @ObservedObject private var crmQueue = CRMWriteQueue.shared
    @ObservedObject private var attendance = AttendanceCache.shared
    @ObservedObject private var orderCache = OrderCache.shared
    @State private var showingSheet = false

    /// Combined count across the three queues (current-user-scoped).
    private var pendingCount: Int {
        let crm = crmQueue.pendingForCurrentUser().count
        let att = attendance.pendingForCurrentUser().count
        let p = orderCache.pendingForCurrentUser()
        let dist = p.orders.count + p.payments.count + p.returns.count
        return crm + att + dist
    }

    private var shouldShow: Bool { !reachability.isOnline || pendingCount > 0 }

    private var label: String {
        if !reachability.isOnline && pendingCount > 0 {
            return "Offline · \(pendingCount) pending sync"
        } else if !reachability.isOnline {
            return "Offline"
        } else if pendingCount > 0 {
            return "Syncing \(pendingCount) change\(pendingCount == 1 ? "" : "s")…"
        } else {
            return ""
        }
    }

    private var tint: Color {
        // Red when offline (the user can't recover until the link returns),
        // amber when online-but-syncing (transient state — should clear
        // within seconds).
        reachability.isOnline ? .orange : .red
    }

    var body: some View {
        if shouldShow {
            Button(action: { showingSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: reachability.isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash")
                        .font(.system(size: 11, weight: .bold))
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(tint.opacity(0.92))
                )
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .sheet(isPresented: $showingSheet) {
                PendingSyncSheet()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityLabel(label)
        }
    }
}

// MARK: - Pending sync sheet

private struct PendingSyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var crmQueue = CRMWriteQueue.shared
    @ObservedObject private var attendance = AttendanceCache.shared
    @ObservedObject private var orderCache = OrderCache.shared
    @ObservedObject private var reachability = NetworkReachability.shared

    private static let timeFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: reachability.isOnline ? "wifi" : "wifi.slash")
                            .foregroundColor(reachability.isOnline ? .green : .red)
                        Text(reachability.isOnline ? "Online" : "Offline — will sync when connection returns")
                            .font(.subheadline)
                    }
                    Button {
                        Task { await retryAll() }
                    } label: {
                        Label("Retry all now", systemImage: "arrow.clockwise")
                    }
                    .disabled(!reachability.isOnline)
                }

                let crmRows = crmQueue.pendingForCurrentUser()
                if !crmRows.isEmpty {
                    Section("CRM") {
                        ForEach(crmRows) { row in
                            CRMPendingRow(row: row)
                        }
                    }
                }

                let attRows = attendance.pendingForCurrentUser()
                if !attRows.isEmpty {
                    Section("Attendance") {
                        ForEach(attRows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.kind.capitalized).font(.headline)
                                    Spacer()
                                    Text(Self.timeFmt.localizedString(for: row.createdAt, relativeTo: Date()))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                if let err = row.lastError {
                                    Text(err).font(.caption2).foregroundColor(.red)
                                }
                            }
                        }
                    }
                }

                let dist = orderCache.pendingForCurrentUser()
                if !(dist.orders.isEmpty && dist.payments.isEmpty && dist.returns.isEmpty) {
                    Section("Distribution") {
                        ForEach(dist.orders) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Order @ \(row.outletName ?? "outlet")").font(.headline)
                                    Spacer()
                                    Text(Self.timeFmt.localizedString(for: row.createdAt, relativeTo: Date()))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                if let err = row.lastError {
                                    Text(err).font(.caption2).foregroundColor(.red)
                                }
                            }
                        }
                        ForEach(dist.payments) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Payment").font(.headline)
                                    Spacer()
                                    Text(Self.timeFmt.localizedString(for: row.createdAt, relativeTo: Date()))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                if let err = row.lastError {
                                    Text(err).font(.caption2).foregroundColor(.red)
                                }
                            }
                        }
                        ForEach(dist.returns) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Return").font(.headline)
                                    Spacer()
                                    Text(Self.timeFmt.localizedString(for: row.createdAt, relativeTo: Date()))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                if let err = row.lastError {
                                    Text(err).font(.caption2).foregroundColor(.red)
                                }
                            }
                        }
                    }
                }

                if crmRows.isEmpty && attRows.isEmpty && dist.orders.isEmpty && dist.payments.isEmpty && dist.returns.isEmpty {
                    Section { Text("Nothing pending. You're up to date.").foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Pending sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func retryAll() async {
        NetworkReachability.shared.triggerGlobalFlush()
    }
}

// MARK: - CRM row

private struct CRMPendingRow: View {
    let row: PendingCRMMutation
    private static let timeFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(row.entityType.rawValue.capitalized) · \(row.operation.rawValue)")
                    .font(.headline)
                Spacer()
                Text(Self.timeFmt.localizedString(for: row.createdAt, relativeTo: Date()))
                    .font(.caption).foregroundColor(.secondary)
            }
            if row.permanentFailure {
                Text("Failed permanently")
                    .font(.caption2).foregroundColor(.red)
            } else if row.attempt > 0 {
                Text("Attempt \(row.attempt) of 5")
                    .font(.caption2).foregroundColor(.orange)
            }
            if let err = row.lastError {
                Text(err).font(.caption2).foregroundColor(.red).lineLimit(2)
            }
            HStack(spacing: 12) {
                Button("Retry") {
                    Task { await CRMSyncEngine.shared.retry(row.id) }
                }
                .font(.caption).foregroundColor(.blue)
                Button("Delete", role: .destructive) {
                    CRMWriteQueue.shared.remove(row.id)
                }
                .font(.caption)
            }
            .padding(.top, 2)
        }
    }
}

#Preview {
    OfflineStatusBanner()
}
