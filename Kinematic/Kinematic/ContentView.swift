import SwiftUI
import Combine
import CoreLocation
import Foundation

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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.12), .clear],
                            startPoint: UnitPoint(x: 0.1, y: 0.1),
                            endPoint: UnitPoint(x: 0.9, y: 0.9)
                        )
                    )
            )
            .background {
                // Aura Bloom (Soft inner glow)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .blur(radius: 10)
            }
            .overlay {
                // Dynamic Specular Glint (Parallax Effect)
                GeometryReader { geo in
                    let scrollY = geo.frame(in: .global).minY
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.2), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .offset(x: -scrollY * 0.04, y: -scrollY * 0.04)
                        .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .opacity(0.6)
                }
                .allowsHitTesting(false)
            }
            .overlay(
                // Prismatic Refraction Border
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.9), location: 0),
                                .init(color: .white.opacity(0.2), location: 0.3),
                                .init(color: .red.opacity(0.3), location: 0.5),
                                .init(color: .white.opacity(0.1), location: 0.7),
                                .init(color: .white.opacity(0.4), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
}

// --- HELPERS (Global Scope) ---
func formatTime(_ iso: String?) -> String {
    guard let date = parseISO(iso) else { return "--:--" }
    let out = DateFormatter()
    out.dateFormat = "h:mm a"
    return out.string(from: date)
}


// --- MAIN VIEWS ---
struct ContentView: View {
    @EnvironmentObject var appState: KiniAppState
    
    var body: some View {
        ZStack {
            // GLOBAL CANVAS (Root-Level Atmospheric Background)
            VibrantBackgroundView()
                .ignoresSafeArea()
            
            if !appState.isAuthenticated {
                LoginView(onSuccess: { appState.checkAuth() })
            } else {
                MainTabView()
            }
        }
        .fullScreenCover(item: $appState.activeSecondaryRoute) { route in
            SecondaryScreenHost(route: route)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var appState: KiniAppState
    @Namespace private var animation // For Matched Geometry (Liquid Pod)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // GLOBAL CONTENT PAGING (Definitive Safe Isolation)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    HomeView()
                        .id(0)
                        .tag(0)
                        .containerRelativeFrame(.horizontal, count: 1, spacing: 0)
                    
                    AttendanceView()
                        .id(1)
                        .tag(1)
                        .containerRelativeFrame(.horizontal, count: 1, spacing: 0)
                    
                    RoutePlansView()
                        .id(2)
                        .tag(2)
                        .containerRelativeFrame(.horizontal, count: 1, spacing: 0)
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: .init(get: { appState.selectedTab }, set: { if let v = $0 { appState.selectedTab = v } }))
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, 0)
            
            if appState.showGlobalSuccess {
                SuccessOverlay(message: appState.lastSuccessMessage) {
                    withAnimation { appState.showGlobalSuccess = false }
                }
                .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .opacity))
                .zIndex(200)
            }
            
            // iOS 26 "Liquid Glass" Navigation (Unified Capsule)
            HStack(spacing: 0) {
                TabBtn(i: "house", l: "Home", s: appState.selectedTab == 0, ns: animation) { 
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appState.selectedTab = 0 }
                }
                TabBtn(i: "person.text.rectangle", l: "Attendance", s: appState.selectedTab == 1, ns: animation) { 
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appState.selectedTab = 1 }
                }
                TabBtn(i: "map", l: "Route", s: appState.selectedTab == 2, ns: animation) { 
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appState.selectedTab = 2 }
                }
            }
            .padding(.vertical, 14)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        // Specular Rim (Top Highlight)
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.6), .clear, .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 15)
            }
            .overlay {
                // Outer Prismatic Bloom
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.1), .red.opacity(0.05), .white.opacity(0.1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
            .zIndex(10) // Prioritize hit testing for taps
            
            SideMenuView(isOpen: $appState.showSideMenu)
        }
        .fullScreenCover(item: $appState.selectedOutlet) { _ in
            StoreVisitView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerCamera)) { _ in
            print("📸 [MainTab] Caught Broadcast Signal - Forcing Camera Presentation")
            appState.triggerCamera()
        }
        .onChange(of: appState.capturedSelfie) { _, newSelfie in
            guard let img = newSelfie else { return }
            print("📸 [Root] Captured Selfie handoff. Triggering attendance logic...")
            // Clear global IMMEDIATELY to prevent double-firing during async handoff
            appState.capturedSelfie = nil 
            appState.attendanceVM.selfie = img
            if let loc = LocationTrackingService.shared.lastLocation {
                Task { await appState.attendanceVM.toggleAttendance(loc: loc) }
            } else {
                appState.attendanceVM.message = "Waiting for GPS... Tap Check-in again."
            }
        }
        .task {
            // --- STABILITY: Initial Data Load ---
            // We fetch dashboard data ONLY ONCE when the main UI settles.
            print("📡 [MainTab] Performing Initial Dashboard Refresh")
            await appState.attendanceVM.refresh()
            
            // Auto-start tracking if session restored
            if appState.today?.isIn == true {
                appState.startTrackingTimer()
                LocationTrackingService.shared.startTracking()
            }
        }
        .onChange(of: appState.capturedSelfie) {
            if let img = appState.capturedSelfie {
                print("📸 [MainTab] Image captured, handing off...")
                appState.attendanceVM.processCapturedSelfie(image: img)
                appState.capturedSelfie = nil // Reset path
                appState.activeSecondaryRoute = nil // Reset modal
            }
        }
    }
}

