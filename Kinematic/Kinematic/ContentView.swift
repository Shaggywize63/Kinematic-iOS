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
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(opacity))
            .cornerRadius(cornerRadius)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.white.opacity(0.1), lineWidth: 0.5))
    }
}

struct VibrantBackgroundView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                gradient: Gradient(colors: [Color.red.opacity(0.15), Color.black]),
                center: .topLeading,
                startRadius: 50,
                endRadius: 500
            ).ignoresSafeArea()
            
            RadialGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.clear]),
                center: .bottomTrailing,
                startRadius: 100,
                endRadius: 600
            ).ignoresSafeArea()
        }
    }
}

// --- VIEW MODELS ---
class SOSViewModel: ObservableObject {
    @Published var countdown = 5
    func start() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            if self.countdown > 1 { self.countdown -= 1 } else { t.invalidate() }
        }
    }
}

class HomeViewModel: ObservableObject {
    @Published var data: MobileHomeResponse?
    @Published var isLoading = false
    
    func refresh() async {
        await MainActor.run { isLoading = true }
        let newData = await KinematicRepository.shared.getMobileHome()
        await MainActor.run { 
            self.data = newData
            self.isLoading = false
        }
    }
}

class ActivityFeedViewModel: ObservableObject {
    @Published var items: [ActivityFeedItem] = []
    @Published var isLoading = false
    
    func refresh() async {
        await MainActor.run { isLoading = true }
        let newItems = await KinematicRepository.shared.getFeed()
        await MainActor.run { 
            self.items = newItems
            self.isLoading = false
        }
    }
}

class RoutePlansViewModel: ObservableObject {
    @Published var plans: [RoutePlan] = []
    @Published var isLoading = false
    
    func refresh() async {
        await MainActor.run { isLoading = true }
        let newPlans = await KinematicRepository.shared.fetchMyRoutePlan()
        await MainActor.run { 
            self.plans = newPlans
            self.isLoading = false
        }
    }
}

class AttendanceViewModel: ObservableObject {
    @Published var today: AttendanceRecord?
    @Published var isLoading = false
    @Published var message = ""
    
    func refresh() async {
        let data = await KinematicRepository.shared.getMobileHome()
        await MainActor.run { self.today = data?.today }
    }
    
    func toggleAttendance(loc: CLLocation) async {
        await MainActor.run { isLoading = true; message = "" }
        let isCheckIn = today?.checkinAt == nil || (today?.checkinAt != nil && today?.checkoutAt != nil)
        let (success, err) = await KinematicRepository.shared.markAttendance(isCheckIn: isCheckIn, lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
        
        await MainActor.run {
            isLoading = false
            if success {
                message = isCheckIn ? "Checked in!" : "Checked out!"
            } else {
                message = err ?? "Failed"
            }
        }
        await refresh()
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

struct LoginView: View {
    let onSuccess: () -> Void
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showPassword = false
    
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 28).fill(Color.red).frame(width: 88, height: 88)
                                .shadow(color: .red.opacity(0.3), radius: 28, y: 10)
                            Text("K").font(.system(size: 40, weight: .black)).foregroundColor(.white)
                        }
                        
                        Text("Kinematic").font(.system(size: 28, weight: .black)).foregroundColor(.white)
                        Text("FIELD FORCE MANAGEMENT").font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(2)
                    }
                    .padding(.top, 90)
                    
                    Spacer().frame(height: 44)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Welcome back").font(.title2).fontWeight(.heavy).foregroundColor(.white)
                        Text("Sign in to your account").font(.subheadline).foregroundColor(.gray).padding(.bottom, 6)
                        
