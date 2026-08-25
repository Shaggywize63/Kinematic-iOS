import SwiftUI

struct SideMenuView: View {
    @ObservedObject var appState = KiniAppState.shared
    @Binding var isOpen: Bool
    /// CRM is presented as its own full-screen module (mirrors Distribution).
    /// We keep a local presentation flag because `SecondaryRoute` lives in
    /// KinematicApp.swift and we don't want to patch that large file just to
    /// add one route case.
    @State private var showCRM = false
    /// MoiSoi's one-tap planogram capture is presented full-screen from here
    /// (mirrors `showCRM`) so the self-contained `PlanogramCaptureView` isn't
    /// double-wrapped in a navigation chrome.
    @State private var showPlanogram = false

    /// Per-client SKU snapshot for nav gating. Refreshes whenever Session.currentUser changes.
    private var hasCrm: Bool         { Session.currentUser?.hasCrm ?? true }
    private var hasFieldForce: Bool  { Session.currentUser?.hasFieldForce ?? true }
    private var hasDistribution: Bool { Session.currentUser?.hasDistribution ?? true }
    private func hasModule(_ id: String) -> Bool { Session.currentUser?.hasModule(id) ?? true }

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
        .fullScreenCover(isPresented: $showCRM) {
            // CRMTabView is the dedicated CRM module shell — 5 bottom tabs
            // (Dashboard / Leads / Pipeline / Activities / More). The "More"
            // tab's "Switch to Field Force" row uses the onExit callback
            // below to dismiss the sheet, mirroring the dashboard's CRM
            // section behaviour.
            CRMTabView(onExit: { showCRM = false })
        }
        .fullScreenCover(isPresented: $showPlanogram) {
            // Storeless shelf capture: no outlet/store/planogram selection. The
            // backend scores it against the org's active planogram. Reuses the
            // exact capture pipeline used inside a store visit.
            PlanogramCaptureView(storeId: nil, visitId: nil, planogramId: nil)
        }
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
            ScrollView {
                VStack(spacing: 8) {
                    MenuButton(icon: "house.fill", title: "Dashboard", isSelected: appState.selectedTab == 0, color: Brand.red) {
                        withAnimation { isOpen = false; appState.selectedTab = 0 }
                    }

                    // ── CRM Module — only visible to clients who own the CRM SKU ──
                    if hasCrm {
                        MenuButton(icon: "person.2.crop.square.stack.fill", title: "CRM", isSelected: false, color: Brand.red) {
                            withAnimation { isOpen = false }
                            // Defer presentation until the menu close animation finishes
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showCRM = true
                            }
                        }
                    }

                    // ── Planogram (MoiSoi) — one-tap storeless shelf capture.
                    //    Opens the camera directly, submits with no store /
                    //    outlet / planogram selection; the backend scores it
                    //    against the org's active planogram. Only MoiSoi sees
                    //    this entry; other clients capture planograms inside a
                    //    store visit.
                    if ClientFeatures.isMoiSoi {
                        MenuButton(icon: "camera.viewfinder", title: "Planogram", isSelected: false, color: Brand.red) {
                            withAnimation { isOpen = false }
                            // Defer presentation until the menu close animation finishes.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showPlanogram = true
                            }
                        }
                    }

                    // ── Distribution / Van Sales — only visible to clients who
                    //    own the distribution SKU. Opens the order history sheet
                    //    via the same SecondaryRoute mechanism the other rows use;
                    //    SecondaryScreenHost re-checks the package gate.
                    if hasDistribution {
                        MenuButton(icon: "cart.fill", title: "My Orders", isSelected: false, color: .indigo) {
                            withAnimation { isOpen = false }
                            appState.activeSecondaryRoute = ModalRoute(route: .orderHistory)
                        }
                    }

                    // ── Van Load (module distribution_van) — day-start load-in +
                    //    end-of-day reconcile. Ships OFF by default; only shown
                    //    when the client's enabled_modules includes the module.
                    if hasModule("distribution_van") {
                        MenuButton(icon: "truck.box.fill", title: "Van Load", isSelected: false, color: .indigo) {
                            withAnimation { isOpen = false }
                            appState.activeSecondaryRoute = ModalRoute(route: .vanLoad)
                        }
                    }

                    // ── Distributor Stock (module distribution_stock) — read-only
                    //    per-SKU on-hand view. Same module-gated OFF-by-default rule.
                    if hasModule("distribution_stock") {
                        MenuButton(icon: "archivebox.fill", title: "Distributor Stock", isSelected: false, color: .brown) {
                            withAnimation { isOpen = false }
                            appState.activeSecondaryRoute = ModalRoute(route: .distributorStock)
                        }
                    }

                    // ── Log Damage (module distribution_damage) — distributor
                    //    damaged / expiry register. Same module-gated OFF-by-default rule.
                    if hasModule("distribution_damage") {
                        MenuButton(icon: "exclamationmark.triangle.fill", title: "Log Damage", isSelected: false, color: .orange) {
                            withAnimation { isOpen = false }
                            appState.activeSecondaryRoute = ModalRoute(route: .damageLog)
                        }
                    }

                    MenuButton(icon: "person.fill", title: "My Profile", isSelected: false, color: .orange) {
                        withAnimation { isOpen = false }
                        appState.activeSecondaryRoute = ModalRoute(route: .profile)
                    }

                    // Leave management + attendance regularization. Shown to
                    // every client except SRS TATA Steel (slimmed build); the
                    // API/role decides what's actionable for the rest.
                    if ClientFeatures.showsLeave {
                        MenuButton(icon: "calendar.badge.clock", title: "Leave", isSelected: false, color: .teal) {
                            withAnimation { isOpen = false }
                            appState.activeSecondaryRoute = ModalRoute(route: .leave)
                        }
                    }

                if hasModule("broadcast") {
                    MenuButton(icon: "megaphone.fill", title: "Broadcasts", isSelected: false, color: .red) {
                        withAnimation { isOpen = false }
                        appState.activeSecondaryRoute = ModalRoute(route: .broadcast)
                    }
                }

                MenuButton(icon: "bell.fill", title: "Notifications", isSelected: false, color: Brand.red) {
                    withAnimation { isOpen = false }
                    appState.activeSecondaryRoute = ModalRoute(route: .notifications)
                }

                if hasFieldForce {
                    MenuButton(icon: "trophy.fill", title: "Leaderboard", isSelected: false, color: .yellow) {
                        withAnimation { isOpen = false }
                        appState.activeSecondaryRoute = ModalRoute(route: .leaderboard)
                    }

                    MenuButton(icon: "doc.text.fill", title: "Activity Feed", isSelected: false, color: Brand.red) {
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
                }

                if hasModule("grievances") {
                    MenuButton(icon: "exclamationmark.bubble.fill", title: "Grievance", isSelected: false, color: Brand.red) {
                        withAnimation { isOpen = false }
                        appState.activeSecondaryRoute = ModalRoute(route: .grievance)
                    }
                }

                MenuButton(icon: "sparkles", title: "Learning Hub", isSelected: false, color: Brand.red) {
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
            }
            
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
            
            // Version Info — always the real bundle version, never a hardcoded string.
            Text("Kinematic v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
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
    var color: Color = Brand.red
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