struct TabBtn: View {
    let i: String; let l: String; let s: Bool
    let ns: Namespace.ID
    let a: () -> Void
    
    var body: some View {
        Button(action: a) {
            VStack(spacing: 2) {
                ZStack {
                    if s {
                        ZStack {
                            Capsule()
                                .fill(.regularMaterial)
                                .opacity(0.6)
                                .scaleEffect(1.3)
                                .matchedGeometryEffect(id: "pod", in: ns)
                            
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(uiColor: .label).opacity(0.2), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                                .matchedGeometryEffect(id: "pod_glint", in: ns)
                        }
                        .frame(width: 44, height: 28)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                    }
                    
                    Image(systemName: s ? "\(i).fill" : i)
                        .font(.system(size: 19, weight: s ? .black : .bold))
                        .symbolEffect(.bounce, value: s)
                        .foregroundStyle(s ? AnyShapeStyle(Color(uiColor: .label)) : AnyShapeStyle(Color(uiColor: .secondaryLabel)))
                        .scaleEffect(s ? 1.2 : 1.0)
                }
                Text(l)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(s ? AnyShapeStyle(Color(uiColor: .label)) : AnyShapeStyle(Color(uiColor: .secondaryLabel)))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct HomeView: View {
    @EnvironmentObject var appState: KiniAppState
    @StateObject var vm = HomeViewModel()
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 26) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Kinematic").font(.system(size: 28, weight: .black, design: .rounded)).foregroundColor(Color(uiColor: .label))
                            Text("Field Operations Hub").font(.caption).fontWeight(.semibold).foregroundColor(.secondary).tracking(0.5)
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
                    .padding(.horizontal, 60)
                    .padding(.top, 60)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Summary").font(.subheadline).foregroundColor(.secondary)
                            Text(Session.currentUser?.name ?? "Field Executive").font(.title2).fontWeight(.bold).foregroundColor(Color(uiColor: .label))
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Button(action: { Task { await vm.refresh() } }) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .medium)).frame(width: 36, height: 36).background(.regularMaterial, in: Circle()).foregroundColor(Color(uiColor: .label))
                            }
                            Button(action: { appState.logout() }) {
                                Image(systemName: "power").font(.system(size: 14, weight: .medium)).frame(width: 36, height: 36).background(Color.red.opacity(0.12), in: Circle()).foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 60)

