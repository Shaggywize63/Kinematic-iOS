import SwiftUI
import Combine
import CoreLocation
import AVFoundation
import Foundation

// --- MODELS ---
struct User: Codable, Identifiable {
    let id: String
    let name: String
    let role: String
    let email: String?
    let mobile: String?
    let orgId: String?
    let clientId: String?
    /// Profile picture URL stored on users.avatar_url. Optional — the
    /// ProfileView falls back to a coloured initial circle when absent.
    let avatarUrl: String?
    /// Per-client SKU module IDs (Field Force / CRM / Distribution + universal).
    /// Empty list = legacy session, treat as full access for backwards compat.
    let enabledModules: [String]
    /// Package SKUs the client owns: field_force, distribution, crm, business, system, people, audit.
    let enabledPackages: [String]
    /// Legacy per-user RBAC grants from user_module_permissions.
    let permissions: [String]
    /// Org-role designation (e.g. "Consumer Champion", "Business Manager").
    /// Source of truth is `org_roles.name` joined via `users.org_role_id`.
    let orgRoleName: String?
    /// Data-scope of the user's org role: own | team | all. Used by the CRM
    /// UI to gate write actions — reps with 'own' scope can only see leads
    /// they own, so reassignment must NOT be offered (it would hide the
    /// record from them entirely).
    let orgRoleDataScope: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, role, mobile, permissions
        case orgId = "org_id"
        case clientId = "client_id"
        case avatarUrl = "avatar_url"
        case enabledModules = "enabled_modules"
        case enabledPackages = "enabled_packages"
        case orgRoleName = "org_role_name"
        case orgRoleDataScope = "org_role_data_scope"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        name            = try c.decode(String.self, forKey: .name)
        role            = try c.decode(String.self, forKey: .role)
        email           = try c.decodeIfPresent(String.self, forKey: .email)
        mobile          = try c.decodeIfPresent(String.self, forKey: .mobile)
        orgId           = try c.decodeIfPresent(String.self, forKey: .orgId)
        clientId        = try c.decodeIfPresent(String.self, forKey: .clientId)
        avatarUrl       = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        enabledModules  = (try? c.decode([String].self, forKey: .enabledModules)) ?? []
        enabledPackages = (try? c.decode([String].self, forKey: .enabledPackages)) ?? []
        permissions     = (try? c.decode([String].self, forKey: .permissions)) ?? []
        orgRoleName     = try c.decodeIfPresent(String.self, forKey: .orgRoleName)
        orgRoleDataScope = try c.decodeIfPresent(String.self, forKey: .orgRoleDataScope)
    }
}

// MARK: - Entitlement helpers
extension User {
    /// True for legacy sessions stored before /auth/me started returning entitlements.
    /// Treated as full access so we never lock out an existing user mid-deploy.
    var isLegacySession: Bool { enabledModules.isEmpty && enabledPackages.isEmpty }
    func hasModule(_ id: String)  -> Bool { isLegacySession || enabledModules.contains(id) }
    func hasPackage(_ pkg: String) -> Bool { isLegacySession || enabledPackages.contains(pkg) }
    var hasFieldForce:  Bool { hasPackage("field_force") }
    var hasCrm:         Bool { hasPackage("crm") }
    var hasDistribution: Bool { hasPackage("distribution") }
    /// True when a client purchased only CRM. Replaces the manual `crm_only_mode`
    /// AppStorage hack; the app auto-flips into CRM-only mode when this is true.
    var isCrmOnly: Bool {
        !isLegacySession && hasCrm && !hasFieldForce && !hasDistribution
    }
}

// --- APP STATE ---
enum SecondaryRoute: String, Identifiable {
    case profile, broadcast, learning, settings, camera
    case leaderboard, notifications, grievance, visitlog, stock, sos, activity
    // Distribution module
    case orderHistory, orderCart, orderReview, orderDetail
    case paymentCollect, returns, distributorStock, secondarySales
    var id: String { rawValue }

    /// Which package SKU this route belongs to. Universal routes return `nil`
    /// and are always available. Used by SecondaryScreenHost + SideMenuView to
    /// hide / block sheets the user's client hasn't purchased.
    var requiredPackage: String? {
        switch self {
        // Universal — every client gets these
        case .profile, .settings, .learning, .notifications, .sos:
            return nil
        // Field Force
        case .broadcast, .leaderboard, .grievance, .visitlog, .stock, .activity, .camera:
            return "field_force"
        // Distribution / Supply Chain
        case .orderHistory, .orderCart, .orderReview, .orderDetail,
             .paymentCollect, .returns, .distributorStock, .secondarySales:
            return "distribution"
        }
    }

    func isAvailable(for user: User?) -> Bool {
        guard let pkg = requiredPackage else { return true }
        return user?.hasPackage(pkg) ?? true   // missing user → assume legacy / open
    }
}

struct ModalRoute: Identifiable {
    let id = UUID()
    let route: SecondaryRoute
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

class KiniAppState: ObservableObject {
    static let shared = KiniAppState()

    /// Persisted across the auth flip so LoginView can show the user
    /// "you got kicked off because another device signed in" AFTER they're
    /// bounced back to the login screen. Cleared by the next successful
    /// login or via `clearSessionKickedMsg()`.
    @Published var sessionKickedMsg: String? = nil
    func clearSessionKickedMsg() { sessionKickedMsg = nil }

    @Published var isAuthenticated = Session.isAuthenticated
    @Published var selectedTab: Int = 0
    @Published var selectedOutlet: RouteOutlet? = nil
    @Published var attendanceVM = AttendanceViewModel()
    
    // --- Shared Home Data (Parity with Android AppViewModel) ---
    @Published var today: AttendanceRecord? = nil
    @Published var summary: AnalyticsSummary? = nil
    @Published var quote: MotivationQuote? = nil
    
    // --- Navigation & UI ---
    @Published var showSideMenu = false
    @Published var activeSecondaryRoute: ModalRoute? = nil
    /// Last tapped push notification's data dict (type / lead_id / deal_id /
    /// task_id). Set by PushAppDelegate on tap; kept for deeper deep-linking.
    @Published var pendingPushData: [String: String]? = nil
    /// Set true when the API starts returning 401s. UI can read this to
    /// surface a non-destructive "session expired, please sign in" prompt
    /// without wiping the user's local check-in state.
    @Published var needsReAuth: Bool = false
    @Published var theme: AppTheme = .system {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "app_theme") }
    }
    
    // --- Visit Management ---
    @Published var activeVisitId: String? = nil
    @Published var activeVisitOutletId: String? = nil
    @Published var visitErrorMessage: String? = nil
    @Published var selectedActivity: RouteActivity? = nil
    
    // --- Navigation Morphing (iOS 26 Liquid Glass) ---
    @Published var isTabBarExpanded: Bool = true
    private var lastScrollY: CGFloat = 0
    
    // --- Ironclad Aura Flow (Flat State) ---
    @Published var capturedSelfie: UIImage? = nil
    
    // --- GLOBAL FEEDBACK ---
    @Published var showGlobalSuccess = false
    @Published var lastSuccessMessage = "Data submitted successfully"
    
    func triggerCamera() {
        print("📸 [KiniAppState] triggerCamera() - High Reliability Signal (UUID Trigger)")
        DispatchQueue.main.async {
            self.activeSecondaryRoute = ModalRoute(route: .camera)
        }
    }
    
    func updateScrollProgress(_ y: CGFloat) {
        let delta = y - lastScrollY
        if abs(delta) > 5 { // Threshold to avoid jitter
            if delta > 0 && isTabBarExpanded {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isTabBarExpanded = false }
            } else if delta < 0 && !isTabBarExpanded {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isTabBarExpanded = true }
            }
            lastScrollY = y
        }
    }
    
    init() {
        // Load persisted theme or follow system appearance
        let savedTheme = UserDefaults.standard.string(forKey: "app_theme") ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: savedTheme) ?? .system
        
        // --- PERFORMANCE: Immediate Cache Restoration ---
        if let cachedHome = KinematicRepository.shared.loadCached(MobileHomeResponse.self, forKey: "cached_mobile_home_payload") {
            self.today = cachedHome.today
            self.summary = cachedHome.summary
            self.quote = cachedHome.quote
            print("🚀 [KiniAppState] Instantly restored state from cache.")
        }
    }
    
    func checkAuth() {
        self.isAuthenticated = Session.isAuthenticated
    }
    
    func logout() {
        Session.logout()
        OutletCache.shared.invalidateAll()
        self.isAuthenticated = false
        self.selectedTab = 0
        self.showSideMenu = false
        self.activeSecondaryRoute = nil
        stopTrackingTimer()
    }
    
    // --- LIVE TRACKING ENGINE ---
    private var trackingTimer: Timer?
    
    func startTrackingTimer() {
        guard trackingTimer == nil else { return }
        print("📡 [KiniAppState] Initializing Live Tracking Cycle (5min)")
        
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.performLivePing()
            }
        }
    }
    
    func stopTrackingTimer() {
        print("🛑 [KiniAppState] Terminating Live Tracking Cycle")
        trackingTimer?.invalidate()
        trackingTimer = nil
    }
    
    private func performLivePing() async {
        // Gate 1: Check Auth & Shift Status
        guard isAuthenticated, let shift = today, shift.isIn else { 
            print("💤 [Tracking] Shift inactive. Skipping ping.")
            return 
        }
        
        // Gate 2: Fetch Coordinates
        guard let location = LocationTrackingService.shared.lastLocation else {
            print("⚠️ [Tracking] No GPS fix. Skipping ping.")
            return
        }
        
        // Gate 3: Fetch Battery
        let battery = Int(UIDevice.current.batteryLevel * 100)
        
        print("📍 [Tracking] Sending Ping: \(location.coordinate.latitude), \(location.coordinate.longitude) | Battery: \(battery)%")
        _ = await KinematicRepository.shared.sendLiveTrackingPing(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            battery: battery
        )
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
    /// Supabase refresh token. Long-lived (30 days, rotating). We persist
    /// it so the access token can be silently refreshed before/after it
    /// expires, keeping the user signed in until they explicitly log out.
    let refreshToken: String?
    /// Single-device-login session UUID. The backend rotates this on every
    /// mobile login and the client echoes it back as X-Session-Id on every
    /// authenticated request. Mismatch → backend returns 401 DEVICE_REPLACED
    /// and this device is force-logged-out by KiniAppState. Null on legacy
    /// or demo logins where enforcement is skipped.
    let sessionId: String?
    let user: User
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case sessionId = "session_id"
        case user
    }
}

