import SwiftUI
import Combine
import CoreLocation

// --- DESIGN SYSTEM (Liquid Glass) ---
extension View {
    func liquidGlass(cornerRadius: CGFloat = 20, opacity: Double = 0.05) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: Double
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// --- VIEWS ---
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if !appState.isAuthenticated {
            LoginView(onSuccess: { appState.checkAuth() })
        } else {
            MainTabView()
        }
    }
}



struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @Namespace private var animation // For Matched Geometry (Liquid Pod)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Global Content Switcher
            Group {
                switch appState.selectedTab {
                case 0: HomeView().id("home")
                case 1: AttendanceView().id("attendance")
                case 2: RoutePlansView().id("route")
                default: HomeView().id("default")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Removed .ignoresSafeArea() to fix top overlap on Dynamic Island devices
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
            
            .offset(y: appState.isTabBarExpanded ? 0 : 10)
            
            // 2025 High-Refraction Liquid Island (Adaptive Morphing)
            HStack(spacing: appState.isTabBarExpanded ? 0 : 20) {
                TabBtn(i: "house", l: "Home", s: appState.selectedTab == 0, ex: appState.isTabBarExpanded, ns: animation) { 
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 25)) { appState.selectedTab = 0 }
                }
                TabBtn(i: "person.text.rectangle", l: "Attendance", s: appState.selectedTab == 1, ex: appState.isTabBarExpanded, ns: animation) { 
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 25)) { appState.selectedTab = 1 }
                }
                TabBtn(i: "map", l: "Route", s: appState.selectedTab == 2, ex: appState.isTabBarExpanded, ns: animation) { 
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 25)) { appState.selectedTab = 2 }
                }
            }
            .padding(.horizontal, appState.isTabBarExpanded ? 14 : 20)
            .padding(.vertical, appState.isTabBarExpanded ? 12 : 10)
            .background(.regularMaterial, in: MirrorGlassTabBarShape())
            .overlay {
                MirrorGlassTabBarShape()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
            .scaleEffect(appState.isTabBarExpanded ? 1.0 : 0.94)
            .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
            .padding(.horizontal, 24)
            .padding(.bottom, appState.isTabBarExpanded ? 34 : 20)
            .offset(y: appState.isTabBarExpanded ? 0 : 10)
            
            // Global Store Visit Overlay (Absolute top z-index)
            if appState.selectedOutlet != nil {
                StoreVisitView()
                    .transition(.move(edge: .bottom))
                    .zIndex(100)
            }
            
            // Side Menu Overlay
            SideMenuView(isOpen: $appState.showSideMenu)
        }
        .allowsHitTesting(true)
        .fullScreenCover(item: $appState.activeSecondaryRoute) { route in
            SecondaryScreenHost(route: route)
        }
        .sheet(isPresented: $appState.attendanceVM.showCamera) {
            ImagePicker(image: $appState.attendanceVM.selfie)
                .ignoresSafeArea()
        }
    }
}

struct TabBtn: View {
    let i: String; let l: String; let s: Bool; let ex: Bool
    let ns: Namespace.ID
    let a: () -> Void
    