                    SelfieStatusCard(record: appState.today).padding(.horizontal, 60)

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            StatTile(label: "Store Target", value: "\(vm.totalStoreCount)", icon: "storefront.fill", color: .blue)
                            StatTile(label: "Visited", value: "\(vm.visitedStoreCount)", icon: "checkmark.seal.fill", color: .green)
                        }
                        StatTile(label: "Data Forms Submitted Today", value: "\(vm.data?.summary?.tffCount ?? 0)", icon: "doc.text.fill", color: .purple)
                    }
                    .padding(.horizontal, 60)

                    SessionCard(record: appState.today).padding(.horizontal, 60)

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
                        .padding(18).liquidGlass().padding(.horizontal, 32).transition(.scale.combined(with: .opacity))
                    } else if let b = vm.data?.broadcast, !(vm.data?.alreadyAnswered ?? b.alreadyAnswered) {
                        BroadcastCard(broadcast: b) { selectedIndex in
                            Task { await vm.submitBroadcastAnswer(id: b.id, selectedIndex: selectedIndex) }
                        }
                        .padding(.horizontal, 60)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("TODAY'S ROUTE").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary).tracking(1)
                            Spacer()
                            Button(action: { 
                                if appState.today?.checkinAt != nil { appState.selectedTab = 2 } 
                            }) {
                                Text("VIEW ALL").font(.system(size: 11, weight: .bold)).foregroundColor(appState.today?.checkinAt != nil ? .red : .gray)
                            }
                        }
                        let previewOutlets = Array(vm.uniqueOutlets.prefix(3))
                        if appState.today?.checkinAt == nil {
                            HStack {
                                Image(systemName: "lock.fill").foregroundColor(.gray)
                                Text("Check in to unlock route").font(.caption).foregroundColor(.gray)
                            }
                            .padding(.vertical, 8)
                        } else if !previewOutlets.isEmpty {
                            ForEach(previewOutlets) { outlet in
                                Button(action: {
                                    withAnimation(.spring()) { appState.selectedOutlet = outlet; appState.selectedTab = 2 }
                                }) {
                                    RoutePreviewRow(outlet: outlet)
                                }
                            }
                        } else {
                            Text("No stores assigned for today").font(.subheadline).foregroundColor(.secondary).padding(.vertical, 8)
                        }
                    }
                    .padding(20).liquidGlass().padding(.horizontal, 60)

                    Spacer().frame(height: 110)
                }
            }
            .refreshable { await vm.refresh() }
        }
        .onAppear { Task { await vm.refresh() } }
    }
}

// --- SHARED COMPONENTS ---

struct SelfieStatusCard: View {
    @EnvironmentObject var appState: KiniAppState
    let record: AttendanceRecord?
    @State private var showCheckoutAlert = false
    
    var isIn: Bool { record?.isIn ?? false }
    
    var body: some View {
        let isCheckInIntent = appState.today?.checkinAt == nil
        let isShiftEnded = appState.today?.checkoutAt != nil
        
        Button(action: {
            if isShiftEnded { return } // No actions after checkout
            
            if isCheckInIntent {
                appState.attendanceVM.startFlow()
            } else {
                showCheckoutAlert = true
            }
        }) {
            HStack(spacing: 20) {
                // Branded Indicator
                ZStack {
                    Circle()
                        .fill(isIn ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: isIn ? "person.badge.shield.checkmark.fill" : "person.badge.key.fill")
                        .font(.title2)
                        .foregroundColor(isIn ? .green : .red)
                        .symbolEffect(.pulse, value: !isIn)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    // Explicit Status Badge
                    HStack(spacing: 6) {
                        Text(isIn ? "CHECKED IN" : "OFFLINE")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isIn ? Color.green : Color.red)
                            .clipShape(Capsule())
                        
                        if let _ = record?.checkoutAt, !isIn {
                            Text("SHIFT PAUSED")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(isShiftEnded ? "Shift Completed" : (isIn ? "Shift Active" : (record?.checkinAt == nil ? "Daily Selfie Required" : "Check In to Resume")))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Color(uiColor: .label))
                    
                    Text(isShiftEnded ? "See you tomorrow!" : (isIn ? "Ongoing since \(formatTime(record?.checkinAt))" : (record?.checkinAt == nil ? "Tap to complete check-in" : "Last seen at \(formatTime(record?.checkoutAt))")))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action Glyph (Dynamic)
                Image(systemName: isShiftEnded ? "checkmark.seal.fill" : "camera.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(isShiftEnded ? Color.gray : (isCheckInIntent ? Color.blue : Color.red), in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            }
            .padding(20)
            .background {
                // High-End Aura Background
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                    
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    (isIn ? Color.green : Color.red).opacity(0.6),
                                    .clear,
                                    .white.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        }
        .alert("Confirm Checkout", isPresented: $showCheckoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Proceed to Checkout", role: .destructive) {
                let isExecutive = Session.currentUser?.role.lowercased().contains("executive") ?? false
                if isExecutive {
                    appState.attendanceVM.startFlow()
                } else if let loc = LocationTrackingService.shared.lastLocation {
                    Task { await appState.attendanceVM.toggleAttendance(loc: loc) }
                } else {
                    appState.attendanceVM.startFlow()
                }
            }
        } message: {
            Text("You wish to checkout? After checkout you won't be able to do any task.")
        }
    }
}

struct StatTile: View {
    let label: String; let value: String; let icon: String; let color: Color
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(color.opacity(0.1)).frame(width: 44, height: 44)
                Image(systemName: icon).foregroundColor(color).font(.system(size: 18, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased()).font(.system(size: 8, weight: .black)).foregroundColor(.secondary).tracking(1)
                Text(value).font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(Color(uiColor: .label))
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 16).liquidGlass()
    }
}

struct SessionCard: View {
    let record: AttendanceRecord?
    var body: some View {
        if let ciStr = record?.checkinAt, let ci = parseISO(ciStr) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                SessionCardContent(checkinDate: ci, checkoutDate: parseISO(record?.checkoutAt), now: context.date)
            }
        } else {
            SessionCardContent(checkinDate: nil, checkoutDate: nil, now: .now)
        }
    }
}

