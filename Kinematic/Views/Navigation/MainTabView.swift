import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var network: NetworkMonitor
    @State private var isSyncing = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab Contents
            TabView(selection: $selectedTab) {
                // Home Feed Tab
                HomeFeedSkeleton()
                    .tag(0)
                
                // Attendance Tab
                Color.kDark.ignoresSafeArea()
                    .overlay(Text("Attendance / Selfie").foregroundColor(.white))
                    .tag(1)
                
                // Routes Tab
                Color.kDark.ignoresSafeArea()
                    .overlay(Text("Route Plans").foregroundColor(.white))
                    .tag(2)
                
                // Settings Tab
                Color.kDark.ignoresSafeArea()
                    .overlay(Text("Settings & Profile").foregroundColor(.white))
                    .tag(3)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .ignoresSafeArea()
            
            // Custom Liquid Glass Bottom Navigation Bar
            CustomGlassTabBar(selectedTab: $selectedTab)
            
            // Floating Sync Status (Top Right)
            if isSyncing || !network.isConnected {
                notificationOverlay
            }
        }
        // AUTO-SYNC TRIGGER: Fires when network comes back online
        .onChange(of: network.isConnected) { oldValue, newValue in
            if newValue {
                Task { await triggerSync() }
            }
        }
    }
    
    private var notificationOverlay: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    if isSyncing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                        Text("Syncing Data...")
                    } else if !network.isConnected {
                        Image(systemName: "wifi.slash")
                        Text("Offline Mode")
                    }
                }
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .padding(.top, 50)
                .padding(.trailing, 20)
            }
            Spacer()
        }
    }
    
    private func triggerSync() async {
        isSyncing = true
        _ = await KinematicRepository.shared.syncPendingSubmissions(context: modelContext)
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Visual comfort
        isSyncing = false
    }
}

/// Floating Liquid Glass Navigation Bar
struct CustomGlassTabBar: View {
    @Binding var selectedTab: Int
    
    let tabs = [
        ("house.fill", "Home"),
        ("person.crop.circle.badge.checkmark", "Attendance"),
        ("map.fill", "Routes"),
        ("gearshape.fill", "Settings")
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = index
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].0)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tabs[index].1)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(selectedTab == index ? .kRed : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    // Subtle indicator behind selected icon
                    .background(
                        Circle()
                            .fill(selectedTab == index ? Color.kRed.opacity(0.15) : Color.clear)
                            .frame(width: 50, height: 50)
                            .blur(radius: 5)
                            .scaleEffect(selectedTab == index ? 1 : 0.5)
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .liquidGlass(cornerRadius: 30, opacity: 0.15, shadowRadius: 20)
        .padding(.horizontal, 24)
        .padding(.bottom, 34) // Safe area offset
    }
}

/// Skeleton View for the Home Feed replicating the Android design
struct HomeFeedSkeleton: View {
    var body: some View {
        ZStack {
            Color.kDark.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header Status
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Welcome back,")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Text("Field Executive")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                        }
                        Spacer()
                        
                        // Fake Network/Sync icon
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "checkmark.icloud.fill")
                                    .foregroundColor(.green)
                            )
                    }
                    .padding(.horizontal)
                    .padding(.top, 60)
                    
                    // Stats / Analytics Grid
                    HStack(spacing: 16) {
                        StatCard(title: "Outlets Visited", value: "12 / 24", icon: "storefront.fill", color: .kGradient2)
                        StatCard(title: "Forms Submitted", value: "8", icon: "doc.text.fill", color: .kGradient4)
                    }
                    .padding(.horizontal)
                    
                    // Task Feed Skeleton
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Today's Pending Tasks")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        ForEach(0..<3) { _ in
                            TaskRowCard()
                        }
                    }
                    .padding(.top, 10)
                    
                    Spacer()
                        .frame(height: 120) // Padding for bottom nav
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .liquidGlass(cornerRadius: 16, opacity: 0.1)
    }
}

struct TaskRowCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.kRed.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "mappin.circle.fill").foregroundColor(.kRed))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Retail Store Check")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Complete merchandising audit")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding()
        .liquidGlass(cornerRadius: 16, opacity: 0.05)
        .padding(.horizontal)
    }
}

#Preview {
    MainTabView()
}