    var body: some View {
        Button(action: a) {
            VStack(spacing: ex ? 6 : 0) {
                ZStack {
                    if s {
                        Capsule()
                            .fill(.thickMaterial)
                            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                            .matchedGeometryEffect(id: "pod", in: ns)
                            .frame(width: ex ? 54 : 50, height: ex ? 36 : 32)
                            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                    }
                    
                    VStack(spacing: 0) {
                        Image(systemName: s ? "\(i).fill" : i)
                            .font(.system(size: ex ? 20 : 18, weight: s ? .black : .bold))
                            .foregroundStyle(
                                s ? 
                                LinearGradient(colors: [.white, .blue], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient(colors: [.gray.opacity(0.6), .gray.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                            )
                            .scaleEffect(s ? (ex ? 1.25 : 1.15) : 1.0)
                            .shadow(color: s ? .blue.opacity(0.4) : .clear, radius: 10)
                    }
                }
                
                if ex {
                    Text(l)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(s ? Color.blue : Color.gray.opacity(0.6))
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MirrorGlassTabBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .path(in: rect)
    }
}

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject var vm = HomeViewModel()

    var body: some View {
        ZStack {
            VibrantBackgroundView()
            ScrollView {
                VStack(spacing: 20) {
                    // App Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Kinematic")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(Color(uiColor: .label))
                            Text("Field Operations Hub")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .tracking(0.5)
                        }
                        Spacer()
                        Button(action: { withAnimation { appState.showSideMenu = true } }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(uiColor: .label))
                                .frame(width: 40, height: 40)
                                .background(.regularMaterial, in: Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Summary Info Row
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Summary")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(Session.currentUser?.name ?? "Field Executive")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(Color(uiColor: .label))
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Button(action: { Task { await vm.refresh() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 36, height: 36)
                                    .background(.regularMaterial, in: Circle())
                                    .foregroundColor(Color(uiColor: .label))
                            }
                            Button(action: { appState.logout() }) {
                                Image(systemName: "power")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 36, height: 36)
                                    .background(Color.red.opacity(0.12), in: Circle())
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Selfie Status Card
                    SelfieStatusCard(record: appState.today)
                        .padding(.horizontal, 20)

                    // Stats Row
                    HStack(spacing: 10) {
                        StatTile(label: "Stores", value: "\(vm.totalStoreCount)", icon: "storefront.fill", color: .blue)
                        StatTile(label: "Visited", value: "\(vm.visitedStoreCount)", icon: "checkmark.seal.fill", color: .green)
                        StatTile(label: "Forms", value: "\(vm.data?.summary?.tffCount ?? 0)", icon: "doc.text.fill", color: .purple)
                    }
                    .padding(.horizontal, 20)

                    // Today's Session
                    SessionCard(record: appState.today)
                        .padding(.horizontal, 20)

                    // Broadcast / Announcement Card
                    if vm.showSubmissionSuccess {
                        HStack(spacing: 15) {
                            ZStack {
                                Circle().fill(Color.green.opacity(0.15)).frame(width: 44, height: 44)
                                Image(systemName: "checkmark.seal.fill").font(.title3).foregroundColor(.green)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Submission Successful!").font(.headline).foregroundColor(Color(uiColor: .label))
                                Text("Thank you for your response.").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(18)
                        .liquidGlass()
                        .padding(.horizontal, 20)
                        .transition(.scale.combined(with: .opacity))
                    } else if let b = vm.data?.broadcast, !(vm.data?.alreadyAnswered ?? b.alreadyAnswered) {
                        BroadcastCard(broadcast: b) { selectedIndex in
                            Task { await vm.submitBroadcastAnswer(id: b.id, selectedIndex: selectedIndex) }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Route Preview
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("TODAY'S ROUTE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(1)
                            Spacer()
                            Button(action: { appState.selectedTab = 2 }) {
                                Text("VIEW ALL")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        }

                        let previewOutlets = Array(vm.uniqueOutlets.prefix(3))

                        if !previewOutlets.isEmpty {
                            ForEach(previewOutlets) { outlet in
                                Button(action: {
                                    withAnimation(.spring()) {
                                        appState.selectedOutlet = outlet
                                        appState.selectedTab = 2
                                    }
                                }) {
                                    RoutePreviewRow(outlet: outlet)
                                }
                            }
                        } else {
                            Text("No stores assigned for today")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(18)
                    .liquidGlass()
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 110)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                appState.updateScrollProgress(newValue)
            }
            .refreshable { await vm.refresh() }
        }
        .onAppear { Task { await vm.refresh() } }
    }
}


struct SelfieStatusCard: View {
    @EnvironmentObject var appState: AppState
    let record: AttendanceRecord?
    var isIn: Bool { record?.checkinAt != nil && record?.checkoutAt == nil }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(isIn ? "Shift Active" : "Daily Selfie Required").font(.headline).foregroundColor(Color(uiColor: .label))
                if isIn {
                    Text("Ongoing since \(formatTime(record?.checkinAt))").font(.caption).foregroundColor(.gray)
                }
            }
            Spacer()
            
            Button(action: { 
                appState.attendanceVM.startFlow()
            }) {
                Text(isIn ? "Selfie Out" : "Selfie In")
                    .font(.caption).fontWeight(.bold).foregroundColor(.white)
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(isIn ? Color.red : Color.blue)
                    .cornerRadius(8)
            }
            .disabled(appState.attendanceVM.isLoading)
        }
        .padding(18)
        .liquidGlass()
    }
}

struct StatTile: View {
    let label: String; let value: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(color).font(.headline)
            VStack(spacing: 2) {
                Text(value).font(.title3).fontWeight(.black).foregroundColor(Color(uiColor: .label))
                Text(label).font(.system(size: 10)).foregroundColor(.gray).fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 15).liquidGlass()
    }
}

/// Live-updating session card — uses TimelineView so the elapsed timer
/// and progress ring refresh automatically without a manual Timer.
struct SessionCard: View {
    let record: AttendanceRecord?

    private var checkinDate: Date? { parseISO(record?.checkinAt) }
    private var checkoutDate: Date? { parseISO(record?.checkoutAt) }

    var body: some View {
        if checkinDate != nil {
            // Always tick every second; SessionCardContent uses checkoutDate when
            // present so the display freezes naturally without stopping the view.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                SessionCardContent(
                    checkinDate: checkinDate,
                    checkoutDate: checkoutDate,
                    now: context.date
                )
            }
        } else {
            SessionCardContent(checkinDate: nil, checkoutDate: nil, now: .now)
        }
    }

    private func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

struct SessionCardContent: View {
    let checkinDate: Date?
    let checkoutDate: Date?
    let now: Date

    private var isActive: Bool { checkinDate != nil && checkoutDate == nil }
    private var endDate: Date { checkoutDate ?? now }

    private var elapsed: TimeInterval {
        guard let ci = checkinDate else { return 0 }
        return max(0, endDate.timeIntervalSince(ci))
    }
    private var progress: Double { min(elapsed / (8 * 3600), 1.0) }

    private var elapsedLabel: String {
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("TODAY'S SESSION")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                if checkinDate != nil {
                    HStack(spacing: 4) {
                        if isActive {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                        }
                        Text(isActive ? "ACTIVE" : "COMPLETED")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(isActive ? .green : .secondary)
                    }
                }
            }

            if let ci = checkinDate {
                HStack(spacing: 16) {
                    // Progress Ring
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                LinearGradient(
                                    colors: progress >= 1.0 ? [.green, .mint] : [.red, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.6), value: progress)

                        VStack(spacing: 1) {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(Color(uiColor: .label))
                                .contentTransition(.numericText())
                            Text("of 8h")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 72, height: 72)

                    // Time details
                    VStack(alignment: .leading, spacing: 10) {
                        SessionTimeRow(
                            label: "Check-In",
                            value: ci.formatted(date: .omitted, time: .shortened),
                            icon: "arrow.right.circle.fill",
                            color: .green
                        )
                        if let co = checkoutDate {
                            SessionTimeRow(
                                label: "Check-Out",
                                value: co.formatted(date: .omitted, time: .shortened),
                                icon: "arrow.left.circle.fill",
                                color: .red
                            )
                        } else {
                            SessionTimeRow(
                                label: "Elapsed",
                                value: elapsedLabel,
                                icon: "timer",
                                color: .orange
                            )
                        }
                    }

                    Spacer()
                }

                // Linear progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 6)
                        Capsule()
                            .fill(LinearGradient(
                                colors: progress >= 1.0 ? [.green, .mint] : [.red, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(progress), height: 6)
                            .animation(.easeInOut(duration: 0.4), value: progress)
                    }
                }
                .frame(height: 6)

            } else {
                // No session yet
                HStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No active session")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(Color(uiColor: .label))
                        Text("Check in to start tracking your shift")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .liquidGlass()
    }
}

struct SessionTimeRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(uiColor: .label))
                    .contentTransition(.numericText())
            }
        }
    }
}

struct BroadcastCard: View {
    let broadcast: BroadcastQuestion
    let onAnswer: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "megaphone.fill").font(.caption)
                    Text("ANNOUNCEMENT").font(.system(size: 10, weight: .bold)).tracking(1)
                }
                .foregroundColor(broadcast.isUrgent ? .red : .blue)
                Spacer()
                if broadcast.alreadyAnswered {
                    Text("ANSWERED").font(.system(size: 8, weight: .bold)).padding(4).background(Color.green.opacity(0.2)).foregroundColor(.green).cornerRadius(4)
                }
            }
            
            Text(broadcast.question)
                .font(.subheadline).fontWeight(.bold).foregroundColor(Color(uiColor: .label)).lineLimit(3)
            
            if !broadcast.alreadyAnswered {
                VStack(spacing: 8) {
                    ForEach(Array(broadcast.options.prefix(3).enumerated()), id: \.element.value) { index, opt in
                        Button(action: { onAnswer(index) }) {
                            HStack {
                                Text(opt.label).font(.caption).foregroundColor(Color(uiColor: .label))
                                Spacer()
                                Image(systemName: "circle").font(.caption).foregroundColor(.gray)
                            }
                            .padding(10).background(Color(uiColor: .label).opacity(0.05)).cornerRadius(10)
                        }
                    }
                }
            }
        }
        .padding(20)
        .liquidGlass()
    }
}