struct SessionCardContent: View {
    @EnvironmentObject var appState: KiniAppState
    let checkinDate: Date?
    let checkoutDate: Date?
    let now: Date
    
    private var isActive: Bool { appState.today?.isIn ?? false }
    private var startDate: Date? {
        if let first = appState.today?.firstCheckinAt, let date = parseISO(first) { return date }
        return checkinDate
    }
    private var endDate: Date {
        if isActive { return now }
        let lastDisplay = appState.today?.lastCheckoutAt ?? appState.today?.checkoutAt
        if let str = lastDisplay, let date = parseISO(str) { return date }
        return checkoutDate ?? now
    }
    private var elapsed: TimeInterval { 
        // Logic: Total working time = Past total duration + Current session elapsed time
        let pastDuration = Double(appState.today?.totalDuration ?? 0)
        guard let start = checkinDate, isActive else { return pastDuration }
        let currentSession = max(0, now.timeIntervalSince(start))
        return pastDuration + currentSession
    }
    private var progress: Double { min(elapsed / (9 * 3600), 1.0) } // Increased target to 9h for full-day visibility
    private var elapsedLabel: String {
        let h = Int(elapsed) / 3600; let m = (Int(elapsed) % 3600) / 60; let s = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("TOTAL DAILY SHIFT").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary).tracking(1)
                Spacer()
                if startDate != nil {
                    HStack(spacing: 4) {
                        if isActive { Circle().fill(.green).frame(width: 6, height: 6) }
                        Text(isActive ? "ACTIVE" : "COMPLETED").font(.system(size: 9, weight: .black)).foregroundStyle(isActive ? .green : .secondary)
                    }
                }
            }
            if let start = startDate {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
                        Circle().trim(from: 0, to: progress).stroke(LinearGradient(colors: progress >= 1.0 ? [.green, .mint] : [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text("\(Int(progress * 100))%").font(.system(size: 16, weight: .black, design: .rounded))
                            Text("of 9h").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        .scaleEffect(isActive ? (1.0 + 0.05 * sin(now.timeIntervalSince1970 * 2)) : 1.0)
                    }
                    .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 10) {
                        SessionTimeRow(label: "First Check-In", value: start.formatted(date: .omitted, time: .shortened), icon: "arrow.right.circle.fill", color: .green)
                        if !isActive { 
                            SessionTimeRow(label: "Final Check-Out", value: endDate.formatted(date: .omitted, time: .shortened), icon: "arrow.left.circle.fill", color: .red) 
                        }
                        else { SessionTimeRow(label: "Total Elapsed", value: elapsedLabel, icon: "timer", color: .orange) }
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No session started").font(.subheadline).fontWeight(.semibold)
                        Text("Check in to begin your daily shift tracking").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
        }
        .padding(20).liquidGlass()
    }
}