// Attendance Models
// Flexible Codable type that accepts any JSON value shape
struct AnyCodableValue: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodableValue].self) {
            value = dict
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let num = value as? Double { try container.encode(num) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else { try container.encodeNil() }
    }
}

struct ApiResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: String?
    let message: String?
}

// MARK: - My Day (rep agenda) — GET /crm/my-day
//
// Backend returns the rep's agenda for today: activities due today,
// overdue + upcoming activities, headline counts and open leads near
// the device (distance_km present only when lat/lng were sent).
struct MyDayResponse: Codable {
    let date: String?
    let counts: MyDayCounts?
    let activitiesToday: [MyDayActivity]?
    let overdue: [MyDayActivity]?
    let upcoming: [MyDayActivity]?
    let leads: [MyDayLead]?

    enum CodingKeys: String, CodingKey {
        case date, counts, overdue, upcoming, leads
        case activitiesToday = "activities_today"
    }
}

struct MyDayCounts: Codable {
    let today: Int?
    let overdue: Int?
    let upcoming: Int?
    let openLeads: Int?

    enum CodingKeys: String, CodingKey {
        case today, overdue, upcoming
        case openLeads = "open_leads"
    }
}

struct MyDayActivity: Codable, Identifiable, Hashable {
    let id: String
    let type: String?
    let subject: String?
    let status: String?
    let dueAt: String?
    let priority: String?
    let leadId: String?
    let dealId: String?

    enum CodingKeys: String, CodingKey {
        case id, type, subject, status, priority
        case dueAt = "due_at"
        case leadId = "lead_id"
        case dealId = "deal_id"
    }
}

struct MyDayLead: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let status: String?
    // `city` is intentionally NOT decoded/exposed here — it's a built-in
    // lead field gated by the field-override contract (see CLAUDE.md), so
    // the My Day screen never renders it.
    let latitude: Double?
    let longitude: Double?
    let createdAt: String?
    let distanceKm: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, status, latitude, longitude
        case createdAt = "created_at"
        case distanceKm = "distance_km"
    }
}

struct AttendanceRecord: Codable {
    let id: String?
    let date: String?
    var status: String?
    var checkinAt: String?
    var checkoutAt: String?
    let totalHours: Double?
    let checkinSelfieUrl: String?
    let checkoutSelfieUrl: String?
    let checkinLatitude: Double?
    let checkinLongitude: Double?
    let checkoutLatitude: Double?
    let checkoutLongitude: Double?
    var firstCheckinAt: String?
    var lastCheckoutAt: String?
    let checkinAddress: String?
    let checkoutAddress: String?
    let totalDuration: Int?

    enum CodingKeys: String, CodingKey {
        case id, date, status
        case checkinAt = "checkin_at"
        case checkoutAt = "checkout_at"
        case checkInAt = "check_in_at"
        case checkOutAt = "check_out_at"
        case totalHours = "total_hours"
        case totalHrs = "total_hrs"
        case checkinSelfieUrl = "checkin_selfie_url"
        case checkoutSelfieUrl = "checkout_selfie_url"
        case checkInSelfieUrl = "check_in_selfie_url"
        case checkOutSelfieUrl = "check_out_selfie_url"
        case checkinLatitude = "checkin_lat"
        case checkinLongitude = "checkin_lng"
        case checkoutLatitude = "checkout_lat"
        case checkoutLongitude = "checkout_lng"
        case checkinAddress = "checkin_address"
        case checkoutAddress = "checkout_address"
        case firstCheckinAt = "first_checkin_at"
        case lastCheckoutAt = "last_checkout_at"
        case totalDuration = "total_duration"
        case location
    }

    init(
        id: String?,
        date: String?,
        status: String?,
        checkinAt: String?,
        checkoutAt: String?,
        totalHours: Double?,
        checkinSelfieUrl: String?,
        checkoutSelfieUrl: String?,
        checkinLatitude: Double? = nil,
        checkinLongitude: Double? = nil,
        checkoutLatitude: Double? = nil,
        checkoutLongitude: Double? = nil,
        checkinAddress: String? = nil,
        checkoutAddress: String? = nil,
        firstCheckinAt: String? = nil,
        lastCheckoutAt: String? = nil,
        totalDuration: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.status = status
        self.checkinAt = checkinAt
        self.checkoutAt = checkoutAt
        self.totalHours = totalHours
        self.checkinSelfieUrl = checkinSelfieUrl
        self.checkoutSelfieUrl = checkoutSelfieUrl
        self.checkinLatitude = checkinLatitude
        self.checkinLongitude = checkinLongitude
        self.checkoutLatitude = checkoutLatitude
        self.checkoutLongitude = checkoutLongitude
        self.checkinAddress = checkinAddress
        self.checkoutAddress = checkoutAddress
        self.firstCheckinAt = firstCheckinAt
        self.lastCheckoutAt = lastCheckoutAt
        self.totalDuration = totalDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyString(forKey: .id)
        date = container.decodeLossyString(forKey: .date)
        status = container.decodeLossyString(forKey: .status)
        
        checkinAt = container.decodeLossyString(forKey: .checkinAt)
            ?? container.decodeLossyString(forKey: .checkInAt)
        checkoutAt = container.decodeLossyString(forKey: .checkoutAt)
            ?? container.decodeLossyString(forKey: .checkOutAt)
            
        totalHours = container.decodeLossyDouble(forKey: .totalHours)
            ?? container.decodeLossyDouble(forKey: .totalHrs)
            
        checkinSelfieUrl = container.decodeLossyString(forKey: .checkinSelfieUrl)
            ?? container.decodeLossyString(forKey: .checkInSelfieUrl)
        checkoutSelfieUrl = container.decodeLossyString(forKey: .checkoutSelfieUrl)
            ?? container.decodeLossyString(forKey: .checkOutSelfieUrl)
            
        checkinLatitude = container.decodeLossyDouble(forKey: .checkinLatitude)
        checkinLongitude = container.decodeLossyDouble(forKey: .checkinLongitude)
        checkoutLatitude = container.decodeLossyDouble(forKey: .checkoutLatitude)
        checkoutLongitude = container.decodeLossyDouble(forKey: .checkoutLongitude)
        
        checkinAddress = container.decodeLossyString(forKey: .checkinAddress)
            ?? container.decodeLossyString(forKey: .location)
        checkoutAddress = container.decodeLossyString(forKey: .checkoutAddress)
        
        firstCheckinAt = container.decodeLossyString(forKey: .firstCheckinAt)
        lastCheckoutAt = container.decodeLossyString(forKey: .lastCheckoutAt)
        totalDuration = container.decodeLossyInt(forKey: .totalDuration)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(checkinAt, forKey: .checkinAt)
        try container.encodeIfPresent(checkoutAt, forKey: .checkoutAt)
        try container.encodeIfPresent(totalHours, forKey: .totalHours)
        try container.encodeIfPresent(checkinSelfieUrl, forKey: .checkinSelfieUrl)
        try container.encodeIfPresent(checkoutSelfieUrl, forKey: .checkoutSelfieUrl)
        try container.encodeIfPresent(checkinLatitude, forKey: .checkinLatitude)
        try container.encodeIfPresent(checkinLongitude, forKey: .checkinLongitude)
        try container.encodeIfPresent(checkoutLatitude, forKey: .checkoutLatitude)
        try container.encodeIfPresent(checkoutLongitude, forKey: .checkoutLongitude)
        try container.encodeIfPresent(checkinAddress, forKey: .checkinAddress)
        try container.encodeIfPresent(checkoutAddress, forKey: .checkoutAddress)
        try container.encodeIfPresent(firstCheckinAt, forKey: .firstCheckinAt)
        try container.encodeIfPresent(lastCheckoutAt, forKey: .lastCheckoutAt)
        try container.encodeIfPresent(totalDuration, forKey: .totalDuration)
    }

    var isIn: Bool {
        checkinAt != nil && checkoutAt == nil
    }
}

struct TrackingPingRequest: Codable {
    let latitude: Double
    let longitude: Double
    let batteryPercentage: Int
    
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case batteryPercentage = "battery_percentage"
    }
}

// Robust ISO Parsing with Fractional Second and SQL fallback
func parseISO(_ s: String?) -> Date? {
    guard let s = s, !s.lowercased().contains("null") else { return nil }
    
    // 1. Try ISO8601 (Strict)
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = f.date(from: s) { return date }
    
    f.formatOptions = [.withInternetDateTime]
    if let date = f.date(from: s) { return date }
    
    // 2. Try Standard SQL Format (yyyy-MM-dd HH:mm:ss)
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)
    
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    if let date = df.date(from: s) { return date }
    
    // 3. Try Date-only fallback for specific server responses
    df.dateFormat = "yyyy-MM-dd"
    return df.date(from: s)
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            let intValue = Int(value)
            return value == Double(intValue) ? String(intValue) : String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return String(value) }
        return nil
    }

    func decodeLossyDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeLossyInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        return nil
    }

    func decodeLossyBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "y"].contains(normalized) { return true }
            if ["false", "0", "no", "n"].contains(normalized) { return false }
        }
        return nil
    }
}