struct RoutePreviewRow: View {
    let outlet: RouteOutlet
    var body: some View {
        HStack {
            Image(systemName: outlet.status == "visited" ? "checkmark.circle.fill" : "storefront")
                .foregroundColor(outlet.status == "visited" ? .green : .gray)
            VStack(alignment: .leading) {
                Text(outlet.storeName ?? "Unknown Store").font(.subheadline).fontWeight(.bold).foregroundColor(Color(uiColor: .label))
                if let activities = outlet.activities, !activities.isEmpty {
                    Text("\(activities.count) tasks assigned").font(.system(size: 10)).foregroundColor(.gray)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
        }
    }
}

// --- HELPERS ---
func formatTime(_ iso: String?) -> String {
    guard let iso = iso else { return "--:--" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: iso) {
        let df = DateFormatter()
        df.dateFormat = "hh:mm a"
        return df.string(from: date)
    }
    return iso.contains("T") ? String(iso.suffix(8).prefix(5)) : iso
}

struct RoutePlansView: View {
    @EnvironmentObject var appState: AppState
    @StateObject var vm = RoutePlansViewModel()
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            VStack(spacing: 0) {
                // Header (Adjusted for iPhone 17 Pro Safe Area)
                HStack {
                    Button(action: { withAnimation { appState.showSideMenu = true } }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(uiColor: .label))
                            .frame(width: 40, height: 40)
                            .background(.regularMaterial, in: Circle())
                    }
                    Text("Today's Route")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(Color(uiColor: .label))
                        .padding(.leading, 8)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Original Large Title (removed top padding to fit new header)
                        Text("Route Details").font(.largeTitle).fontWeight(.black).foregroundColor(Color(uiColor: .label)).padding(.horizontal)
                    
                    if vm.isLoading && vm.plans.isEmpty {
                        ProgressView().tint(.red).frame(maxWidth: .infinity).padding(.top, 50)
                    } else if vm.plans.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 50)).foregroundColor(.gray)
                            Text("No routes planned for today").foregroundColor(.gray)
                        }.frame(maxWidth: .infinity).padding(.top, 100)
                    } else {
                        ForEach(vm.plans) { plan in
                            ForEach(plan.outlets ?? []) { outlet in
                                OutletCard(outlet: outlet)
                            }
                        }
                    }
                    Spacer().frame(height: 120)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                appState.updateScrollProgress(newValue)
            }
            .refreshable { await vm.refresh() }
        }
        }
        .onAppear { Task { await vm.refresh() } }
    }
}