struct SessionTimeRow: View {
    let label: String; let value: String; let icon: String; let color: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(color).frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Color(uiColor: .label))
            }
        }
    }
}

struct BroadcastCard: View {
    let broadcast: BroadcastQuestion; let onAnswer: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) { Image(systemName: "megaphone.fill").font(.caption); Text("ANNOUNCEMENT").font(.system(size: 10, weight: .bold)).tracking(1) }.foregroundColor(broadcast.isUrgent ? .red : .blue)
                Spacer()
                if broadcast.alreadyAnswered { Text("ANSWERED").font(.system(size: 8, weight: .bold)).padding(4).background(Color.green.opacity(0.2)).foregroundColor(.green).cornerRadius(4) }
            }
            Text(broadcast.question).font(.subheadline).fontWeight(.bold).foregroundColor(Color(uiColor: .label)).lineLimit(3)
            if !broadcast.alreadyAnswered {
                VStack(spacing: 8) {
                    ForEach(Array(broadcast.options.prefix(3).enumerated()), id: \.offset) { index, opt in
                        Button(action: { onAnswer(index) }) {
                            HStack { Text(opt.label).font(.caption).foregroundColor(Color(uiColor: .label)); Spacer(); Image(systemName: "circle").font(.caption).foregroundColor(.gray) }.padding(10).background(Color(uiColor: .label).opacity(0.05)).cornerRadius(10)
                        }
                    }
                }
            }
        }.padding(20).liquidGlass()
    }
}

struct RoutePreviewRow: View {
    let outlet: RouteOutlet
    var body: some View {
        HStack {
            Image(systemName: outlet.status == "visited" ? "checkmark.circle.fill" : "storefront").foregroundColor(outlet.status == "visited" ? .green : .gray)
            VStack(alignment: .leading) {
                Text(outlet.storeName ?? "Unknown Store").font(.subheadline).fontWeight(.bold).foregroundColor(Color(uiColor: .label))
                if let activities = outlet.activities, !activities.isEmpty { Text("\(activities.count) tasks assigned").font(.system(size: 10)).foregroundColor(.gray) }
            }
            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
        }
    }
}

struct RoutePlansView: View {
    @EnvironmentObject var appState: KiniAppState
    @StateObject var vm = RoutePlansViewModel()
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            VStack(spacing: 0) {
                HStack {
                    Button(action: { withAnimation { appState.showSideMenu = true } }) { 
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(uiColor: .label))
                            .frame(width: 40, height: 40)
                            .background(.regularMaterial, in: Circle()) 
                    }
                    Text("Today's Route").font(.title3).fontWeight(.bold).foregroundColor(Color(uiColor: .label)).padding(.leading, 8)
                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.top, 60)
                .padding(.bottom, 8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Route Details").font(.largeTitle).fontWeight(.black).foregroundColor(Color(uiColor: .label)).padding(.horizontal, 60)
                        
                        let isShiftEnded = appState.today?.checkoutAt != nil
                        if appState.today?.checkinAt == nil {
                            VStack(spacing: 20) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 64))
                                    .foregroundStyle(LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom))
                                    .padding(.bottom, 10)
                                Text("SHIFT RESTRICTED").font(.system(size: 12, weight: .black)).tracking(2).foregroundColor(.red)
                                Text("Checkpoint Required").font(.title2).fontWeight(.black).foregroundColor(Color(uiColor: .label))
                                Text("Your route plans and store tasks are locked until your first check-in of the day is completed.").font(.subheadline).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 60)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        }
                        else if isShiftEnded {
                             VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "flag.checkered").foregroundColor(.gray)
                                    Text("SHIFT COMPLETED").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(.gray)
                                    Spacer()
                                }
                                .padding(.horizontal, 60).padding(.top, 10)
                                
                                ForEach(vm.plans) { plan in ForEach(plan.outlets ?? []) { outlet in OutletCard(outlet: outlet) } }
                             }
                        }
                        else if vm.isLoading && vm.plans.isEmpty { ProgressView().tint(.red).frame(maxWidth: .infinity).padding(.top, 50) }
                        else if vm.plans.isEmpty {
                            VStack(spacing: 15) { Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 50)).foregroundColor(.gray); Text("No routes planned for today").foregroundColor(.gray) }.frame(maxWidth: .infinity).padding(.top, 100)
                        } else {
                            ForEach(vm.plans) { plan in ForEach(plan.outlets ?? []) { outlet in OutletCard(outlet: outlet) } }
                        }
                        Spacer().frame(height: 120)
                    }
                }
                .refreshable { await vm.refresh() }
            }
        }.onAppear { Task { await vm.refresh() } }
    }
}

