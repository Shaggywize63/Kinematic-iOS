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

    /// The entries below Dashboard in the order the built-in menu has always drawn them. Dashboard (first) and Settings (last)
    /// are fixed and not part of the list. Each entry's package / module / tenant gate and hide flag live in
    /// `ClientFeatures.menuEntryAllowed`, which the bottom bar's action tabs share.
    private static let defaultMenuOrder: [String] = [
        "crm", "planogram", "book_order", "collect_payment", "my_orders", "van_load", "distributor_stock", "log_damage",
        "stock_batches", "profile", "leave", "expenses", "timeline", "broadcast", "notifications",
        "leaderboard", "activity_feed", "log_visit", "stock", "grievance", "learning_hub", "emergency_sos",
    ]

    /// The entries to draw, in the admin's order (`app_ui_config.layout.menu`: listed ids first, the rest in the built-in
    /// order). Hide flags and the gates still win, and a screen the bottom bar already shows is not repeated here.
    private var orderedMenuIds: [String] {
        let inBar = BottomBarPlan.menuIdsInBar(ClientFeatures.layoutBarTabs())
        let shown = Self.defaultMenuOrder.filter { ClientFeatures.menuEntryAllowed($0) && !inBar.contains($0) }
        return ClientFeatures.ordered(shown, section: "menu", id: { $0 })
    }

    /// One side-menu row that opens a sheet through the shared secondary-route mechanism.
    private func routeRow(_ id: String, icon: String, title: String, color: Color, route: SecondaryRoute) -> some View {
        MenuButton(icon: icon, title: ClientFeatures.labelFor("menu", id, default: title), isSelected: false, color: color) {
            withAnimation { isOpen = false }
            appState.activeSecondaryRoute = ModalRoute(route: route)
        }
    }

    @ViewBuilder
    private func menuRow(_ id: String) -> some View {
        switch id {
        case "crm":
            // CRM Module — only visible to clients who own the CRM SKU.
            if let a = NavActions.action("crm") {
                MenuButton(icon: a.icon, title: a.title, isSelected: false, color: a.color) {
                    withAnimation { isOpen = false }
                    // Defer presentation until the menu close animation finishes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showCRM = true
                    }
                }
            }

        case "planogram":
            // Planogram (MoiSoi) — one-tap storeless shelf capture.
            // Opens the camera directly, submits with no store /
            // outlet / planogram selection; the backend scores it
            // against the org's active planogram. Only MoiSoi sees
            // this entry; other clients capture planograms inside a
            // store visit.
            MenuButton(icon: "camera.viewfinder", title: ClientFeatures.labelFor("menu", "planogram", default: "Planogram"), isSelected: false, color: Brand.red) {
                withAnimation { isOpen = false }
                // Defer presentation until the menu close animation finishes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showPlanogram = true
                }
            }

        case "my_orders":
            // Shows how many orders / payments / returns are saved on the phone waiting to upload.
            MyOrdersMenuButton(isOpen: $isOpen)

        // Van Load (module distribution_van) — day-start load-in + end-of-day reconcile. Ships OFF by default; only
        // shown when the client's enabled_modules includes the module.
        case "van_load":
            routeRow("van_load", icon: "truck.box.fill", title: "Van Load", color: .indigo, route: .vanLoad)

        // Distributor Stock (module distribution_stock) — read-only per-SKU on-hand view. Same module-gated rule.
        case "distributor_stock":
            routeRow("distributor_stock", icon: "archivebox.fill", title: "Distributor Stock", color: .brown, route: .distributorStock)

        // Log Damage (module distribution_damage) — distributor damaged / expiry register. Same module-gated rule.
        case "log_damage":
            routeRow("log_damage", icon: "exclamationmark.triangle.fill", title: "Log Damage", color: .orange, route: .damageLog)

        // Stock & Batches (module distribution_batches) — Supply Chain FEFO batch / expiry view + Receive (GRN). STRICT
        // entitlement gate (ClientFeatures.hasDistributionBatches): an empty legacy-session module list must NOT surface
        // this, so enabled_modules is read directly. Off by default.
        case "stock_batches":
            routeRow("stock_batches", icon: "calendar.badge.exclamationmark", title: "Stock & Batches", color: .purple, route: .stockBatches)

        case "profile":
            routeRow("profile", icon: "person.fill", title: "My Profile", color: .orange, route: .profile)

        // Expense claims (module `field_expenses`, off by default). STRICT entitlement: only clients explicitly granted the
        // module see it. This is the path for field-force tenants, which have no CRM "More" tab; CRM tenants also have it there.
        case "expenses":
            routeRow("expenses", icon: "receipt", title: "Expenses", color: .green, route: .expenses)

        case "leaderboard":
            routeRow("leaderboard", icon: "trophy.fill", title: "Leaderboard", color: .yellow, route: .leaderboard)

        case "activity_feed":
            routeRow("activity_feed", icon: "doc.text.fill", title: "Activity Feed", color: Brand.red, route: .activity)

        case "stock":
            routeRow("stock", icon: "shippingbox.fill", title: "Stock", color: .brown, route: .stock)

        case "grievance":
            routeRow("grievance", icon: "exclamationmark.bubble.fill", title: "Grievance", color: Brand.red, route: .grievance)

        case "learning_hub":
            routeRow("learning_hub", icon: "sparkles", title: "Learning Hub", color: Brand.red, route: .learning)

        case "emergency_sos":
            routeRow("emergency_sos", icon: "exclamationmark.octagon.fill", title: "Emergency SOS", color: .red, route: .sos)

        default:
            // Book Order / Collect Payment (book or collect for ANY outlet in scope, outlet picker first), Leave (+ attendance
            // regularization), Timeline, Broadcasts, Notifications, Visit Log: the screens that can also sit in the bottom bar.
            // One table (NavActions) names their symbol, label and destination for both places.
            if let a = NavActions.action(id), case .route(let route) = a.target {
                routeRow(id, icon: a.icon, title: a.defaultTitle, color: a.color, route: route)
            }
        }
    }

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

                    // Every entry below Dashboard is drawn from `orderedMenuIds`: the built-in order, moved by the layout the
                    // admin arranged in Client Management (listed ids first). Dashboard stays first; Settings and Sign Out
                    // stay where they are.
                    ForEach(orderedMenuIds, id: \.self) { id in
                        menuRow(id)
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