struct OutletCard: View {
    @EnvironmentObject var appState: AppState
    let outlet: RouteOutlet
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(outlet.storeName ?? "Unknown Store").font(.headline).foregroundColor(Color(uiColor: .label))
                Spacer()
                if outlet.status == "visited" {
                    Text("COMPLETED").font(.system(size: 8, weight: .bold)).padding(5).background(Color.green.opacity(0.2)).foregroundColor(.green).cornerRadius(5)
                }
            }
            Text(outlet.address ?? "No address provided").font(.caption).foregroundColor(.gray)
            
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "list.clipboard").font(.caption)
                    Text("\((outlet.activities ?? []).count) Tasks").font(.caption).fontWeight(.bold)
                }.foregroundColor(.purple)
                Spacer()
                Button(action: {
                    // Start Visit Action: Simply set selectedOutlet (Overlay handles visibility)
                    appState.selectedOutlet = outlet
                    // Removed selectedTab = 0 to fulfill request to stay in Route Plans
                }) {
                    Text(outlet.status == "visited" ? "View Details" : "Start Visit")
                        .font(.caption2).fontWeight(.black).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(outlet.status == "visited" ? Color.gray.opacity(0.2) : Color.red).foregroundColor(.white).cornerRadius(15)
                }
            }
            .padding(.top, 5)
        }
        .padding(20).liquidGlass().padding(.horizontal, 20)
    }
}