struct OutletCard: View {
    @EnvironmentObject var appState: KiniAppState
    let outlet: RouteOutlet
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(outlet.storeName ?? "Unknown Store").font(.headline).foregroundColor(Color(uiColor: .label))
                Spacer()
                if outlet.status == "visited" { Text("COMPLETED").font(.system(size: 8, weight: .bold)).padding(5).background(Color.green.opacity(0.2)).foregroundColor(.green).cornerRadius(5) }
            }
            Text(outlet.address ?? "No address provided").font(.caption).foregroundColor(.gray)
            HStack {
                HStack(spacing: 4) { Image(systemName: "list.clipboard").font(.caption); Text("\((outlet.activities ?? []).count) Tasks").font(.caption).fontWeight(.bold) }.foregroundColor(.purple)
                Spacer()
                let isShiftEnded = appState.today?.checkoutAt != nil
                Button(action: { if !isShiftEnded || outlet.status == "visited" { appState.selectedOutlet = outlet } }) {
                    Text(outlet.status == "visited" ? "View Details" : (isShiftEnded ? "Shift Ended" : "Start Visit")).font(.caption2).fontWeight(.black).padding(.horizontal, 12).padding(.vertical, 6).background(outlet.status == "visited" ? Color.gray.opacity(0.2) : (isShiftEnded ? Color.gray.opacity(0.4) : Color.red)).foregroundColor(.white).cornerRadius(15)
                }
                .disabled(isShiftEnded && outlet.status != "visited")
            }.padding(.top, 5)
        }.padding(20).liquidGlass().padding(.horizontal, 60)
    }
}

