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
            // 1. Base Blur Layer matching the corner radius perfectly
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            // 2. Tint Layer to provide the specific color opacity OVER the blur, not behind it
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(uiColor: .systemBackground).opacity(opacity))
            )
            // 3. Crisp Glass Border using an overlay so it sits tight to the edges
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.6), .clear, Color.black.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            )
            // 4. Subtle Drop Shadow for floating depth
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
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
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $appState.selectedTab) {
                HomeView().tag(0)
                AttendanceView().tag(1)
                RoutePlansView().tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .ignoresSafeArea()
            
            // Mirror Glass Floating Tab Bar
            HStack(spacing: 0) {
                TabBtn(i: "house.fill", l: "Home", s: appState.selectedTab == 0) { 
                    withAnimation(.spring()) { appState.selectedTab = 0 }
                }
                TabBtn(i: "person.text.rectangle.fill", l: "Attendance", s: appState.selectedTab == 1) { 
                    withAnimation(.spring()) { appState.selectedTab = 1 }
                }
                TabBtn(i: "map.fill", l: "Route", s: appState.selectedTab == 2) { 
                    withAnimation(.spring()) { appState.selectedTab = 2 }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(MirrorGlassTabBarShape().fill(.ultraThinMaterial))
            .overlay {
                MirrorGlassTabBarShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.10),
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                MirrorGlassTabBarShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                Color.white.opacity(0.18),
                                Color.black.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .top) {
                MirrorGlassTabBarShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.34),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 30)
                    .padding(.horizontal, 18)
                    .blur(radius: 8)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
            .padding(.horizontal, 25)
            .padding(.bottom, 25)
            
            // Side Menu Overlay
            SideMenuView(isOpen: $appState.showSideMenu)
        }
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
    let i: String; let l: String; let s: Bool; let a: () -> Void
    var body: some View {
        Button(action: a) {
            VStack(spacing: 6) {
                ZStack {
                    if s {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.42),
                                        Color.white.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                            )
                            .frame(width: 52, height: 42)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Image(systemName: i)
                        .font(.system(size: 20, weight: s ? .bold : .medium))
                }
                Text(l).font(.system(size: 10, weight: s ? .black : .bold))
            }
            .foregroundColor(s ? Color(uiColor: .label) : Color(uiColor: .label).opacity(0.48))
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
                VStack(spacing: 24) {
                    // Modern App Bar Parity
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Kinematic").font(.system(size: 28, weight: .black, design: .rounded)).foregroundColor(Color(uiColor: .label))
                            Text("Field Operations Hub").font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(1)
                        }
                        Spacer()
                        Button(action: { withAnimation { appState.showSideMenu = true } }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.title3)
                                .foregroundColor(Color(uiColor: .label))
                                .padding(12)
                                .background(Color(uiColor: .label).opacity(0.05))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
    
                    // Summary Info Row
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary").font(.subheadline).foregroundColor(.gray)
                            Text(Session.currentUser?.name ?? "Field Executive").font(.title2).fontWeight(.black).foregroundColor(Color(uiColor: .label))
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            Button(action: { Task { await vm.refresh() } }) {
                                Image(systemName: "arrow.clockwise").padding(10).background(Color(uiColor: .label).opacity(0.05)).foregroundColor(Color(uiColor: .label)).clipShape(Circle())
                            }
                            Button(action: { appState.logout() }) {
                                Image(systemName: "power").padding(10).background(Color.red.opacity(0.1)).foregroundColor(.red).clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal, 25)
                    
                    // Selfie Status Card
                    SelfieStatusCard(record: appState.today)
                        .padding(.horizontal, 20)
                    
                    // Stats Row
                    HStack(spacing: 12) {
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
                                Circle().fill(Color.green.opacity(0.15)).frame(width: 45, height: 45)
                                Image(systemName: "checkmark.seal.fill").font(.title3).foregroundColor(.green)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Submission Successful!").font(.headline).foregroundColor(Color(uiColor: .label))
                                Text("Thank you for your response.").font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(20)
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
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("TODAY'S ROUTE").font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(1)
                            Spacer()
                            Button(action: { appState.selectedTab = 2 }) {
                                Text("VIEW ALL").font(.caption2).fontWeight(.bold).foregroundColor(.red)
                            }
                        }
                        
                        let previewOutlets = Array(vm.uniqueOutlets.prefix(3))
                        
                        if !previewOutlets.isEmpty {
                            ForEach(previewOutlets) { outlet in
                                Button(action: { 
                                    appState.selectedOutlet = outlet
                                    appState.selectedTab = 0
                                }) {
                                    RoutePreviewRow(outlet: outlet)
                                }
                            }
                        } else {
                            Text("No stores assigned for today").font(.subheadline).foregroundColor(.gray).padding(.vertical, 10)
                        }
                    }
                    .padding(20)
                    .liquidGlass()
                    .padding(.horizontal, 20)
                    
                    Spacer().frame(height: 100)
                }
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

struct SessionCard: View {
    let record: AttendanceRecord?
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("TODAY'S SESSION").font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(1)
            HStack {
                VStack(alignment: .leading) {
                    Text("Check-In").font(.caption).foregroundColor(.gray)
                    Text(formatTime(record?.checkinAt)).font(.headline).foregroundColor(Color(uiColor: .label))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Check-Out").font(.caption).foregroundColor(.gray)
                    Text(formatTime(record?.checkoutAt)).font(.headline).foregroundColor(Color(uiColor: .label))
                }
            }
            // Progress Bar simulation
            if record?.checkinAt != nil {
                Capsule().fill(Color.gray.opacity(0.2)).frame(height: 6)
                    .overlay(Capsule().fill(Color.red).frame(width: 100), alignment: .leading)
            }
        }
        .padding(20).liquidGlass()
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
                // Header
                HStack {
                    Button(action: { withAnimation { appState.showSideMenu = true } }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundColor(Color(uiColor: .label))
                            .padding(10)
                            .background(Color(uiColor: .label).opacity(0.05))
                            .clipShape(Circle())
                    }
                    Text("Today's Route").font(.title3).fontWeight(.bold).foregroundColor(Color(uiColor: .label)).padding(.leading, 8)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 10)
                
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
                    // Start Visit Action: Navigate to Home showing StoreVisitView
                    appState.selectedOutlet = outlet
                    appState.selectedTab = 0
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
                // Header
                HStack {
                    Button(action: { withAnimation { appState.showSideMenu = true } }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundColor(Color(uiColor: .label))
                            .padding(10)
                            .background(Color(uiColor: .label).opacity(0.05))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
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
                        
                        Button(action: { 
                            if let loc = locationService.lastLocation { Task { await vm.toggleAttendance(loc: loc) } }
                        }) {
                            HStack {
                                if vm.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: appState.today?.checkinAt != nil ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                                    Text(appState.today?.checkinAt != nil ? "CHECK OUT NOW" : "CHECK IN NOW").fontWeight(.black)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity).padding().background(appState.today?.checkinAt != nil ? Color.gray.opacity(0.3) : Color.red).foregroundColor(.white).cornerRadius(18)
                        .disabled(vm.isLoading || (vm.selfie == nil && appState.today?.checkinAt == nil))
                        .opacity((vm.selfie == nil && appState.today?.checkinAt == nil) ? 0.5 : 1.0)
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
                        Text("Work Feed").font(.largeTitle).fontWeight(.black).foregroundColor(Color(uiColor: .label)).padding(.top, 60).padding(.horizontal)
                        
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