struct UploadResponse: Codable {
    let url: String
    let path: String?
}

struct AnalyticsSummary: Codable {
    var tffCount: Int
    enum CodingKeys: String, CodingKey {
        case tffCount = "tff_count"
    }
}

struct MotivationQuote: Codable {
    let quote: String?
    let author: String?
}

struct BroadcastOption: Codable {
    let label: String
    let value: String
}

struct BroadcastQuestion: Codable, Identifiable {
    let id: String
    let question: String
    let isUrgent: Bool
    var alreadyAnswered: Bool
    let options: [BroadcastOption]
    let createdAt: String?
    let deadlineAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, question, options
        case isUrgent = "is_urgent"
        case alreadyAnswered = "already_answered"
        case createdAt = "created_at"
        case deadlineAt = "deadline_at"
    }
}

struct SubmitAnswerRequest: Codable {
    let selected: Int
}

struct MobileHomeResponse: Codable {
    let today: AttendanceRecord?
    let summary: AnalyticsSummary?
    let routePlan: [RoutePlan]?
    let unreadCount: Int?
    let quote: MotivationQuote?
    var alreadyAnswered: Bool?
    var broadcast: BroadcastQuestion?
    
    enum CodingKeys: String, CodingKey {
        case today, attendance, attendanceToday
        case summary, quote, broadcast
        case unreadCount, unread_count
        case alreadyAnswered = "already_answered"
        case routePlan = "routePlan"
        case route_plan
        case routes
    }
    
    init(
        today: AttendanceRecord?,
        summary: AnalyticsSummary?,
        routePlan: [RoutePlan]?,
        unreadCount: Int?,
        quote: MotivationQuote?,
        alreadyAnswered: Bool?,
        broadcast: BroadcastQuestion?
    ) {
        self.today = today
        self.summary = summary
        self.routePlan = routePlan
        self.unreadCount = unreadCount
        self.quote = quote
        self.alreadyAnswered = alreadyAnswered
        self.broadcast = broadcast
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        today = (try? container.decodeIfPresent(AttendanceRecord.self, forKey: .today))
            ?? (try? container.decodeIfPresent(AttendanceRecord.self, forKey: .attendance))
            ?? (try? container.decodeIfPresent(AttendanceRecord.self, forKey: .attendanceToday))

        summary = try? container.decodeIfPresent(AnalyticsSummary.self, forKey: .summary)
        routePlan = (try? container.decodeIfPresent([RoutePlan].self, forKey: .routePlan))
            ?? (try? container.decodeIfPresent([RoutePlan].self, forKey: .route_plan))
            ?? (try? container.decodeIfPresent([RoutePlan].self, forKey: .routes))

        unreadCount = container.decodeLossyInt(forKey: .unreadCount)
            ?? container.decodeLossyInt(forKey: .unread_count)
        quote = try? container.decodeIfPresent(MotivationQuote.self, forKey: .quote)
        alreadyAnswered = container.decodeLossyBool(forKey: .alreadyAnswered)
        broadcast = try? container.decodeIfPresent(BroadcastQuestion.self, forKey: .broadcast)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(today, forKey: .today)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(routePlan, forKey: .routePlan)
        try container.encodeIfPresent(unreadCount, forKey: .unreadCount)
        try container.encodeIfPresent(quote, forKey: .quote)
        try container.encodeIfPresent(alreadyAnswered, forKey: .alreadyAnswered)
        try container.encodeIfPresent(broadcast, forKey: .broadcast)
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

// ── LEARNING MODELS (Parity with Android) ─────────────────
struct LearningProgress: Codable {
    let isCompleted: Bool?
    let progressPct: Int?
    let lastAccessed: String?
    
    enum CodingKeys: String, CodingKey {
        case isCompleted = "is_completed"
        case progressPct = "progress_pct"
        case lastAccessed = "last_accessed"
    }
}

struct LearningMaterial: Codable, Identifiable {
    let id: String
    let title: String
    let category: String?
    let type: String? // video, pdf, image, link
    let fileUrl: String?
    let description: String?
    let isMandatory: Bool?
    let thumbnailUrl: String?
    let myProgress: LearningProgress?
    
    enum CodingKeys: String, CodingKey {
        case id, title, category, type, description
        case fileUrl = "file_url"
        case isMandatory = "is_mandatory"
        case thumbnailUrl = "thumbnail_url"
        case myProgress = "my_progress"
    }
}

// ── FORMS MODELS (Parity with Android) ─────────────────────
struct FormTemplate: Codable {
    let id: String
    let activityId: String
    let name: String
    let description: String?
    let requiresPhoto: Bool
    let requiresGps: Bool
    let fields: [FormField]?
    let pages: [FormPage]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case fields = "form_fields" // Matches Android @SerializedName("form_fields")
        case requiresPhoto = "requires_photo"
        case requiresGps = "requires_gps"
        case activityId = "activity_id"
        case pages = "form_pages"
    }
}

struct FormPage: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let order: Int
    
    enum CodingKeys: String, CodingKey {
        case id, title, description
        case order = "page_order"
    }
}
struct FormField: Codable, Identifiable {
    let id: String
    let label: String
    let fieldKey: String
    let fieldType: String
    let placeholder: String?
    let helpText: String?
    let isRequired: Bool
    let sortOrder: Int?
    let options: [FormOption]?
    let dependsOnId: String?
    let dependsOnValue: String?
    let imageCount: Int?
    let cameraOnly: Bool?
    let pageId: String?
    let keyboardType: String?
    
    enum CodingKeys: String, CodingKey {
        case id, label, placeholder
        case fieldKey = "field_key"
        case fieldType = "field_type"
        case helpText = "help_text"
        case isRequired = "is_required"
        case sortOrder = "sort_order"
        case options = "options"
        case fieldOptions = "field_options"
        case dependsOnId = "depends_on_id"
        case dependsOnValue = "depends_on_value"
        case imageCount = "image_count"
        case cameraOnly = "camera_only"
        case pageId = "page_id"
        case keyboardType = "keyboard_type"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        fieldKey = try container.decode(String.self, forKey: .fieldKey)
        fieldType = try container.decode(String.self, forKey: .fieldType)
        placeholder = try? container.decodeIfPresent(String.self, forKey: .placeholder)
        helpText = try? container.decodeIfPresent(String.self, forKey: .helpText)
        isRequired = (try? container.decodeIfPresent(Bool.self, forKey: .isRequired)) ?? false
        sortOrder = try? container.decodeIfPresent(Int.self, forKey: .sortOrder)
        
        // Options can arrive in 3 formats from the backend:
        // 1. Array of objects: [{"label":"A","value":"a"}]  (FormOption directly)
        // 2. Array of plain strings: ["Option 1","Option 2"]  (DB stores this way)
        // 3. Under key "field_options" instead of "options"
        if let objOptions = try? container.decodeIfPresent([FormOption].self, forKey: .options), !objOptions.isEmpty {
            options = objOptions
        } else if let strOptions = try? container.decodeIfPresent([String].self, forKey: .options), !strOptions.isEmpty {
            options = strOptions.map { FormOption(label: $0, value: $0) }
        } else if let objOptions = try? container.decodeIfPresent([FormOption].self, forKey: .fieldOptions), !objOptions.isEmpty {
            options = objOptions
        } else if let strOptions = try? container.decodeIfPresent([String].self, forKey: .fieldOptions), !strOptions.isEmpty {
            options = strOptions.map { FormOption(label: $0, value: $0) }
        } else {
            options = nil
        }
        
        dependsOnId = try? container.decodeIfPresent(String.self, forKey: .dependsOnId)
        dependsOnValue = try? container.decodeIfPresent(String.self, forKey: .dependsOnValue)
        imageCount = try? container.decodeIfPresent(Int.self, forKey: .imageCount)
        cameraOnly = try? container.decodeIfPresent(Bool.self, forKey: .cameraOnly)
        pageId = try? container.decodeIfPresent(String.self, forKey: .pageId)
        keyboardType = try? container.decodeIfPresent(String.self, forKey: .keyboardType)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(fieldKey, forKey: .fieldKey)
        try container.encode(fieldType, forKey: .fieldType)
        try container.encodeIfPresent(placeholder, forKey: .placeholder)
        try container.encodeIfPresent(helpText, forKey: .helpText)
        try container.encode(isRequired, forKey: .isRequired)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(dependsOnId, forKey: .dependsOnId)
        try container.encodeIfPresent(dependsOnValue, forKey: .dependsOnValue)
        try container.encodeIfPresent(imageCount, forKey: .imageCount)
        try container.encodeIfPresent(cameraOnly, forKey: .cameraOnly)
        try container.encodeIfPresent(pageId, forKey: .pageId)
        try container.encodeIfPresent(keyboardType, forKey: .keyboardType)
    }

    init(id: String, label: String, fieldKey: String, fieldType: String, placeholder: String? = nil, helpText: String? = nil, isRequired: Bool = false, sortOrder: Int? = nil, options: [FormOption]? = nil, dependsOnId: String? = nil, dependsOnValue: String? = nil, imageCount: Int? = nil, cameraOnly: Bool? = nil, pageId: String? = nil, keyboardType: String? = nil) {
        self.id = id
        self.label = label
        self.fieldKey = fieldKey
        self.fieldType = fieldType
        self.placeholder = placeholder
        self.helpText = helpText
        self.isRequired = isRequired
        self.sortOrder = sortOrder
        self.options = options
        self.dependsOnId = dependsOnId
        self.dependsOnValue = dependsOnValue
        self.imageCount = imageCount
        self.cameraOnly = cameraOnly
        self.pageId = pageId
        self.keyboardType = keyboardType
    }
}