struct AttendanceView: View {
    @EnvironmentObject var appState: KiniAppState
    var vm: AttendanceViewModel { appState.attendanceVM }
    @EnvironmentObject var locationService: LocationTrackingService
    @State private var currentTime = Date()
    @State private var showCheckoutAlert = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            VStack(spacing: 0) {
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
                .padding(.horizontal, 60)
                .padding(.top, 60)
                
                ScrollView {
                    VStack(spacing: 25) {
                        Text("Attendance").font(.largeTitle).fontWeight(.black).foregroundColor(Color(uiColor: .label)).padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 60)
                        
                        VStack(spacing: 24) {
                            let isIn = appState.today?.isIn ?? false
                            VStack(spacing: 4) {
                                Text(currentTime.formatted(date: .omitted, time: .shortened)).font(.system(size: 44, weight: .black, design: .rounded)).foregroundColor(Color(uiColor: .label))
                                Text(currentTime.formatted(date: .complete, time: .omitted)).font(.caption).fontWeight(.bold).foregroundColor(.gray).textCase(.uppercase)
                            }
                            VStack(spacing: 12) {
                                Button(action: { 
                                    print("📸 [AttendanceView] Take Selfie Button Tapped")
                                    vm.startFlow() 
                                }) {
                                    ZStack {
                                        Circle().fill(Color.white.opacity(0.05)).frame(width: 140, height: 140)
                                        if let img = vm.selfie { Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 130, height: 130).clipShape(Circle()) }
                                        else if let selfieUrl = appState.today?.checkinSelfieUrl, let url = URL(string: selfieUrl) { AsyncImage(url: url) { image in image.resizable().aspectRatio(contentMode: .fill).frame(width: 130, height: 130).clipShape(Circle()) } placeholder: { ProgressView().tint(.gray).frame(width: 130, height: 130) } }
                                        else { VStack(spacing: 8) { Image(systemName: "camera.fill").font(.title).foregroundColor(.red); Text("Take Selfie").font(.caption2).fontWeight(.bold).foregroundColor(.gray) } }
                                    }.overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                                }
                                .contentShape(Circle())
                            }
                            VStack(spacing: 8) {
                                HStack(spacing: 6) { 
                                    Circle().fill(isIn ? Color.green : Color.red).frame(width: 8, height: 8)
                                    Text(isIn ? "Shift: Active" : "Shift: Offline")
                                        .font(.headline)
                                        .foregroundColor(Color(uiColor: .label)) 
                                }
                                if let loc = locationService.lastLocation { Text(String(format: "Location: %.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)).font(.system(size: 10, design: .monospaced)).foregroundColor(.gray) }
                                else { Text("Waiting for GPS...").font(.caption2).foregroundColor(.red.opacity(0.8)) }
                            }
                            if !vm.message.isEmpty { Text(vm.message).font(.caption).foregroundColor(vm.message.contains("Success") ? .green : .red).padding(.horizontal, 12).padding(.vertical, 4).background(Color.white.opacity(0.05)).cornerRadius(8) }
                            
                            let isCheckInIntent = appState.today?.checkinAt == nil
                            let isExecutive = Session.currentUser?.role.lowercased().contains("executive") ?? false
                            let needsSelfie = vm.selfie == nil && (isCheckInIntent || isExecutive)
                            let isShiftEnded = appState.today?.checkoutAt != nil
                            
                            Button(action: { 
                                if isShiftEnded { return }
                                
                                if isCheckInIntent {
                                    if needsSelfie { vm.startFlow() }
                                    else if let loc = locationService.lastLocation { Task { await vm.toggleAttendance(loc: loc) } }
                                } else {
                                    // Trigger Checkout Alert in the tab too if needed, but for simplicity we can use the same logic
                                    // However, AttendanceView needs its own @State for the alert
                                    showCheckoutAlert = true
                                }
                            }) {
                                HStack(spacing: 10) {
                                    if vm.isLoading { ProgressView().tint(.white) }
                                    else if isShiftEnded { Image(systemName: "checkmark.seal.fill"); Text("SHIFT COMPLETED").fontWeight(.black) }
                                    else if needsSelfie && isCheckInIntent { Image(systemName: "camera.fill"); Text("TAKE SELFIE TO CHECK IN").fontWeight(.black) }
                                    else if isCheckInIntent { Image(systemName: "arrow.right.circle.fill"); Text("CHECK IN NOW").fontWeight(.black) }
                                    else { Image(systemName: "arrow.left.circle.fill"); Text("CHECK OUT NOW").fontWeight(.black) }
                                }
                            }
                            .frame(maxWidth: .infinity).padding().background(isShiftEnded ? Color.gray : (isCheckInIntent ? (needsSelfie ? Color.blue : Color.green) : Color.red)).foregroundColor(.white).cornerRadius(18).disabled(vm.isLoading || isShiftEnded)
                        }.padding(30).liquidGlass().padding(.horizontal, 60)
                        .alert("Confirm Checkout", isPresented: $showCheckoutAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Proceed to Checkout", role: .destructive) {
                                if let loc = locationService.lastLocation {
                                    Task { await vm.toggleAttendance(loc: loc) }
                                } else {
                                    vm.startFlow()
                                }
                            }
                        } message: {
                            Text("You wish to checkout? After checkout you won't be able to do any task.")
                        }
                        
                        SessionCard(record: appState.today).padding(.horizontal, 60)
                        
                        Text("RECENT HISTORY").font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(1).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 60)
                        VStack(spacing: 12) {
                            if let t = appState.today { AttendanceHistoryRow(record: t, localLocationStamp: vm.checkinLocationStamp) }
                            else { EmptyHistoryRow() }
                        }.padding(.horizontal, 60)
                        Spacer().frame(height: 120)
                    }
                }
            }
        }.onReceive(timer) { _ in currentTime = Date() }
        .onAppear { Task { await vm.refresh() }; LocationTrackingService.shared.startTracking() }
    }
}

