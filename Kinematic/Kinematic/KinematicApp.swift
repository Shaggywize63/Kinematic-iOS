import SwiftUI
import Combine
import CoreLocation

// --- MODELS ---
struct User: Codable, Identifiable {
    let id, name, role: String
    let email: String?
    let mobile: String?
    let organizationName: String?
    enum CodingKeys: String, CodingKey {
        case id, name, email, role, mobile
        case organizationName = "org_id"
    }
}

// --- APP STATE ---
class AppState: ObservableObject {
    @Published var isAuthenticated = Session.isAuthenticated
    @Published var isSplashScreenActive = true
    
    static let shared = AppState()
    
    func checkAuth() {
        self.isAuthenticated = Session.isAuthenticated
    }
    
    func logout() {
        Session.logout()
        self.isAuthenticated = false
    }
}

// Login Models
struct LoginResponseModel: Codable {
    let success: Bool
    let data: LoginData?
    let error: String?
}

struct LoginData: Codable {
    let accessToken: String
    let user: User
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case user
    }
}

// Attendance Models
struct ApiResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: String?
}

struct AttendanceRecord: Codable {
    let id, date: String
    let status: String?
    let checkinAt: String?
    let checkoutAt: String?
    let totalHours: Double?
    let checkinSelfieUrl: String?
    let checkoutSelfieUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id, date, status
        case checkinAt = "checkin_at"
        case checkoutAt = "checkout_at"
        case totalHours = "total_hours"
        case checkinSelfieUrl = "checkin_selfie_url"
        case checkoutSelfieUrl = "checkout_selfie_url"
    }
}

struct AnalyticsSummary: Codable {
    let tffCount: Int
    enum CodingKeys: String, CodingKey {
        case tffCount = "tff_count"
    }
}

struct MotivationQuote: Codable {
    let quote: String?
    let author: String?
}

struct MobileHomeResponse: Codable {
    let today: AttendanceRecord?
    let summary: AnalyticsSummary?
    let routePlan: [RoutePlan]?
    let unreadCount: Int?
    let quote: MotivationQuote?
    
    enum CodingKeys: String, CodingKey {
        case today, summary, quote, unreadCount
        case routePlan = "route_plans"
    }
}

struct ActivityFeedItem: Codable, Identifiable {
    let id: String
    let outletName: String?
    let isConverted: Bool
    let submittedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, isConverted
        case outletName = "outlet_name"
        case submittedAt = "submitted_at"
    }
}

struct RoutePlan: Codable, Identifiable {
    let id, date, status: String
    var outlets: [RouteOutlet]
}

struct RouteOutlet: Codable, Identifiable {
    let id, storeId, storeName: String
    let address: String?
    let status: String
    var activities: [RouteActivity]
    enum CodingKeys: String, CodingKey {
        case id, status, activities, address
        case storeId = "store_id"
        case storeName = "store_name"
    }
}

struct RouteActivity: Codable, Identifiable {
    let id, title: String
    let description: String?
    let type, status: String
}

// --- SERVICES ---
class Session: ObservableObject {
    static let shared = Session()
    
    static var sharedToken: String {
        get { UserDefaults.standard.string(forKey: "auth_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "auth_token") }
    }
    
    static var isDemoMode: Bool {
        get { UserDefaults.standard.bool(forKey: "is_demo_mode") }
        set { UserDefaults.standard.set(newValue, forKey: "is_demo_mode") }
    }
    
    static var isAuthenticated: Bool { !sharedToken.isEmpty || isDemoMode }
    static var currentUser: User? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "current_user") else { return nil }
            return try? JSONDecoder().decode(User.self, from: data)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "current_user")
            }
        }
    }
    static func logout() { 
        sharedToken = ""
        currentUser = nil
        isDemoMode = false
    }
}

class LocationTrackingService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationTrackingService()
    private let locationManager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        #if !targetEnvironment(simulator)
        locationManager.allowsBackgroundLocationUpdates = true
        #endif
    }
    func requestPermissions() { locationManager.requestWhenInUseAuthorization() }
    func startTracking() { locationManager.startUpdatingLocation() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.lastLocation = locations.last
    }
}

class KinematicRepository {
    static let shared = KinematicRepository()
    private let baseURL = "https://kinematic-production.up.railway.app/api/v1"
    