struct AttendanceView: View {
    @EnvironmentObject var appState: AppState
    var vm: AttendanceViewModel { appState.attendanceVM }
    @EnvironmentObject var locationService: LocationTrackingService
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            VStack(spacing: 0) {
                // Header (Adjusted for iPhone 17 Pro Safe Area)
                HStack {
                    Button(action: { withAnimation { appState.showSideMenu = true } }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(uiColor: .label))
                            .frame(width: 40, height: 40)
                            .background(.regularMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                ScrollView {
                    VStack(spacing: 25) {
                        Text("Attendance").font(.largeTitle).fontWeight(.black).foregroundColor(Color(uiColor: .label)).padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                    
                    // Main Status Card
                    VStack(spacing: 24) {
                        // Live Clock & Date
                        VStack(spacing: 4) {
                            Text(currentTime.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 44, weight: .black, design: .rounded))
                                .foregroundColor(Color(uiColor: .label))
                            Text(currentTime.formatted(date: .complete, time: .omitted))
                                .font(.caption).fontWeight(.bold).foregroundColor(.gray).textCase(.uppercase)
                        }
                        
                        // Selfie Preview / Capture
                        VStack(spacing: 12) {
                            Button(action: { vm.showCamera = true }) {
                                ZStack {
                                    Circle().fill(Color.white.opacity(0.05)).frame(width: 140, height: 140)
                                    if let img = vm.selfie {
                                        // Locally captured selfie (just taken this session)
                                        Image(uiImage: img)
                                            .resizable().aspectRatio(contentMode: .fill)
                                            .frame(width: 130, height: 130).clipShape(Circle())
                                    } else if let selfieUrl = appState.today?.checkinSelfieUrl,
                                              let url = URL(string: selfieUrl) {
                                        // Stored selfie from server (shown after app restart)
                                        AsyncImage(url: url) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                                .frame(width: 130, height: 130).clipShape(Circle())
                                        } placeholder: {
                                            ProgressView().tint(.gray).frame(width: 130, height: 130)
                                        }
                                    } else {
                                        VStack(spacing: 8) {
                                            Image(systemName: "camera.fill").font(.title).foregroundColor(.red)
                                            Text("Take Selfie").font(.caption2).fontWeight(.bold).foregroundColor(.gray)
                                        }
                                    }
                                }
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                            }
                            
                            // Simulator Fallback Button
                            if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button(action: { vm.useMockSelfie() }) {
                                    Label("Simulator: Use Mock", systemImage: "testtube.2")
                                        .font(.caption2).fontWeight(.black).padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.white.opacity(0.1)).foregroundColor(.white).cornerRadius(10)
                                }
                            }
                        }
                        
                        // Status Info
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Circle().fill(vm.today?.checkinAt != nil ? Color.green : Color.red).frame(width: 8, height: 8)
                                Text(vm.today?.checkinAt != nil ? "Shift: Active" : "Shift: Inactive")
                                    .font(.headline).foregroundColor(Color(uiColor: .label))
                            }
                            
                            if let loc = locationService.lastLocation {
                                Text(String(format: "Location: %.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                            } else {
                                Text("Waiting for GPS...").font(.caption2).foregroundColor(.red.opacity(0.8))
                            }
                        }
                        
                        if !vm.message.isEmpty {
                            Text(vm.message).font(.caption).foregroundColor(vm.message.contains("Success") || vm.message.contains("Checked") ? .green : .red)
                                .padding(.horizontal, 12).padding(.vertical, 4).background(Color.white.opacity(0.05)).cornerRadius(8)
                        }
                        
                        // Unified action button: opens camera if no selfie yet, else submits
                        let needsSelfie = vm.selfie == nil && appState.today?.checkinAt == nil
                        Button(action: {
                            if needsSelfie {
                                vm.startFlow()
                            } else if let loc = locationService.lastLocation {
                                Task { await vm.toggleAttendance(loc: loc) }
                            } else {
                                LocationTrackingService.shared.startTracking()
                                vm.message = "Acquiring GPS location…"
                            }
                        }) {
                            HStack(spacing: 10) {
                                if vm.isLoading {
                                    ProgressView().tint(.white)
                                } else if needsSelfie {
                                    Image(systemName: "camera.fill")
                                    Text("TAKE SELFIE TO CHECK IN").fontWeight(.black)
                                } else {
                                    Image(systemName: appState.today?.checkinAt != nil ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                                    Text(appState.today?.checkinAt != nil ? "CHECK OUT NOW" : "CHECK IN NOW").fontWeight(.black)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(needsSelfie ? Color.blue : (appState.today?.checkinAt != nil ? Color.gray.opacity(0.3) : Color.red))
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .disabled(vm.isLoading)
                    }
                    .padding(30).liquidGlass().padding(.horizontal, 20)
                    
                    // History Header
                    Text("RECENT HISTORY").font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(1).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 25)
                    
                    VStack(spacing: 12) {
                        if let t = appState.today {
                            AttendanceHistoryRow(record: t, localLocationStamp: vm.checkinLocationStamp)
                        } else {
                            EmptyHistoryRow()
                        }
                    }.padding(.horizontal, 20)
                    
                    Spacer().frame(height: 120)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                appState.updateScrollProgress(newValue)
            }
        }
    }
    .onReceive(timer) { _ in currentTime = Date() }
        .onAppear { 
            Task { await vm.refresh() }
            LocationTrackingService.shared.startTracking()
        }
    }
}