struct FormOption: Codable, Identifiable {
    var id: String { "\(label)_\(value)" } // Deterministic identity for ForEach
    let label: String
    let value: String
    
    enum CodingKeys: String, CodingKey {
        case label, value, name, id
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let parsedLabel = container.decodeLossyString(forKey: .label) 
             ?? container.decodeLossyString(forKey: .name) 
             ?? "Option"
        label = parsedLabel
        
        value = container.decodeLossyString(forKey: .value) 
             ?? container.decodeLossyString(forKey: .id) 
             ?? parsedLabel
    }
    
    init(label: String, value: String) {
        self.label = label
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(value, forKey: .value)
    }
}

struct FormSubmissionRequest: Codable {
    let templateId: String?
    let activityId: String?
    let outletId: String?
    let outletName: String?
    let latitude: Double?
    let longitude: Double?
    let submittedAt: String
    let isConverted: Bool?
    let responses: [FormResponse]
    
    enum CodingKeys: String, CodingKey {
        case responses, latitude, longitude
        case templateId = "template_id"
        case activityId = "activity_id"
        case outletId = "outlet_id"
        case outletName = "outlet_name"
        case submittedAt = "submitted_at"
        case isConverted = "is_converted"
    }
}

struct FormResponse: Codable {
    let fieldId: String
    let value: String?
    let photo: String?
    let gps: String?
    
    enum CodingKeys: String, CodingKey {
        case value, photo, gps
        case fieldId = "field_id"
    }
}


struct RoutePlan: Codable, Identifiable {
    let id: String?
    let planDate: String?
    let status: String?
    let activityId: String? // Added for dashboard parity
    let totalOutlets: Int?
    let visitedOutlets: Int?
    let completionPct: Double?
    var outlets: [RouteOutlet]?

    enum CodingKeys: String, CodingKey {
        case id, status, outlets, stores
        case planDate = "plan_date"
        case activityId = "activity_id" // Maps to Android activity_id
        case totalOutlets = "total_outlets"
        case visitedOutlets = "visited_outlets"
        case completionPct = "completion_pct"
        case date
    }

    init(id: String?, planDate: String?, status: String?, activityId: String?, outlets: [RouteOutlet]?,
         totalOutlets: Int? = nil, visitedOutlets: Int? = nil, completionPct: Double? = nil) {
        self.id = id
        self.planDate = planDate
        self.status = status
        self.activityId = activityId
        self.outlets = outlets
        self.totalOutlets = totalOutlets
        self.visitedOutlets = visitedOutlets
        self.completionPct = completionPct
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        planDate = try container.decodeIfPresent(String.self, forKey: .planDate)
            ?? container.decodeIfPresent(String.self, forKey: .date)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        activityId = try container.decodeIfPresent(String.self, forKey: .activityId)
        totalOutlets = try container.decodeIfPresent(Int.self, forKey: .totalOutlets)
        visitedOutlets = try container.decodeIfPresent(Int.self, forKey: .visitedOutlets)
        completionPct = try container.decodeIfPresent(Double.self, forKey: .completionPct)
        outlets = try container.decodeIfPresent([RouteOutlet].self, forKey: .outlets)
            ?? container.decodeIfPresent([RouteOutlet].self, forKey: .stores)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(planDate, forKey: .planDate)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(activityId, forKey: .activityId)
        try container.encodeIfPresent(totalOutlets, forKey: .totalOutlets)
        try container.encodeIfPresent(visitedOutlets, forKey: .visitedOutlets)
        try container.encodeIfPresent(completionPct, forKey: .completionPct)
        try container.encodeIfPresent(outlets, forKey: .outlets)
    }

    /// Computed completion percentage that prefers the server-supplied value
    /// but falls back to local counts so the UI is always populated.
    var derivedCompletionPct: Double {
        if let pct = completionPct { return pct }
        let total = totalOutlets ?? outlets?.count ?? 0
        guard total > 0 else { return 0 }
        let done = visitedOutlets ?? outlets?.filter {
            ($0.status ?? "").lowercased() == "completed" || $0.checkoutAt != nil
        }.count ?? 0
        return Double(done) / Double(total) * 100.0
    }
}

struct RouteOutlet: Codable, Identifiable {
    let rawId: String?
    let storeId: String?
    let storeName: String?
    let address: String?
    let status: String?
    let activityId: String?
    var activities: [RouteActivity]?
    let visitOrder: Int?
    let checkinAt: String?
    let checkoutAt: String?
    let geofenceRadius: Double?
    let isGeofenced: Bool?
    let storeLat: Double?
    let storeLng: Double?

    var id: String { storeId ?? rawId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case status, activities, address, tasks
        case rawId = "id"
        case storeId = "store_id"
        case storeName = "store_name"
        case activityId = "activity_id"
        case name
        case visitOrder = "visit_order"
        case checkinAt = "checkin_at"
        case checkoutAt = "checkout_at"
        case geofenceRadius = "geofence_radius"
        case isGeofenced = "is_geofenced"
        case storeLat = "store_lat"
        case storeLng = "store_lng"
    }

    init(rawId: String?, storeId: String?, storeName: String?, address: String?, status: String?,
         activityId: String?, activities: [RouteActivity]?,
         visitOrder: Int? = nil, checkinAt: String? = nil, checkoutAt: String? = nil,
         geofenceRadius: Double? = nil, isGeofenced: Bool? = nil,
         storeLat: Double? = nil, storeLng: Double? = nil) {
        self.rawId = rawId
        self.storeId = storeId
        self.storeName = storeName
        self.address = address
        self.status = status
        self.activityId = activityId
        self.activities = activities
        self.visitOrder = visitOrder
        self.checkinAt = checkinAt
        self.checkoutAt = checkoutAt
        self.geofenceRadius = geofenceRadius
        self.isGeofenced = isGeofenced
        self.storeLat = storeLat
        self.storeLng = storeLng
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawId = try container.decodeIfPresent(String.self, forKey: .rawId)
        storeId = try container.decodeIfPresent(String.self, forKey: .storeId)
        storeName = try container.decodeIfPresent(String.self, forKey: .storeName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        activityId = try container.decodeIfPresent(String.self, forKey: .activityId)
        activities = try container.decodeIfPresent([RouteActivity].self, forKey: .activities)
            ?? container.decodeIfPresent([RouteActivity].self, forKey: .tasks)
        visitOrder = try container.decodeIfPresent(Int.self, forKey: .visitOrder)
        checkinAt = try container.decodeIfPresent(String.self, forKey: .checkinAt)
        checkoutAt = try container.decodeIfPresent(String.self, forKey: .checkoutAt)
        geofenceRadius = try container.decodeIfPresent(Double.self, forKey: .geofenceRadius)
        isGeofenced = try container.decodeIfPresent(Bool.self, forKey: .isGeofenced)
        storeLat = try container.decodeIfPresent(Double.self, forKey: .storeLat)
        storeLng = try container.decodeIfPresent(Double.self, forKey: .storeLng)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(rawId, forKey: .rawId)
        try container.encodeIfPresent(storeId, forKey: .storeId)
        try container.encodeIfPresent(storeName, forKey: .storeName)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(activityId, forKey: .activityId)
        try container.encodeIfPresent(activities, forKey: .activities)
        try container.encodeIfPresent(visitOrder, forKey: .visitOrder)
        try container.encodeIfPresent(checkinAt, forKey: .checkinAt)
        try container.encodeIfPresent(checkoutAt, forKey: .checkoutAt)
        try container.encodeIfPresent(geofenceRadius, forKey: .geofenceRadius)
        try container.encodeIfPresent(isGeofenced, forKey: .isGeofenced)
        try container.encodeIfPresent(storeLat, forKey: .storeLat)
        try container.encodeIfPresent(storeLng, forKey: .storeLng)
    }
}

struct RouteActivity: Codable, Identifiable {
    let id: String?
    let name: String?
    var status: String? // Changed to var for local state updates
}

// --- SERVICES ---
class Session: ObservableObject {
    static let shared = Session()
    