struct AttendanceHistoryRow: View {
    let record: AttendanceRecord; var localLocationStamp: String? = nil
    private var dayString: String { guard let dateStr = record.date, let d = parseDate(dateStr) else { return "--" }; let fmt = DateFormatter(); fmt.dateFormat = "dd"; return fmt.string(from: d) }
    private var monthString: String { guard let dateStr = record.date, let d = parseDate(dateStr) else { return "---" }; let fmt = DateFormatter(); fmt.dateFormat = "MMM"; return fmt.string(from: d).uppercased() }
    private func parseDate(_ s: String) -> Date? { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: s) }
    var body: some View {
        let displayCheckin = record.firstCheckinAt ?? record.checkinAt
        let displayCheckout = record.lastCheckoutAt ?? record.checkoutAt
        
        return HStack(spacing: 15) {
            if let selfieUrl = record.checkinSelfieUrl, let url = URL(string: selfieUrl) { AsyncImage(url: url) { image in image.resizable().aspectRatio(contentMode: .fill).frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 12)) } placeholder: { dateBadge } }
            else { dateBadge }
            VStack(alignment: .leading, spacing: 4) {
                Text(displayCheckout != nil ? "Daily Shift Completed" : (displayCheckin != nil ? "Shift In Progress" : "Present")).font(.subheadline).fontWeight(.bold).foregroundColor(Color(uiColor: .label))
                HStack(spacing: 10) { 
                    Label(formatTime(displayCheckin), systemImage: "clock").font(.caption2).foregroundColor(.gray)
                    if let co = displayCheckout { 
                        Label(formatTime(co), systemImage: "clock.fill").font(.caption2).foregroundColor(.gray) 
                    } 
                }
            }
            Spacer()
        }.padding().liquidGlass()
    }
    private var dateBadge: some View { ZStack { RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.1)).frame(width: 50, height: 50); VStack(spacing: -2) { Text(dayString).font(.headline).foregroundColor(Color(uiColor: .label)); Text(monthString).font(.system(size: 8, weight: .bold)).foregroundColor(.green) } } }
}

struct EmptyHistoryRow: View {
    var body: some View { HStack { Image(systemName: "calendar").foregroundColor(.gray); Text("Attendance history will appear here").font(.subheadline).foregroundColor(.gray); Spacer() }.padding().liquidGlass() }
}

struct ActivityFeedView: View {
    @EnvironmentObject var appState: KiniAppState
    @StateObject var vm = ActivityFeedViewModel()
    var body: some View {
        if appState.selectedOutlet != nil { StoreVisitView() }
        else {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Work Feed").font(.largeTitle).fontWeight(.black).foregroundColor(Color(uiColor: .label)).padding(.top, 20).padding(.horizontal, 60)
                        if vm.isLoading && vm.items.isEmpty { ProgressView().tint(.red).frame(maxWidth: .infinity).padding(.top, 50) }
                        else if vm.items.isEmpty { VStack(spacing: 15) { Image(systemName: "bubble.left.and.exclamationmark.bubble.right").font(.system(size: 50)).foregroundColor(.gray); Text("No recent activity found").foregroundColor(.gray) }.frame(maxWidth: .infinity).padding(.top, 100) }
                        else { ForEach(vm.items) { item in ActivityRow(item: item) } }
                        Spacer().frame(height: 120)
                    }
                }.refreshable { await vm.refresh() }
            }.onAppear { Task { await vm.refresh() } }
        }
    }
}

struct ActivityRow: View {
    let item: ActivityFeedItem
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "doc.plaintext.fill").foregroundColor(.purple).font(.title3).padding(12).background(Color.purple.opacity(0.1)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) { Text(item.outletName ?? "General Submission").font(.subheadline).fontWeight(.bold).foregroundColor(Color(uiColor: .label)); Text(formatTime(item.submittedAt)).font(.caption2).foregroundColor(.gray) }
            Spacer()
            if item.isConverted { Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption) }
        }.padding(15).liquidGlass().padding(.horizontal, 60)
    }
}

struct SOSView: View {
    @Environment(\.dismiss) var d; @StateObject var vm = SOSViewModel()
    var body: some View {
        ZStack {
            Color.red.ignoresSafeArea()
            VStack(spacing: 40) { Text("EMERGENCY SOS").font(.largeTitle.bold()).foregroundColor(.white); Text("\(vm.countdown)").font(.system(size: 120, weight: .bold)).foregroundColor(.white); Button("CANCEL") { d() }.padding().background(.white.opacity(0.2)).cornerRadius(12).foregroundColor(.white) }
        }.onAppear { vm.start() }
    }
}