struct AttendanceHistoryRow: View {
    let record: AttendanceRecord
    var localLocationStamp: String? = nil

    private var dayString: String {
        guard let dateStr = record.date else { return "--" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        if let d = fmt.date(from: dateStr) {
            fmt.dateFormat = "dd"
            return fmt.string(from: d)
        }
        return "--"
    }

    private var monthString: String {
        guard let dateStr = record.date else { return "---" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        if let d = fmt.date(from: dateStr) {
            fmt.dateFormat = "MMM"
            return fmt.string(from: d).uppercased()
        }
        return "---"
    }

    private var statusTitle: String {
        if record.checkoutAt != nil { return "Full Shift Completed" }
        if record.checkinAt != nil { return "Checked In" }
        return "Present"
    }

    var body: some View {
        HStack(spacing: 15) {
            // Selfie thumbnail if available, otherwise date badge
            if let selfieUrl = record.checkinSelfieUrl, let url = URL(string: selfieUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } placeholder: {
                    dateBadge
                }
            } else {
                dateBadge
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.subheadline).fontWeight(.bold).foregroundColor(Color(uiColor: .label))
                HStack(spacing: 10) {
                    Label(formatTime(record.checkinAt), systemImage: "clock")
                        .font(.caption2).foregroundColor(.gray)
                    if record.checkoutAt != nil {
                        Label(formatTime(record.checkoutAt), systemImage: "clock.fill")
                            .font(.caption2).foregroundColor(.gray)
                    }
                }
                // Location stamp (server address → server coords → locally cached coords)
                if let address = record.checkinAddress {
                    Label(address, systemImage: "location.fill")
                        .font(.caption2).foregroundColor(.gray).lineLimit(1)
                } else if let lat = record.checkinLatitude, let lng = record.checkinLongitude {
                    Label(String(format: "%.4f, %.4f", lat, lng), systemImage: "location")
                        .font(.caption2).foregroundColor(.gray)
                } else if let stamp = localLocationStamp {
                    Label(stamp, systemImage: "location")
                        .font(.caption2).foregroundColor(.gray)
                }
            }
            Spacer()
            if let hours = record.totalHours {
                Text(String(format: "%.1f hrs", hours))
                    .font(.caption).fontWeight(.black).padding(6)
                    .background(Color.white.opacity(0.08)).cornerRadius(8)
            }
        }
        .padding().liquidGlass()
    }

