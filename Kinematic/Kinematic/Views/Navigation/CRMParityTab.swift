import SwiftUI

/// Tiny launcher that mirrors the Android "CRM tab" surface. Lives next to
/// ParityViews.swift so the navigation reads as one unit. Used by HomeView /
/// any future tab wiring that wants a non-modal entry point. The side-menu
/// CRM button uses a fullScreenCover; this view enables future inline tab
/// promotion without further edits.
struct CRMParityTab: View {
    var body: some View {
        NavigationStack {
            CRMHomeView()
        }
    }
}

/// Compact dashboard tile for HomeView — drop-in launcher for CRM.
struct CRMQuickTile: View {
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                    Image(systemName: "person.2.crop.square.stack.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 20, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("CRM")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(uiColor: .label))
                    Text("Leads, deals, pipeline & KINI assistant")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $presented) {
            NavigationStack {
                CRMHomeView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { presented = false }
                        }
                    }
            }
        }
    }
}
