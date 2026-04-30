import SwiftUI

struct SideMenuView: View {
    @ObservedObject var appState = KiniAppState.shared
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
        .allowsHitTesting(isOpen)
    }
    
    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Priority 1: Motivation Quote (Back at Top)
            quoteHeader
                .padding(.top, safeAreaInsets.top + 20)
                .padding(.leading, 60)
                .padding(.trailing, 24)
            
            Spacer().frame(height: 24)
            
            // Priority 2: User Identity
            userHeader
                .padding(.leading, 60)
                .padding(.trailing, 24)
            
            Spacer().frame(height: 32)
            
            // Priority 3: Navigation Menu
            VStack(spacing: 8) {
                MenuButton(icon: "house.fill", title: "Dashboard", isSelected: appState.selectedTab == 0, color: .blue) {
                    withAnimation { isOpen = false; appState.selectedTab = 0 }
                }
                
                MenuButton(icon: "person.fill", title: "My Profile", isSelected: false, color: .orange) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .profile)
                }
                
                MenuButton(icon: "megaphone.fill", title: "Broadcasts", isSelected: false, color: .red) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .broadcast)
                }

                MenuButton(icon: "bell.fill", title: "Notifications", isSelected: false, color: .indigo) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .notifications)
                }

                MenuButton(icon: "trophy.fill", title: "Leaderboard", isSelected: false, color: .yellow) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .leaderboard)
                }

                MenuButton(icon: "doc.text.fill", title: "Activity Feed", isSelected: false, color: .teal) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .activity)
                }

                MenuButton(icon: "list.bullet.rectangle", title: "Visit Log", isSelected: false, color: .green) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .visitlog)
                }

                MenuButton(icon: "shippingbox.fill", title: "Stock", isSelected: false, color: .brown) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .stock)
                }

                MenuButton(icon: "exclamationmark.bubble.fill", title: "Grievance", isSelected: false, color: .pink) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .grievance)
                }

                MenuButton(icon: "sparkles", title: "Learning Hub", isSelected: false, color: .purple) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .learning)
                }

                MenuButton(icon: "exclamationmark.octagon.fill", title: "Emergency SOS", isSelected: false, color: .red) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .sos)
                }

                MenuButton(icon: "gearshape.fill", title: "Settings", isSelected: false, color: .gray) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .settings)
                }
            }
            .padding(.leading, 44) // 44 + 16 (MenuButton padding) = 60px Leading alignment
            .padding(.trailing, 12)
            
            Spacer()
            
            Divider()
                .padding(.leading, 60)
                .padding(.trailing, 24)
                .padding(.bottom, 15)
            
            // Sign Out at bottom
            MenuButton(icon: "power", title: "Sign Out", isSelected: false, color: .red) {
                withAnimation { isOpen = false; appState.logout() }
            }
            .padding(.leading, 44)
            .padding(.bottom, 30)
            
            // Version Info
            Text("Kinematic v1.0.9 (IRONCLAD)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray.opacity(0.4))
                .padding(.bottom, safeAreaInsets.bottom + 10)
                .padding(.leading, 60)
        }
        .frame(width: 320)
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea(.all, edges: .vertical)
    }
    
    private var userHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(Session.currentUser?.name.prefix(1).uppercased() ?? "K")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.white)
            }
            .frame(width: 50, height: 50)
            .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(Session.currentUser?.name ?? "User Name")
                    .font(.headline)
                    .fontWeight(.black)
                Text(Session.currentUser?.role.uppercased() ?? "FIELD EXECUTIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
            }
        }
    }
    
    private var quoteHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.red.opacity(0.4))
            
            Text(appState.quote?.quote ?? "Loading motivation...")
                .font(.system(size: 13, weight: .medium, design: .serif))
                .foregroundColor(Color(uiColor: .label))
                .italic()
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .label).opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var safeAreaInsets: UIEdgeInsets {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return .zero
        }
        return window.safeAreaInsets
    }
}

struct MenuButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var color: Color = .blue
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.gradient)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(uiColor: .label))
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? color.opacity(0.1) : Color.clear)
            .cornerRadius(12)
        }
    }
}