    func login(email: String, phone: String?, pass: String) async -> (Bool, String?) {
        // --- DEMO MODE INTERCEPTION ---
        if email.lowercased() == "demo@kinematic.com" {
            await MainActor.run {
                Session.isDemoMode = true
                Session.sharedToken = "demo-token-123"
                Session.currentUser = User(id: "demo-id", name: "Demo Executive", role: "Field Executive", email: "demo@kinematic.com", mobile: "9999999999", organizationName: "Kinematic Demo")
                AppState.shared.checkAuth()
            }
            return (true, nil)
        }
        
        guard let url = URL(string: "\(baseURL)/auth/login") else { return (false, "Invalid URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var payload: [String: String] = ["password": pass]
        if !email.isEmpty { payload["email"] = email }
        if let p = phone, !p.isEmpty { payload["mobile"] = p }
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let result = try JSONDecoder().decode(LoginResponseModel.self, from: data)
            if result.success, let t = result.data?.accessToken {
                await MainActor.run { 
                    Session.sharedToken = t
                    Session.currentUser = result.data?.user
                    AppState.shared.checkAuth()
                }
                return (true, nil)
            }
            return (false, result.error ?? "Login failed")
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    func markAttendance(isCheckIn: Bool, lat: Double, lng: Double) async -> (Bool, String?) {
        if Session.isDemoMode { return (true, nil) }
        
        let endpoint = isCheckIn ? "checkin" : "checkout"
        guard let url = URL(string: "\(baseURL)/attendance/\(endpoint)") else { return (false, "Invalid URL") }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = ["latitude": lat, "longitude": lng]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let result = try JSONDecoder().decode(ApiResponse<AttendanceRecord>.self, from: data)
            if result.success { return (true, nil) }
            return (false, result.error ?? "Failed to mark attendance")
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    func getMobileHome() async -> MobileHomeResponse? {
        if Session.isDemoMode { return mockMobileHome() }
        
        guard let url = URL(string: "\(baseURL)/analytics/mobile-home") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return try JSONDecoder().decode(MobileHomeResponse.self, from: data)
        } catch {
            print("Home fetch error: \(error)")
            return nil
        }
    }
    
    func getFeed() async -> [ActivityFeedItem] {
        if Session.isDemoMode { return mockFeed() }
        
        guard let url = URL(string: "\(baseURL)/feed") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return (try? JSONDecoder().decode([ActivityFeedItem].self, from: data)) ?? []
        } catch {
            return []
        }
    }
    
    func fetchMyRoutePlan() async -> [RoutePlan] {
        if Session.isDemoMode { return mockRoute() }
        
        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        guard let url = URL(string: "\(baseURL)/route-plan/me?date=\(date)") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = (try? await URLSession.shared.data(for: req)) ?? (Data(), URLResponse())
        return (try? JSONDecoder().decode([RoutePlan].self, from: data)) ?? []
    }
    
    // --- MOCK DATA PROVIDER ---
    private func mockMobileHome() -> MobileHomeResponse {
        return MobileHomeResponse(
            today: AttendanceRecord(id: "1", date: "2024-04-08", status: "present", checkinAt: "2024-04-08T09:00:00Z", checkoutAt: nil, totalHours: 4.5, checkinSelfieUrl: nil, checkoutSelfieUrl: nil),
            summary: AnalyticsSummary(tffCount: 12),
            routePlan: mockRoute(),
            unreadCount: 5,
            quote: MotivationQuote(quote: "Success is not final; failure is not fatal: it is the courage to continue that counts.", author: "Winston Churchill")
        )
    }
    
    private func mockFeed() -> [ActivityFeedItem] {
        return [
            ActivityFeedItem(id: "1", outletName: "Reliance Fresh, Koramangala", isConverted: true, submittedAt: "2024-04-08T10:30:00Z"),
            ActivityFeedItem(id: "2", outletName: "Big Bazaar, Indiranagar", isConverted: false, submittedAt: "2024-04-08T11:15:00Z"),
            ActivityFeedItem(id: "3", outletName: "Star Market, Whitefield", isConverted: true, submittedAt: "2024-04-08T12:00:00Z"),
            ActivityFeedItem(id: "4", outletName: "Nature's Basket, MG Road", isConverted: true, submittedAt: "2024-04-08T13:45:00Z"),
            ActivityFeedItem(id: "5", outletName: "Spencer's, JP Nagar", isConverted: false, submittedAt: "2024-04-08T14:30:00Z")
        ]
    }
    
    private func mockRoute() -> [RoutePlan] {
        let outlets = [
            RouteOutlet(id: "o1", storeId: "s1", storeName: "Global Mart", address: "123 Outer Ring Rd", status: "visited", activities: [
                RouteActivity(id: "a1", title: "Shelf Stocking", description: "Check beverage section", type: "stock", status: "completed")
            ]),
            RouteOutlet(id: "o2", storeId: "s2", storeName: "Metro Corner", address: "456 Inner Circle", status: "pending", activities: [
                RouteActivity(id: "a2", title: "Merchandising", description: "Put up new posters", type: "promo", status: "pending"),
                RouteActivity(id: "a3", title: "Price Audit", description: "Verify yogurt prices", type: "audit", status: "pending")
            ]),
            RouteOutlet(id: "o3", storeId: "s3", storeName: "City Supermarket", address: "Market St, Plaza", status: "pending", activities: [
                RouteActivity(id: "a4", title: "Inventory", description: "Full warehouse check", type: "stock", status: "pending")
            ])
        ]
        return [RoutePlan(id: "p1", date: "2024-04-08", status: "active", outlets: outlets)]
    }
}

@main
struct KinematicApp: App {
    @StateObject private var locationService = LocationTrackingService.shared
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if appState.isSplashScreenActive {
                    SplashScreenView()
                } else {
                    ContentView()
                        .environmentObject(locationService)
                        .environmentObject(appState)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                locationService.requestPermissions()
                if Session.isAuthenticated { locationService.startTracking() }
                
                // Show splash for 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.spring()) {
                        appState.isSplashScreenActive = false
                    }
                }
            }
        }
    }
}

struct SplashScreenView: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30).fill(Color.red).frame(width: 120, height: 120)
                        .shadow(color: .red.opacity(0.4), radius: 20)
                        .scaleEffect(animate ? 1.0 : 0.8)
                    Text("K").font(.system(size: 60, weight: .black)).foregroundColor(.white)
                        .offset(y: animate ? 0 : 20)
                }
                
                Text("KINEMATIC").font(.system(size: 32, weight: .black)).foregroundColor(.white).tracking(6)
                    .opacity(animate ? 1 : 0)
                Text("FIELD FORCE EVOLUTION").font(.caption2).fontWeight(.black).foregroundColor(.gray).tracking(4)
                    .opacity(animate ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 50, damping: 5).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}