    private var dateBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.1)).frame(width: 50, height: 50)
            VStack(spacing: -2) {
                Text(dayString).font(.headline).foregroundColor(Color(uiColor: .label))
                Text(monthString).font(.system(size: 8, weight: .bold)).foregroundColor(.green)
            }
        }
    }
}

struct EmptyHistoryRow: View {
    var body: some View {
        HStack {
            Image(systemName: "calendar").foregroundColor(.gray)
            Text("Attendance history will appear here").font(.subheadline).foregroundColor(.gray)
            Spacer()
        }.padding().liquidGlass()
    }
}

struct ActivityFeedView: View {
    @EnvironmentObject var appState: AppState
    @StateObject var vm = ActivityFeedViewModel()
    
    var body: some View {
        if appState.selectedOutlet != nil {
            StoreVisitView()
        } else {
            ZStack {
                VibrantBackgroundView()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Work Feed").font(.largeTitle).fontWeight(.black).foregroundColor(Color(uiColor: .label)).padding(.top, 20).padding(.horizontal)
                        
                        if vm.isLoading && vm.items.isEmpty {
                            ProgressView().tint(.red).frame(maxWidth: .infinity).padding(.top, 50)
                        } else if vm.items.isEmpty {
                            VStack(spacing: 15) {
                                Image(systemName: "bubble.left.and.exclamationmark.bubble.right").font(.system(size: 50)).foregroundColor(.gray)
                                Text("No recent activity found").foregroundColor(.gray)
                            }.frame(maxWidth: .infinity).padding(.top, 100)
                        } else {
                            ForEach(vm.items) { item in
                                ActivityRow(item: item)
                            }
                        }
                        Spacer().frame(height: 120)
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newValue in
                    appState.updateScrollProgress(newValue)
                }
                .refreshable { await vm.refresh() }
            }
            .onAppear { Task { await vm.refresh() } }
        }
    }
    
    struct ActivityRow: View {
        let item: ActivityFeedItem
        var body: some View {
            HStack(spacing: 15) {
                Image(systemName: "doc.plaintext.fill").foregroundColor(.purple).font(.title3).padding(12).background(Color.purple.opacity(0.1)).clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.outletName ?? "General Submission").font(.subheadline).fontWeight(.bold).foregroundColor(Color(uiColor: .label))
                    Text(formatTime(item.submittedAt)).font(.caption2).foregroundColor(.gray)
                }
                Spacer()
                if item.isConverted {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                }
            }
            .padding(15).liquidGlass().padding(.horizontal, 20)
        }
    }
}

    struct SOSView: View {
        @Environment(\.dismiss) var d; @StateObject var vm = SOSViewModel()
        var body: some View {
            ZStack {
                Color.red.ignoresSafeArea()
                VStack(spacing: 40) {
                    Text("EMERGENCY SOS").font(.largeTitle.bold()).foregroundColor(.white)
                    Text("\(vm.countdown)").font(.system(size: 120, weight: .bold)).foregroundColor(.white)
                    Button("CANCEL") { d() }.padding().background(.white.opacity(0.2)).cornerRadius(12).foregroundColor(.white)
                }
            }
            .onAppear { vm.start() }
        }
    }
