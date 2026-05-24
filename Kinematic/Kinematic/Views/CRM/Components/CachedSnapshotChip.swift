//
//  CachedSnapshotChip.swift
//  Kinematic CRM
//
//  Small "Cached · Xm ago" chip rendered atop list views when the data
//  on screen came from the on-disk read cache rather than a fresh
//  network response. The ViewModel sets `showingCached = true` on
//  cache-hit at init and flips it off after the first successful
//  network refresh. Chip stays visible through subsequent network
//  failures so the rep keeps knowing the data is stale.
//

import SwiftUI

struct CachedSnapshotChip: View {
    /// True when the list is rendering from cache. Hidden when false.
    let showing: Bool
    /// Timestamp the cache was last refreshed (driven by CRMReadCache).
    /// Used to render the relative-time suffix. nil suppresses the suffix.
    let lastFetched: Date?

    var body: some View {
        if showing {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .imageScale(.small)
                Text(lastFetched.map { "Cached · \(Self.relative($0))" } ?? "Cached")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }

    private static let rtFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static func relative(_ d: Date) -> String {
        rtFormatter.localizedString(for: d, relativeTo: Date())
    }
}