    static var sharedToken: String {
        get { UserDefaults.standard.string(forKey: "auth_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "auth_token") }
    }

    /// Supabase refresh token. Long-lived. Used by `KinematicRepository.refreshAccessToken`
    /// to silently swap a stale access token for a fresh one, so the user
    /// never gets kicked out unless they explicitly log out.
    static var refreshToken: String {
        get { UserDefaults.standard.string(forKey: "refresh_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "refresh_token") }
    }

    static var isDemoMode: Bool {
        get { UserDefaults.standard.bool(forKey: "is_demo_mode") }
        set { UserDefaults.standard.set(newValue, forKey: "is_demo_mode") }
    }

    /// Number of consecutive 401s where refresh ALSO failed. Stays 0 in
    /// the normal case because each 401 is now resolved by a silent refresh.
    /// We only surface a re-auth prompt once the refresh token itself is
    /// rejected — we no longer force-logout based on this counter.
    static var unauthorizedHits: Int = 0

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
    /// Single-device-login session UUID, written by /auth/login and echoed
    /// back as X-Session-Id on every authenticated request. Stored in
    /// UserDefaults (matches sharedToken / refreshToken so cold-start
    /// restores all three together). Cleared on logout.
    static var sessionId: String? {
        get { UserDefaults.standard.string(forKey: "active_session_id") }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: "active_session_id")
            } else {
                UserDefaults.standard.removeObject(forKey: "active_session_id")
            }
        }
    }

    static func logout() {
        sharedToken = ""
        refreshToken = ""
        sessionId = nil
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
        locationManager.distanceFilter = 10 // Update every 10 meters if moving fast
        
        // Defer background update activation to prevent launch-time crashes.
        //
        // CLLocationManager.allowsBackgroundLocationUpdates = true throws
        // at runtime if UIBackgroundModes:[location] isn't in Info.plist
        // (which is the case on free-Apple-ID dev builds — the entitlement
        // is gated behind the paid Apple Developer Program). We probe the
        // Info.plist at runtime and only enable background updates when
        // the entitlement is actually present.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            #if !targetEnvironment(simulator)
            let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
            if modes.contains("location") {
                self.locationManager.allowsBackgroundLocationUpdates = true
                self.locationManager.pausesLocationUpdatesAutomatically = false
                self.locationManager.showsBackgroundLocationIndicator = true
            } else {
                print("📍 [LocationTrackingService] Skipping allowsBackgroundLocationUpdates — UIBackgroundModes:location not in Info.plist (free Apple ID dev build). Live tracking will pause when app is backgrounded.")
            }
            #endif
        }
    }
    
    func requestPermissions() {
        // Apple guidance: request the cheapest permission tier on launch
        // (WhenInUse). Upgrade to Always *only* when the user does
        // something that needs it (e.g. starts a visit / attendance).
        // Calling requestAlwaysAuthorization() immediately after
        // requestWhenInUseAuthorization() on a fresh install was found to
        // deadlock the SwiftUI launch path on iOS 26: the second prompt
        // never appeared, but the app stayed stuck on the launch screen
        // until the user force-quit and reopened. Removing the eager
        // Always request fixes that first-install hang.
        locationManager.requestWhenInUseAuthorization()
    }

    func upgradeToAlwaysIfPossible() {
        // Call this from a user-initiated moment (visit start, attendance
        // check-in) — iOS only allows the Always upgrade prompt to
        // appear once the WhenInUse decision is settled.
        if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
    }
    
    func startTracking() {
        // Tata Tiscon reps reported battery drain — continuous tracking
        // is disabled for that tenant. The one-shot OneShotLocationProvider
        // used by lead-create / activity capture is unaffected.
        if ClientFeatures.isTataTiscon {
            locationManager.stopUpdatingLocation()
            return
        }
        locationManager.startUpdatingLocation()
    }
    func stopTracking() { locationManager.stopUpdatingLocation() }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.lastLocation = locations.last
    }
}

class KinematicRepository {
    static let shared = KinematicRepository()
    private let baseURL = "https://api.kinematicapp.com/api/v1"
    private let cachedMobileHomeKey = "cached_mobile_home_payload"
    private let cachedRoutePlanKey = "cached_route_plan_payload"
    
    func logVisit(outletId: String, lat: Double, lng: Double) async -> String? {
        do {
            let payload: [String: Any] = [
                "visit_outlet_id": outletId,
                "latitude": lat,
                "longitude": lng,
                "rating": "good",
                "remarks": "Visit started"
            ]
            let body = try? JSONSerialization.data(withJSONObject: payload)
            
            // Using a generic [String: Any] response dictionary for flexibility with the visit log ID
            let res: ApiResponse<[String: String]>? = try await performRequest(
                "/visits",
                method: "POST",
                body: body
            )
            return res?.data?["id"]
        } catch {
            print("❌ LOG_VISIT_ERROR: \(error). Returning MOCK_ID.")
            return "mock_visit_\(UUID().uuidString)"
        }
    }
    
    func sendLiveTrackingPing(lat: Double, lng: Double, battery: Int) async -> Bool {
        // Hard kill switch for Tata Tiscon — even if a stale timer fires
        // (e.g. user logged in elsewhere then the JWT swapped), skip the
        // network round-trip so we don't drain battery on a 204 from
        // the backend.
        if ClientFeatures.isTataTiscon {
            return true
        }
        do {
            let payload = UserStatusUpdate.heartbeat(lat: lat, lng: lng, battery: battery)
            let body = try? JSONEncoder().encode(payload)
            let res: ApiResponse<[String: String]>? = try await performRequest(
                "/users/status",
                method: "PATCH",
                body: body
            )
            let success = res?.success ?? false
            if success {
                print("✅ [Tracking] Status update successful.")
            } else {
                print("⚠️ [Tracking] Ping rejected: \(res?.error ?? res?.message ?? "Unknown error")")
            }
            return success
        } catch {
            print("❌ TRACKING_PING_FAILED: \(error)")
            return false
        }
    }
    
    /// Upload this device's APNs token so the backend can send iOS push.
    /// PATCH /notifications/fcm-token with platform:"ios". Best-effort — the
    /// caller ignores failures (the dispatcher simply has no iOS token to
    /// target until the next successful registration).
    func registerPushToken(token: String, platform: String) async -> Bool {
        do {
            let body = try? JSONSerialization.data(withJSONObject: ["token": token, "platform": platform])
            let res: ApiResponse<[String: String]>? = try await performRequest(
                "/notifications/fcm-token",
                method: "PATCH",
                body: body
            )
            let success = res?.success ?? false
            print(success ? "📲 [Push] token registered with backend" : "⚠️ [Push] token registration rejected")
            return success
        } catch {
            print("❌ [Push] token register failed: \(error)")
            return false
        }
    }

    /// Fetch the rep's "My Day" agenda — activities due today / overdue /
    /// upcoming plus open leads near the device. `lat`/`lng` are optional;
    /// when supplied the backend stamps `distance_km` on each lead so the
    /// UI can sort/show proximity. Returns nil on failure (caller renders
    /// an empty / retry state).
    func fetchMyDay(lat: Double? = nil, lng: Double? = nil) async -> MyDayResponse? {
        do {
            var query: [URLQueryItem]? = nil
            if let lat = lat, let lng = lng {
                query = [
                    URLQueryItem(name: "lat", value: String(lat)),
                    URLQueryItem(name: "lng", value: String(lng))
                ]
            }
            let res: ApiResponse<MyDayResponse>? = try await performRequest(
                "/crm/my-day",
                queryItems: query
            )
            return res?.data
        } catch {
            print("❌ FETCH_MY_DAY_FAILED: \(error)")
            return nil
        }
    }

    /// Silently swap the stored access token for a fresh one using the
    /// long-lived refresh token. Returns true on success. Serialised via
    /// `refreshLock` so a burst of concurrent 401s only triggers one POST
    /// to `/auth/refresh`.
    private static let refreshLock = NSLock()
    private static var refreshInFlight: Task<Bool, Never>?

