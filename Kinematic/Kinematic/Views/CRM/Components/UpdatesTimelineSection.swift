//
//  UpdatesTimelineSection.swift
//  Kinematic CRM
//
//  Append-only Updates timeline on a lead detail screen. Mirrors the
//  dashboard's `LeadUpdatesTimeline.tsx` — a textarea composer at the
//  top plus a chronological list of timestamped entries beneath. The
//  posted body is stamped server-side with the current user's id +
//  display name and denormalised onto the lead's `latest_update*`
//  fields so the leads list can render a one-liner preview.
//

import SwiftUI

struct UpdatesTimelineSection: View {
    @ObservedObject var vm: LeadDetailViewModel
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    private let maxLen = 2000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(Brand.red)
                Text("UPDATES")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.secondary)
                if !vm.updates.isEmpty {
                    Text("· \(vm.updates.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            composer
            list
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ZStack(alignment: .topLeading) {
                // SwiftUI's TextField with axis: .vertical is the
                // multi-line composer iOS 16+; falls back to TextEditor
                // shape via the same look-and-feel.
                TextField("", text: $draft, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focused)
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focused ? Brand.red.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                if draft.isEmpty {
                    Text("Log an update — \"Called, asked for follow-up Friday.\" Feeds the next-best-action recommender.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 10) {
                Text("\(draft.count)/\(maxLen)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    Task {
                        let ok = await vm.postUpdate(body: draft)
                        if ok {
                            draft = ""
                            focused = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if vm.updatesPosting {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(vm.updatesPosting ? "Saving…" : "Add update")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(canSubmit ? Brand.red : Brand.red.opacity(0.45))
                    .cornerRadius(8)
                }
                .disabled(!canSubmit)
            }
        }
    }

    private var canSubmit: Bool {
        !vm.updatesPosting
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.count <= maxLen
    }

    @ViewBuilder
    private var list: some View {
        if vm.updatesLoading && vm.updates.isEmpty {
            HStack { Spacer(); ProgressView().controlSize(.small).tint(Brand.red); Spacer() }
                .padding(.vertical, 12)
        } else if vm.updates.isEmpty {
            Text("No updates yet. Add the first one above — recent updates are fed into the next-best-action recommender.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 8) {
                ForEach(vm.updates) { update in
                    UpdateRow(update: update)
                }
            }
        }
    }
}

private struct UpdateRow: View {
    let update: LeadUpdate

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Brand.red.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text(initials)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(Brand.red)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(update.authorName ?? "Someone")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(uiColor: .label))
                    if let rel = relative {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(rel)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Text(update.body)
                    .font(.system(size: 13))
                    .foregroundColor(Color(uiColor: .label).opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
    }

    private var initials: String {
        guard let name = update.authorName, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private var relative: String? {
        guard let at = update.createdAt,
              let date = UpdateRow.iso.date(from: at) ?? UpdateRow.isoFallback.date(from: at)
        else { return nil }
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3600))h ago" }
        if elapsed < 604_800 { return "\(Int(elapsed / 86_400))d ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
