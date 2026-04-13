import SwiftUI

struct SideMenuView: View {
    @ObservedObject var appState = AppState.shared
    @Binding var isOpen: Bool
    
    var body: some View {
        ZStack {
            if isOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { isOpen = false }
                    }
                
                HStack(spacing: 0) {
                    sidebarContent
                        .transition(.move(edge: .leading))
                    Spacer()
                }
            }
        }
    }
    
    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Quote (Parity with Android)
            quoteHeader
                .padding(.top, 60)
                .padding(.horizontal, 24)
            
            Spacer(minLength: 32)
            
            // Menu Items
            VStack(spacing: 8) {
                MenuButton(icon: "house.fill", title: "Home", isSelected: false) {
                    withAnimation { 
                        isOpen = false
                        appState.selectedTab = 0
                    }
                }
                
                MenuButton(icon: "person.fill", title: "Profile", isSelected: false) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = .profile
                }
                
                MenuButton(icon: "gearshape.fill", title: "Settings", isSelected: false) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = .settings
                }
                
                MenuButton(icon: "megaphone.fill", title: "Broadcast Messages", isSelected: false) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = .broadcast
                }
                
                MenuButton(icon: "book.fill", title: "Learning Hub", isSelected: false) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = .learning
                }
                
                MenuButton(icon: "plus.app.fill", title: "Log Visit", isSelected: false) {
                    withAnimation { 
                        isOpen = false
                        appState.selectedTab = 2 // Navigate to Route tab
                    }
                }
                
                Divider()
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                
                MenuButton(icon: "arrow.right.square.fill", title: "Sign Out", isSelected: false, color: .red) {
                    withAnimation { 
                        isOpen = false
                        appState.logout()
                    }
                }
            }
            .padding(.horizontal, 12)
            
            Spacer()
            
            // App Version Info
            Text("Kinematic v1.0.8 (Stable)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.gray.opacity(0.6))
                .padding(.bottom, 30)
                .padding(.horizontal, 24)
        }
        .frame(width: 300)
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea(.all, edges: .vertical)
    }
    
    private var quoteHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Glass Quotation Card
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "quote.opening")
                    .font(.title2)
                    .foregroundColor(.red.opacity(0.6))
                
                Text(appState.quote?.quote ?? "Loading motivation...")
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundColor(Color(uiColor: .label))
                    .italic()
                    .lineSpacing(4)
                
                HStack {
                    Spacer()
                    Text("- \(appState.quote?.author ?? "Kinematic")")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .label).opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
}

struct MenuButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var color: Color = Color(uiColor: .label).opacity(0.8)
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
            .cornerRadius(12)
        }
    }
}