    func refreshAccessToken() async -> Bool {
        let saved = Session.refreshToken
        guard !saved.isEmpty else { return false }

        // Coalesce — if another caller already kicked off a refresh, await
        // its result instead of issuing a second POST.
        Self.refreshLock.lock()
        if let inflight = Self.refreshInFlight {
            Self.refreshLock.unlock()
            return await inflight.value
        }
        let task = Task<Bool, Never> {
            defer {
                Self.refreshLock.lock()
                Self.refreshInFlight = nil
                Self.refreshLock.unlock()
            }
            guard let url = URL(string: "\(baseURL)/auth/refresh") else { return false }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 15
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(["refresh_token": saved])
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else {
                    print("🚩 REFRESH_FAILED: status \(code)")
                    return false
                }
                struct Body: Codable {
                    let success: Bool
                    let data: Inner?
                    struct Inner: Codable {
                        let accessToken: String
                        let refreshToken: String?
                        enum CodingKeys: String, CodingKey {
                            case accessToken = "access_token"
                            case refreshToken = "refresh_token"
                        }
                    }
                }
                let parsed = try JSONDecoder().decode(Body.self, from: data)
                guard parsed.success, let newAccess = parsed.data?.accessToken else { return false }
                Session.sharedToken = newAccess
                if let newRefresh = parsed.data?.refreshToken, !newRefresh.isEmpty {
                    Session.refreshToken = newRefresh
                }
                print("✅ REFRESH_OK")
                return true
            } catch {
                print("🚩 REFRESH_ERROR: \(error.localizedDescription)")
                return false
            }
        }
        Self.refreshInFlight = task
        Self.refreshLock.unlock()
        return await task.value
    }

    // --- New Deep Diagnostic Helper ---
    private func performRequest<T: Codable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil,
        idempotencyKey: String? = nil,
        // Internal — set on the recursive retry after a silent refresh so
        // we never spin in an infinite refresh loop.
        _retryingAfterRefresh: Bool = false
    ) async throws -> ApiResponse<T>? {
        var urlComponents = URLComponents(string: "\(baseURL)\(path)")
        if let queryItems = queryItems {
            urlComponents?.queryItems = queryItems
        }

        guard let url = urlComponents?.url else {
            print("🚩 ERROR: Invalid URL for path \(path)")
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15.0 // Prevent hangs
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        // Single-device-login + platform headers. Backend uses
        // X-Kinematic-Platform to decide whether to enforce session
        // checking; mismatch on X-Session-Id returns 401 DEVICE_REPLACED.
        // Device-* headers populate the kicked-device toast on the
        // OTHER device ("signed in on iPhone15,3 · iOS 17.4").
        req.setValue("ios", forHTTPHeaderField: "X-Kinematic-Platform")
        req.setValue(UIDevice.current.modelName, forHTTPHeaderField: "X-Device-Model")
        req.setValue("Apple", forHTTPHeaderField: "X-Device-Brand")
        req.setValue(UIDevice.current.systemVersion, forHTTPHeaderField: "X-OS-Version")
        if let sid = Session.sessionId, !sid.isEmpty {
            req.setValue(sid, forHTTPHeaderField: "X-Session-Id")
        }

        // --- PROD SYNC: Inject X-Org-Id if available ---
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }
        if let key = idempotencyKey {
            req.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }

        print("🚀 API_START: \(method) \(url.absoluteString)")
        if let orgId = req.value(forHTTPHeaderField: "X-Org-Id") {
            print("🔑 ORG_ID: \(orgId)")
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("📡 API_END: Status \(statusCode) for \(path)")


        // Session resilience:
        //   On 401 we silently refresh the access token using the long-lived
        //   refresh token and replay the request once. The user never gets
        //   kicked out unless they explicitly hit Sign Out OR the refresh
        //   token itself is rejected (revoked / 30d-stale). Only in that
        //   final case do we set `needsReAuth` so the UI can offer a
        //   gentle re-login — we no longer wipe the local session
        //   automatically.
        if statusCode == 401 {
            // Single-device-login: if the body carries DEVICE_REPLACED,
            // this device's session UUID is stale because the SAME user
            // logged in on another device. Refreshing the access token
            // would NOT help (the session_id mismatch survives token
            // rotation), so skip the refresh path and force-logout
            // immediately with a friendly explainer.
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            if bodyStr.contains("DEVICE_REPLACED") {
                // Extract the human-readable device label from the JSON
                // body ("device":"Realme 12 Pro · Android 14"). Plain
                // string-splitting instead of NSRegularExpression because
                // we only need this one shape and the body is small
                // enough that O(n) scanning is trivial.
                let deviceLabel: String? = {
                    let needle = "\"device\""
                    guard let keyRange = bodyStr.range(of: needle) else { return nil }
                    let after = bodyStr[keyRange.upperBound...]
                    guard let openQuote = after.range(of: "\"") else { return nil }
                    let valueStart = openQuote.upperBound
                    guard let closeQuote = after.range(of: "\"", range: valueStart..<after.endIndex) else { return nil }
                    return String(after[valueStart..<closeQuote.lowerBound])
                }()
                await MainActor.run {
                    let label = deviceLabel ?? "another device"
                    KiniAppState.shared.sessionKickedMsg = "Your account was signed in on \(label). This device has been signed out."
                    KiniAppState.shared.logout()
                }
                return nil
            }
            if !_retryingAfterRefresh {
                print("⚠️ AUTH_ERROR: 401 on \(path). Attempting silent refresh.")
                let refreshed = await refreshAccessToken()
                if refreshed {
                    Session.unauthorizedHits = 0
                    return try await performRequest(
                        path, method: method, body: body,
                        queryItems: queryItems, idempotencyKey: idempotencyKey,
                        _retryingAfterRefresh: true
                    )
                }
            }
            // Refresh failed (or this IS the retry hitting 401 again).
            // Surface a flag the UI can prompt on, but DO NOT auto-logout.
            Session.unauthorizedHits += 1
            await MainActor.run { KiniAppState.shared.needsReAuth = true }
        } else if statusCode >= 200 && statusCode < 400 {
            // Reset the counter on any successful response so a re-login
            // (or token refresh on the backend) resumes normal behaviour.
            if Session.unauthorizedHits > 0 { Session.unauthorizedHits = 0 }
            if KiniAppState.shared.needsReAuth {
                await MainActor.run { KiniAppState.shared.needsReAuth = false }
            }
        }
        
        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(ApiResponse<T>.self, from: data)
            if !result.success {
                print("🚨 API_LOGIC_ERROR: \(result.error ?? result.message ?? "Unknown error")")
            }
            return result
        } catch {
            if let rawJson = String(data: data, encoding: .utf8) {
                print("❌ DECODE_ERROR at \(path): \(error)")
                print("📦 RAW_JSON: \(rawJson)")
            }
            throw error
        }
    }
    
    func getFormTemplates(activityId: String) async -> FormTemplate? {
        print("LOADING_TEMPLATE_FOR_ACTIVITY: \(activityId)")

        guard !activityId.isEmpty else { return nil }

        do {
            let res: ApiResponse<[FormTemplate]>? = try await performRequest(
                "/forms/templates",
                queryItems: [URLQueryItem(name: "activity_id", value: activityId)]
            )
            return res?.data?.first
        } catch {
            print("⚠️ FETCH_TEMPLATES_FAILED: \(error)")
            return nil
        }
    }

    func submitForm(request: FormSubmissionRequest) async -> Bool {
        do {
            let body = try? JSONEncoder().encode(request)
            // Backend returns the full submission object (mixed types: strings, ints, booleans, dates)
            // Use a flexible decode type that won't fail on type mismatches
            let res: ApiResponse<AnyCodableValue>? = try await performRequest(
                "/forms/submit",
                method: "POST",
                body: body
            )
            return res?.success ?? false
        } catch {
            print("❌ SUBMIT_FORM_ERROR: \(error)")
            return false
        }
    }
    
    // --- BROADCAST ---
    func getBroadcastHistory() async -> [BroadcastQuestion] {
        do {
            let res: ApiResponse<[BroadcastQuestion]>? = try await performRequest("/analytics/broadcasts")
            return res?.data ?? []
        } catch {
            return []
        }
    }
    
    func sendBroadcastAnswer(id: String, selectedIndex: Int) async -> Bool {
        do {
            let payload = SubmitAnswerRequest(selected: selectedIndex)
            let body = try? JSONEncoder().encode(payload)
            let res: ApiResponse<[String: String]>? = try await performRequest(
                "/analytics/broadcasts/\(id)/answer",
                method: "POST",
                body: body
            )
            return res?.success ?? false
        } catch {
            return false
        }
    }
    
    // --- LEARNING HUB ---
    func getLearningMaterials() async -> [LearningMaterial] {
        do {
            let res: ApiResponse<[LearningMaterial]>? = try await performRequest("/analytics/learning")
            return res?.data ?? []
        } catch {
            return []
        }
    }

    /// Re-pull `/auth/me` and overwrite the cached `Session.currentUser` so
    /// entitlement-driven UI gating (CRM-only mode, FF tabs, etc.) reflects
    /// the latest server-side SKU state. Critical for users whose session was
    /// stored before `enabled_modules` / `enabled_packages` rolled out — those
    /// stale rows have empty arrays which the User model treats as a "legacy
    /// session" (i.e. full access), so a CRM-only client like Hemanth was
    /// seeing Field Force tabs until this refresh ran.
    @discardableResult
    func refreshMe() async -> User? {
        guard !Session.sharedToken.isEmpty else { return nil }
        do {
            let res: ApiResponse<User>? = try await performRequest("/auth/me")
            guard let user = res?.data else { return nil }
            await MainActor.run { Session.currentUser = user }
            return user
        } catch {
            print("🚩 refreshMe failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Self-profile patch. Backend allow-list (auth.controller.ts) is
    /// avatar_url + name today; pass nil to skip a field. Returns true
    /// when the server accepted the update so the caller can decide
    /// whether to mirror the change optimistically.
    func patchMyProfile(avatarUrl: String? = nil, name: String? = nil) async -> Bool {
        guard !Session.sharedToken.isEmpty else { return false }
        struct Body: Encodable {
            let avatar_url: String?
            let name: String?
        }
        let body = try? JSONEncoder().encode(Body(avatar_url: avatarUrl, name: name))
        do {
            let res: ApiResponse<User>? = try await performRequest(
                "/auth/me",
                method: "PATCH",
                body: body
            )
            return res?.success ?? false
        } catch {
            print("🚩 patchMyProfile failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Self-service password reset — step 1. Backend always returns
    /// 200 with {ok:true} regardless of whether the email is on file
    /// (anti-enumeration), so we just surface "Check your inbox"
    /// after any 2xx and let the user retry with a different address
    /// if they got the wrong one.
    func forgotPassword(email: String) async -> (Bool, String?) {
        guard let url = URL(string: "\(baseURL)/auth/forgot-password") else { return (false, "Invalid URL") }
        let cleaned = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !cleaned.isEmpty else { return (false, "Enter your email.") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["email": cleaned])
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code) { return (true, nil) }
            return (false, "Couldn't send the reset email. Try again in a minute.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Self-service password reset — step 2. Backend verifies the
    /// Supabase recovery token, sets the new password, then signs the
    /// user in with the new credentials and returns a fresh session.
    /// We mirror the login save path so the rep lands straight on the
    /// home tab without re-entering credentials.
    func resetPassword(email: String, token: String, newPassword: String) async -> (Bool, String?) {
        guard let url = URL(string: "\(baseURL)/auth/reset-password") else { return (false, "Invalid URL") }
        let cleanedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        let cleanedToken = token.trimmingCharacters(in: .whitespaces)
        guard !cleanedEmail.isEmpty, !cleanedToken.isEmpty else {
            return (false, "Reset link is incomplete. Request a fresh one.")
        }
        guard newPassword.count >= 6 else { return (false, "Password must be at least 6 characters.") }

        let payload: [String: String] = [
            "email": cleanedEmail,
            "token": cleanedToken,
            "password": newPassword,
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code) {
                // Response mirrors /auth/login so we can reuse the same
                // decoder + save sequence. We don't get session_id back
                // on reset (single-device rotation only fires on login)
                // — that's fine; the next refresh will pick up a fresh
                // one anyway.
                if let result = try? JSONDecoder().decode(LoginResponseModel.self, from: data),
                   result.success, let t = result.data?.accessToken {
                    await MainActor.run {
                        Session.sharedToken = t
                        Session.refreshToken = result.data?.refreshToken ?? ""
                        Session.sessionId = result.data?.sessionId
                        Session.currentUser = result.data?.user
                        KiniAppState.shared.clearSessionKickedMsg()
                        KiniAppState.shared.checkAuth()
                    }
                    return (true, nil)
                }
                return (false, "Password updated, but couldn't auto-sign in. Sign in manually.")
            }
            // 4xx — usually expired/used token. Surface the backend
            // error string when we get one.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["error"] as? String {
                return (false, msg)
            }
            return (false, "Reset link is invalid or has expired. Request a new one.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func login(email: String, phone: String?, pass: String) async -> (Bool, String?) {
        guard let url = URL(string: "\(baseURL)/auth/login") else { return (false, "Invalid URL") }
        let identifier = (phone != nil && !phone!.isEmpty) ? phone! : email
        let payload: [String: String] = ["email": identifier, "password": pass]
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Stamp platform + device headers so the backend can identify
        // mobile traffic at login and build a friendly device label for
        // the OTHER device's kicked-device toast when this login rotates
        // the session_id.
        req.setValue("ios", forHTTPHeaderField: "X-Kinematic-Platform")
        req.setValue(UIDevice.current.modelName, forHTTPHeaderField: "X-Device-Model")
        req.setValue("Apple", forHTTPHeaderField: "X-Device-Brand")
        req.setValue(UIDevice.current.systemVersion, forHTTPHeaderField: "X-OS-Version")
        req.httpBody = try? JSONEncoder().encode(payload)
        
        print("🚀 API_LOGIN_START: \(url.absoluteString) for \(identifier)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("📡 API_LOGIN_END: Status \(statusCode)")
            
            do {
                let result = try JSONDecoder().decode(LoginResponseModel.self, from: data)
                if result.success, let t = result.data?.accessToken {
                    await MainActor.run {
                        Session.sharedToken = t
                        // Persist the refresh token so the access token can
                        // be silently swapped when it expires (~1h Supabase
                        // default), keeping the user signed in for the full
                        // refresh-token lifetime (~30d, rolling) without a
                        // re-login prompt.
                        Session.refreshToken = result.data?.refreshToken ?? ""
                        // Single-device-login session UUID — persisted so
                        // every subsequent request can echo it back as
                        // X-Session-Id. Clear any leftover kicked-device
                        // toast from a previous forced logout.
                        Session.sessionId = result.data?.sessionId
                        KiniAppState.shared.clearSessionKickedMsg()
                        Session.currentUser = result.data?.user
                        KiniAppState.shared.checkAuth()
                    }
                    return (true, nil)
                }
                return (false, result.error ?? "Login rejected")
            } catch {
                if let rawJson = String(data: data, encoding: .utf8) {
                    print("❌ LOGIN_DECODE_ERROR: \(error)")
                    print("📦 RAW_JSON: \(rawJson)")
                }
                return (false, error.localizedDescription)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    func uploadImage(image: UIImage, type: String) async -> String? {
        let url = URL(string: "\(baseURL)/upload/\(type)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        if let orgId = Session.currentUser?.orgId { request.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Resize + iteratively compress so the upload payload is ~50–150 KB
        // instead of the 1.5–2 MB an iPhone selfie produces. Cuts upload time
        // ~5-10× on 3G/4G — selfie upload is the biggest chunk of perceived
        // attendance latency.
        guard let imageData = Self.compressForUpload(image, maxDim: 1280, targetKB: 150) else { return nil }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"selfie.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("🚀 UPLOAD_START: \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            if !(200..<300).contains(statusCode) {
                let rawBody = String(data: data, encoding: .utf8) ?? "no body"
                print("❌ UPLOAD_SERVER_ERROR: Status \(statusCode). Body: \(rawBody)")
                return nil
            }
            
            let res = try JSONDecoder().decode(ApiResponse<UploadResponse>.self, from: data)
            return res.data?.url
        } catch {
            print("❌ UPLOAD_NETWORK_ERROR: \(error)")
            return nil
        }
    }
    
    func markAttendance(isCheckIn: Bool, lat: Double, lng: Double, selfieUrl: String? = nil, battery: Int? = nil, idempotencyKey: String? = nil) async -> (Bool, String?, AttendanceRecord?) {
        let endpoint = isCheckIn ? "/attendance/checkin" : "/attendance/checkout"

        do {
            var payload: [String: Any] = ["latitude": lat, "longitude": lng]
            if let selfie = selfieUrl { payload["selfie_url"] = selfie }
            if let battery = battery { payload["battery_percentage"] = battery }

            let body = try? JSONSerialization.data(withJSONObject: payload)
            let res: ApiResponse<AttendanceRecord>? = try await performRequest(
                endpoint,
                method: "POST",
                body: body,
                idempotencyKey: idempotencyKey
            )
            if res?.success == true { return (true, nil, res?.data) }
            return (false, res?.error ?? res?.message ?? "Failed to mark attendance", nil)
        } catch {
            return (false, error.localizedDescription, nil)
        }
    }
    
    // MARK: Route plan outlet update (Android parity — PATCH /route-plan/outlets/{id})
    /// Update an outlet visit's status / checkin / checkout. `status` is one of
    /// "pending" | "in_progress" | "completed" | "skipped". Coordinates and
    /// photo URL are optional and only sent when present.
    func updateRouteOutlet(outletId: String,
                           status: String? = nil,
                           checkinLat: Double? = nil,
                           checkinLng: Double? = nil,
                           checkinAt: String? = nil,
                           checkoutAt: String? = nil,
                           photoUrl: String? = nil,
                           notes: String? = nil) async -> (Bool, String?) {
        var payload: [String: Any] = [:]
        if let status { payload["status"] = status }
        if let checkinLat { payload["checkin_lat"] = checkinLat }
        if let checkinLng { payload["checkin_lng"] = checkinLng }
        if let checkinAt { payload["checkin_at"] = checkinAt }
        if let checkoutAt { payload["checkout_at"] = checkoutAt }
        if let photoUrl { payload["photo_url"] = photoUrl }
        if let notes { payload["visit_notes"] = notes }
        do {
            let body = try? JSONSerialization.data(withJSONObject: payload)
            let res: ApiResponse<[String: String]>? = try await performRequest(
                "/route-plan/outlets/\(outletId)", method: "PATCH", body: body)
            if res?.success == true { return (true, nil) }
            return (false, res?.error ?? res?.message ?? "Failed to update outlet")
        } catch { return (false, error.localizedDescription) }
    }

    // MARK: Breaks (Android parity — POST /attendance/break/start, /break/end)
    func startBreak() async -> (Bool, String?) {
        do {
            let res: ApiResponse<[String: String]>? = try await performRequest(
                "/attendance/break/start", method: "POST", body: Data("{}".utf8))
            if res?.success == true { return (true, nil) }
            return (false, res?.error ?? res?.message ?? "Failed to start break")
        } catch { return (false, error.localizedDescription) }
    }

    func endBreak() async -> (Bool, String?) {
        do {
            let res: ApiResponse<[String: String]>? = try await performRequest(
                "/attendance/break/end", method: "POST", body: Data("{}".utf8))
            if res?.success == true { return (true, nil) }
            return (false, res?.error ?? res?.message ?? "Failed to end break")
        } catch { return (false, error.localizedDescription) }
    }

    // MARK: History (Android parity — GET /attendance/history)
    func getAttendanceHistory(page: Int = 1, limit: Int = 30) async -> [AttendanceRecord] {
        do {
            let res: ApiResponse<[AttendanceRecord]>? = try await performRequest(
                "/attendance/history?page=\(page)&limit=\(limit)")
            return res?.data ?? []
        } catch { return [] }
    }

    func logSecurityViolation(type: String, action: String, lat: Double?, lng: Double?) async {
        do {
            let payload: [String: Any?] = ["type": type, "action": action, "lat": lat, "lng": lng]
            let body = try? JSONSerialization.data(withJSONObject: payload)
            _ = try await performRequest(
                "/security/alert",
                method: "POST",
                body: body
            ) as ApiResponse<[String: String]>?
        } catch {
            print("❌ SECURITY_LOG_ERROR: \(error)")
        }
    }
    
    func getMobileHome() async -> MobileHomeResponse? {
        if let cached = OutletCache.shared.get(MobileHomeResponse.self, key: .mobileHome) {
            return cached
        }
        do {
            let res: ApiResponse<MobileHomeResponse>? = try await performRequest("/analytics/mobile-home")
            if let home = res?.data {
                OutletCache.shared.put(home, key: .mobileHome)
                cache(home, forKey: cachedMobileHomeKey)
                if let routes = home.routePlan, !routes.isEmpty {
                    cache(routes, forKey: cachedRoutePlanKey)
                }
                return home
            }
            return loadCached(MobileHomeResponse.self, forKey: cachedMobileHomeKey)
        } catch {
            return loadCached(MobileHomeResponse.self, forKey: cachedMobileHomeKey)
        }
    }
    
    func getFeed() async -> [ActivityFeedItem] {
        do {
            let res: ApiResponse<[ActivityFeedItem]>? = try await performRequest("/feed")
            return res?.data ?? []
        } catch {
            return []
        }
    }
    
    func fetchMyRoutePlan() async -> [RoutePlan] {
        if let cached = OutletCache.shared.get([RoutePlan].self, key: .routePlan) {
            return cached
        }
        // Use local timezone date so IST/non-UTC users get the correct date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let date = dateFormatter.string(from: Date())
        print("🔍 FETCH_ROUTE_PLAN_START: Date=\(date)")
        do {
            let res: ApiResponse<[RoutePlan]>? = try await performRequest(
                "/route-plan/me",
                queryItems: [URLQueryItem(name: "date", value: date)]
            )

            if let data = res?.data {
                print("✅ FETCH_ROUTE_PLAN_SUCCESS: Found \(data.count) plans")
                if !data.isEmpty {
                    OutletCache.shared.put(data, key: .routePlan)
                    cache(data, forKey: cachedRoutePlanKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: cachedRoutePlanKey)
                }
                return data
            } else {
                print("⚠️ FETCH_ROUTE_PLAN_EMPTY: Success but no data.")
                return loadCached([RoutePlan].self, forKey: cachedRoutePlanKey) ?? []
            }
        } catch {
            print("❌ FETCH_ROUTE_PLAN_ERROR: \(error)")
            return loadCached([RoutePlan].self, forKey: cachedRoutePlanKey) ?? []
        }
    }
    
    // MARK: - Date Helpers
    private var todayString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        return dateFormatter.string(from: Date())
    }
    
    private func cache<T: Encodable>(_ value: T, forKey key: String) {
        guard let encoded = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }
    
    fileprivate func loadCached<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let raw = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: raw)
    }
    // --- MOCK DATA PROVIDER ---
    private func mockMobileHome() -> MobileHomeResponse {
        return MobileHomeResponse(
            today: AttendanceRecord(id: "1", date: "2024-04-08", status: "present", checkinAt: "2024-04-08T09:00:00Z", checkoutAt: nil, totalHours: 4.5, checkinSelfieUrl: nil, checkoutSelfieUrl: nil, checkinLatitude: nil, checkinLongitude: nil, checkoutLatitude: nil, checkoutLongitude: nil, checkinAddress: nil, checkoutAddress: nil, firstCheckinAt: nil, lastCheckoutAt: nil, totalDuration: 16200),
            summary: AnalyticsSummary(tffCount: 12),
            routePlan: mockRoute(),
            unreadCount: 5,
            quote: MotivationQuote(quote: "Success is not final; failure is not fatal: it is the courage to continue that counts.", author: "Winston Churchill"),
            alreadyAnswered: false,
            broadcast: nil
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
            RouteOutlet(rawId: "o1", storeId: "s1", storeName: "Apex Retail", address: "Andheri East, Mumbai", status: "pending", activityId: "form_123", activities: []),
            RouteOutlet(rawId: "o2", storeId: "s2", storeName: "Global Mart", address: "Powai, Mumbai", status: "visited", activityId: "form_123", activities: [])
        ]
        return [RoutePlan(id: "p1", planDate: "2024-04-08", status: "active", activityId: "form_123", outlets: outlets)]
    }

    /// Resize the longest side to `maxDim` and iteratively lower JPEG quality
    /// until the result is below `targetKB`. iPhone selfies are 12 MP / ~2 MB
    /// out of the camera; this typically lands at 50–150 KB while staying
    /// readable for face-recognition / ID purposes. Hot path on attendance.
    static func compressForUpload(_ image: UIImage, maxDim: CGFloat = 1280, targetKB: Int = 150) -> Data? {
        // 1. Resize so neither dimension exceeds maxDim. Aspect-ratio preserved.
        let resized: UIImage
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        if longest > maxDim {
            let scale = maxDim / longest
            let newSize = CGSize(width: w * scale, height: h * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        } else {
            resized = image
        }

        // 2. Iteratively reduce quality until under target, floor at 0.4.
        var quality: CGFloat = 0.8
        let targetBytes = targetKB * 1024
        var data = resized.jpegData(compressionQuality: quality)
        while let d = data, d.count > targetBytes, quality > 0.4 {
            quality -= 0.1
            data = resized.jpegData(compressionQuality: quality)
        }
        return data
    }
}

/// Identifiable wrapper for the deep-link reset payload — required by
/// SwiftUI's `sheet(item:)` so the email + token presented to
/// ResetPasswordView are inspectable on every set.
private struct PendingReset: Identifiable {
    let id = UUID()
    let email: String
    let token: String
}

@main
struct KinematicApp: App {
    // Bridges UIKit APNs callbacks (device-token registration, notification
    // taps) into SwiftUI. Inert on free-Apple-ID dev builds — see
    // PushNotificationManager for the activation steps.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @StateObject private var locationService = LocationTrackingService.shared
    @StateObject private var appState = KiniAppState.shared
    @Environment(\.scenePhase) private var scenePhase
    /// Brand splash shown for a brief minimum on launch (parity with Android).
    /// Dismissed purely on a timer so it can never hang on a setup task.
    @State private var showSplash = true
    // Captures kinematic://reset-password?email=…&token=… deep links
    // from the password-reset email. When the user taps the link from
    // their inbox on this device, .onOpenURL fills these and the
    // sheet attached to ContentView opens straight onto the new-
    // password screen — works whether the app was foregrounded or
    // cold-started.
    @State private var pendingReset: (email: String, token: String)?

    init() {
        print("🚀 APP_LIFE: KinematicApp launched")
    }

    var body: some Scene {
        WindowGroup {
            // The iOS UILaunchScreen (configured in Info.plist with
            // UIImageName=LaunchLogo + UIColorName=DeepNavy) is the single
            // splash. We previously layered a SwiftUI SplashView on top,
            // which caused two visible loaders AND was implicated in the
            // splash-hang the user reported (the SwiftUI flag could fail
            // to flip if the awaited setup task got cancelled). ContentView
            // now mounts directly — the system launch screen seamlessly
            // hands off to our app.
            ZStack {
            ContentView()
                .environmentObject(locationService)
                .environmentObject(appState)
                .preferredColorScheme(appState.theme == .system ? nil : (appState.theme == .dark ? .dark : .light))
                .task {
                    // App-launch security check. We can't gate the
                    // splash on it (no GPS fix yet, no action to
                    // block), but we DO want a VPN sniff to land an
                    // audit row + manager push the moment the rep
                    // opens the app with a VPN already active.
                    if Session.isAuthenticated {
                        _ = await SecurityCheck.preflight(action: "APP_LAUNCH", location: nil)
                    }
                }
                // Deep-link handler. The password-reset email embeds
                // `kinematic://reset-password?email=…&token=…`. Tapping
                // it from any inbox app on this device routes here
                // (registered via CFBundleURLTypes in Info.plist). We
                // pull the params off and flip pendingReset, which the
                // sheet below renders.
                .onOpenURL { url in
                    guard url.scheme?.lowercased() == "kinematic",
                          (url.host ?? "").lowercased() == "reset-password"
                    else { return }
                    let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let q = comps?.queryItems ?? []
                    let email = q.first(where: { $0.name == "email" })?.value ?? ""
                    let token = q.first(where: { $0.name == "token" })?.value ?? ""
                    if !email.isEmpty, !token.isEmpty {
                        pendingReset = (email: email, token: token)
                    }
                }
                .sheet(item: Binding(
                    get: { pendingReset.map { PendingReset(email: $0.email, token: $0.token) } },
                    set: { pendingReset = $0.map { ($0.email, $0.token) } }
                )) { item in
                    ResetPasswordView(email: item.email, token: item.token)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Drain queued attendance + distribution writes whenever
                    // the app comes back to the foreground.
                    if phase == .active && Session.isAuthenticated {
                        Task { await AttendanceCache.shared.flush() }
                        // Same VPN-on-resume check. A rep can leave
                        // the app, enable a VPN, then return — the
                        // scene-phase callback is the only place we
                        // catch that without polling.
                        Task { _ = await SecurityCheck.preflight(action: "APP_RESUME", location: nil) }
                        // Re-pull /auth/me so profile changes made elsewhere
                        // (e.g. a DP/avatar set on the web dashboard) and the
                        // latest entitlements show up without a re-login.
                        Task { await KinematicRepository.shared.refreshMe() }
                    }
                }
                .task {
                    UIDevice.current.isBatteryMonitoringEnabled = true
                    // Deferred to the next runloop tick so the launch
                    // screen has handed off to ContentView before any
                    // permission alert can appear over it. On first
                    // install, the camera + location prompts being
                    // requested synchronously inside `.task` was causing
                    // the SwiftUI window to stay behind the alerts and
                    // the user perceived it as "stuck on splash".
                    DispatchQueue.main.async {
                        locationService.requestPermissions()
                    }
                    // Camera permission is now requested lazily, the
                    // first time the user opens the selfie sheet — see
                    // AttendanceViewModel.captureSelfie. Pre-warming on
                    // launch was part of the first-install hang.
                }

                if showSplash {
                    SplashView()
                        .preferredColorScheme(appState.theme == .system ? nil : (appState.theme == .dark ? .dark : .light))
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .task {
                // The iOS launch screen (now configured with UIImageName=LaunchLogo
                // in Info.plist) already shows the brand mark on cold launch, so
                // the SwiftUI SplashView is mostly a hand-off cross-fade. Keeping
                // it at 1.6s caused the login UI to feel locked behind a static
                // image on first install — drop to a brief 350ms so the splash
                // dissolves almost immediately into the interactive view. Pure
                // timer, never gated on auth/network, so it can't hang.
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.easeInOut(duration: 0.25)) { showSplash = false }
            }
        }
    }
}


// MARK: - UIDevice.modelName
// Returns the marketing identifier from sysctl (e.g. "iPhone15,3" for iPhone
// 14 Pro Max). The default UIDevice.current.model gives generic "iPhone" /
// "iPad" — not granular enough for the kicked-device toast that surfaces on
// the OTHER device when the same user logs in on a new phone. Falls back to
// UIDevice.current.model on sysctl error so the header is never empty.
extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let id = machineMirror.children.reduce("") { acc, element in
            guard let value = element.value as? Int8, value != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(value)))
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
}