                        HStack {
                            Image(systemName: "person.fill").foregroundColor(.gray)
                            TextField("Mobile or Email", text: $email)
                                .foregroundColor(.white)
                                .autocapitalization(.none)
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                        
                        HStack {
                            Image(systemName: "lock.fill").foregroundColor(.gray)
                            if showPassword {
                                TextField("App Password", text: $password).foregroundColor(.white)
                            } else {
                                SecureField("App Password", text: $password).foregroundColor(.white)
                            }
                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill").foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                        
                        if !errorMessage.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                                Text(errorMessage).font(.caption).foregroundColor(.red)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(10)
                        }
                        
                        Spacer().frame(height: 4)
                        
                        Button(action: performLogin) {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Sign In")
                                    Image(systemName: "arrow.right.to.line")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                    }
                    .padding(24)
                    .liquidGlass(cornerRadius: 24, opacity: 0.1)
                    .padding(.horizontal, 20)
                    
                    Spacer().frame(height: 24)
                    Text("Kinematic v1.0 · Secured").font(.caption2).foregroundColor(.gray)
                    Spacer().frame(height: 32)
                }
            }
            .ignoresSafeArea(.keyboard)
        }
    }
    
    private func performLogin() {
        isLoading = true
        Task {
            let phone = email.allSatisfy({ $0.isNumber }) ? email : nil
            let em = phone == nil ? email : ""
            let (success, error) = await KinematicRepository.shared.login(email: em, phone: phone, pass: password)
            await MainActor.run {
                isLoading = false
                if success {
                    onSuccess()
                } else {
                    errorMessage = error ?? "Failed to login"
                }
            }
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showSOS = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabView(selection: $selectedTab) {
                    HomeView().tag(0)
                    AttendanceView().tag(1)
                    RoutePlansView().tag(2)
                    ActivityFeedView().tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                
                // Custom Tab Bar (Parity with Android Navigation)
                HStack(spacing: 0) {
                    TabBtn(i: "house.fill", l: "Home", s: selectedTab == 0) { selectedTab = 0 }
                    TabBtn(i: "person.text.rectangle.fill", l: "Attendance", s: selectedTab == 1) { selectedTab = 1 }
                    TabBtn(i: "map.fill", l: "Route", s: selectedTab == 2) { selectedTab = 2 }
                    TabBtn(i: "clock.arrow.circlepath", l: "Activity", s: selectedTab == 3) { selectedTab = 3 }
                }
                .padding(.top, 12)
                .padding(.bottom, 30)
                .background(Color.black.opacity(0.8))
                .overlay(Rectangle().frame(height: 0.5).foregroundColor(.white.opacity(0.1)), alignment: .top)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct TabBtn: View {
    let i: String; let l: String; let s: Bool; let a: () -> Void
    var body: some View {
        Button(action: a) {
            VStack(spacing: 4) {
                Image(systemName: i).font(.system(size: 20))
                Text(l).font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(s ? .red : .gray)
            .frame(maxWidth: .infinity)
        }
    }
}

struct HomeView: View {
    @StateObject var vm = HomeViewModel()
    @EnvironmentObject var locationService: LocationTrackingService
    
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            ScrollView {
                VStack(spacing: 20) {
                    // Header (Hello User)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hello,").font(.subheadline).foregroundColor(.gray)
                            Text(Session.currentUser?.name ?? "Field Executive").font(.title2).fontWeight(.black).foregroundColor(.white)
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            Button(action: { Task { await vm.refresh() } }) {
                                Image(systemName: "arrow.clockwise").padding(10).background(Color.white.opacity(0.1)).foregroundColor(.white).clipShape(Circle())
                            }
                            Button(action: { AppState.shared.logout() }) {
                                Image(systemName: "power").padding(10).background(Color.red.opacity(0.8)).foregroundColor(.white).clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal, 25)
                    .padding(.top, 60)
                    
                    // Selfie Status Card
                    SelfieStatusCard(record: vm.data?.today)
                        .padding(.horizontal, 20)
                    
                    // Stats Row
                    HStack(spacing: 12) {
                        StatTile(label: "Stores", value: "\(vm.data?.routePlan?.flatMap { $0.outlets }.count ?? 0)", icon: "storefront.fill", color: .blue)
                        StatTile(label: "Visited", value: "\(vm.data?.routePlan?.flatMap { $0.outlets }.filter { $0.status == "visited" }.count ?? 0)", icon: "checkmark.seal.fill", color: .green)
                        StatTile(label: "Forms", value: "\(vm.data?.summary?.tffCount ?? 0)", icon: "doc.text.fill", color: .purple)
                    }
                    .padding(.horizontal, 20)
                    
                    // Today's Session
                    SessionCard(record: vm.data?.today)
                        .padding(.horizontal, 20)
                    
                    // Route Preview
                    VStack(alignment: .leading, spacing: 15) {
                        Text("TODAY'S ROUTE").font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(1)
                        
                        if let outlets = vm.data?.routePlan?.flatMap({ $0.outlets }).prefix(3), !outlets.isEmpty {
                            ForEach(outlets) { outlet in
                                RoutePreviewRow(outlet: outlet)
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
    let record: AttendanceRecord?
    var isIn: Bool { record?.checkinAt != nil && record?.checkoutAt == nil }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(isIn ? "Shift Active" : "Daily Selfie Required").font(.headline).foregroundColor(.white)
                if isIn {
                    Text("Ongoing since \(formatTime(record?.checkinAt))").font(.caption).foregroundColor(.gray)
                }
            }
            Spacer()
            // Simplified button for now
            Text(isIn ? "Selfie Out" : "Selfie In")
                .font(.caption).fontWeight(.bold).foregroundColor(.white)
                .padding(.horizontal, 15).padding(.vertical, 8)
                .background(isIn ? Color.red : Color.blue).cornerRadius(20)
        }
        .padding(18)
        .background(Color.white.opacity(0.08))
        .cornerRadius(22)
    }
}

struct StatTile: View {
    let label: String; let value: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(color).font(.headline)
            VStack(spacing: 2) {
                Text(value).font(.title3).fontWeight(.black).foregroundColor(.white)
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
                    Text(formatTime(record?.checkinAt)).font(.headline).foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Check-Out").font(.caption).foregroundColor(.gray)
                    Text(formatTime(record?.checkoutAt)).font(.headline).foregroundColor(.white)
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

struct RoutePreviewRow: View {
    let outlet: RouteOutlet
    var body: some View {
        HStack {
            Image(systemName: outlet.status == "visited" ? "checkmark.circle.fill" : "storefront")
                .foregroundColor(outlet.status == "visited" ? .green : .gray)
            VStack(alignment: .leading) {
                Text(outlet.storeName).font(.subheadline).fontWeight(.bold).foregroundColor(.white)
                if !outlet.activities.isEmpty {
                    Text("\(outlet.activities.count) tasks assigned").font(.system(size: 10)).foregroundColor(.gray)
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
    @StateObject var vm = RoutePlansViewModel()
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Today's Route").font(.largeTitle).fontWeight(.black).foregroundColor(.white).padding(.top, 60).padding(.horizontal)
                    
                    if vm.isLoading && vm.plans.isEmpty {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 50)
                    } else if vm.plans.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 50)).foregroundColor(.gray)
                            Text("No routes planned for today").foregroundColor(.gray)
                        }.frame(maxWidth: .infinity).padding(.top, 100)
                    } else {
                        ForEach(vm.plans) { plan in
                            ForEach(plan.outlets) { outlet in
                                OutletCard(outlet: outlet)
                            }
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

struct OutletCard: View {
    let outlet: RouteOutlet
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(outlet.storeName).font(.headline).foregroundColor(.white)
                Spacer()
                if outlet.status == "visited" {
                    Text("COMPLETED").font(.system(size: 8, weight: .bold)).padding(5).background(Color.green.opacity(0.2)).foregroundColor(.green).cornerRadius(5)
                }
            }
            Text(outlet.address ?? "No address provided").font(.caption).foregroundColor(.gray)
            
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "list.clipboard").font(.caption)
                    Text("\(outlet.activities.count) Tasks").font(.caption).fontWeight(.bold)
                }.foregroundColor(.purple)
                Spacer()
                Text(outlet.status == "visited" ? "View Details" : "Start Visit")
                    .font(.caption2).fontWeight(.black).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(outlet.status == "visited" ? Color.gray.opacity(0.2) : Color.red).foregroundColor(.white).cornerRadius(15)
            }
            .padding(.top, 5)
        }
        .padding(20).liquidGlass().padding(.horizontal, 20)
    }
}

struct AttendanceView: View {
    @StateObject var vm = AttendanceViewModel()
    @EnvironmentObject var locationService: LocationTrackingService
    
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            ScrollView {
                VStack(spacing: 25) {
                    Text("Attendance").font(.largeTitle).fontWeight(.black).foregroundColor(.white).padding(.top, 60).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                    
                    // Main Status
                    VStack(spacing: 20) {
                        Image(systemName: vm.today?.checkinAt != nil ? "checkmark.shield.fill" : "person.fill.viewfinder")
                            .font(.system(size: 60)).foregroundColor(vm.today?.checkinAt != nil ? .green : .red)
                        VStack(spacing: 5) {
                            Text(vm.today?.checkinAt != nil ? "Currently Active" : "Not Logged In").font(.title3).fontWeight(.bold).foregroundColor(.white)
                            Text("Your location is being tracked").font(.caption).foregroundColor(.gray)
                        }
                        
                        Button(action: { 
                            if let loc = locationService.lastLocation { Task { await vm.toggleAttendance(loc: loc) } }
                        }) {
                            if vm.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(vm.today?.checkinAt != nil ? "CHECK OUT" : "CHECK IN").fontWeight(.black)
                            }
                        }
                        .frame(maxWidth: .infinity).padding().background(vm.today?.checkinAt != nil ? Color.gray.opacity(0.3) : Color.red).foregroundColor(.white).cornerRadius(15)
                    }
                    .padding(30).liquidGlass().padding(.horizontal, 20)
                    
                    // History Header
                    Text("RECENT HISTORY").font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(1).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 25)
                    
                    VStack(spacing: 12) {
                        EmptyHistoryRow() // Placeholder for actual history list
                    }.padding(.horizontal, 20)
                    
                    Spacer().frame(height: 120)
                }
            }
        }
        .onAppear { Task { await vm.refresh() } }
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
    @StateObject var vm = ActivityFeedViewModel()
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Work Feed").font(.largeTitle).fontWeight(.black).foregroundColor(.white).padding(.top, 60).padding(.horizontal)
                    
                    if vm.isLoading && vm.items.isEmpty {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 50)
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
                Text(item.outletName ?? "General Submission").font(.subheadline).fontWeight(.bold).foregroundColor(.white)
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
