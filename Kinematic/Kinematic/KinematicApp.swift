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
    
    enum CodingKeys: String, CodingKey {
        case id, name, email, role, mobile
        case orgId = "org_id"
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
    let user: User
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
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
    var outlets: [RouteOutlet]?
    
    enum CodingKeys: String, CodingKey {
        case id, status, outlets, stores
        case planDate = "plan_date"
        case activityId = "activity_id" // Maps to Android activity_id
        case date
    }
    
    init(id: String?, planDate: String?, status: String?, activityId: String?, outlets: [RouteOutlet]?) {
        self.id = id
        self.planDate = planDate
        self.status = status
        self.activityId = activityId
        self.outlets = outlets
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        planDate = try container.decodeIfPresent(String.self, forKey: .planDate)
            ?? container.decodeIfPresent(String.self, forKey: .date)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        activityId = try container.decodeIfPresent(String.self, forKey: .activityId)
        outlets = try container.decodeIfPresent([RouteOutlet].self, forKey: .outlets)
            ?? container.decodeIfPresent([RouteOutlet].self, forKey: .stores)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(planDate, forKey: .planDate)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(activityId, forKey: .activityId)
        try container.encodeIfPresent(outlets, forKey: .outlets)
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
    
    var id: String { storeId ?? rawId ?? UUID().uuidString }
    
    enum CodingKeys: String, CodingKey {
        case status, activities, address, tasks
        case rawId = "id"
        case storeId = "store_id"
        case storeName = "store_name"
        case activityId = "activity_id"
        case name
    }
    
    init(rawId: String?, storeId: String?, storeName: String?, address: String?, status: String?, activityId: String?, activities: [RouteActivity]?) {
        self.rawId = rawId
        self.storeId = storeId
        self.storeName = storeName
        self.address = address
        self.status = status
        self.activityId = activityId
        self.activities = activities
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
    
    static var isDemoMode: Bool {
        get { UserDefaults.standard.bool(forKey: "is_demo_mode") }
        set { UserDefaults.standard.set(newValue, forKey: "is_demo_mode") }
    }
    
    /// Number of consecutive 401s seen by the API client. Used to decide
    /// when to give up and force-logout instead of kicking the user out
    /// on the very first transient 401.
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
        locationManager.distanceFilter = 10 // Update every 10 meters if moving fast
        
        // Defer background update activation to prevent launch-time crashes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            #if !targetEnvironment(simulator)
            self.locationManager.allowsBackgroundLocationUpdates = true
            self.locationManager.pausesLocationUpdatesAutomatically = false
            self.locationManager.showsBackgroundLocationIndicator = true
            #endif
        }
    }
    
    func requestPermissions() { 
        locationManager.requestWhenInUseAuthorization()
        // Modern background tracking requires 'Always' permission for high reliability
        locationManager.requestAlwaysAuthorization() 
    }
    
    func startTracking() { locationManager.startUpdatingLocation() }
    func stopTracking() { locationManager.stopUpdatingLocation() }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.lastLocation = locations.last
    }
}

class KinematicRepository {
    static let shared = KinematicRepository()
    private let baseURL = "https://kinematic-production.up.railway.app/api/v1"
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
    
    // --- New Deep Diagnostic Helper ---
    private func performRequest<T: Codable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil,
        idempotencyKey: String? = nil
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
        //   The previous behaviour was to wipe the session on the *first*
        //   401, which kicked field executives out mid-shift the moment
        //   their JWT expired. We now keep the local session intact and
        //   only force-logout if 401s keep happening. This way:
        //     1) Cached attendance/check-in UI stays visible
        //     2) Transient 401s (network/clock skew) don't blow up auth
        //     3) After repeated 401s we surface a "session expired" flag
        //        the UI can act on without losing state
        if statusCode == 401 {
            print("⚠️ AUTH_ERROR: 401 on \(path). Marking session as needing re-auth.")
            Session.unauthorizedHits += 1
            await MainActor.run { KiniAppState.shared.needsReAuth = true }
            if Session.unauthorizedHits >= 5 {
                print("⛔ AUTH_ERROR: 5+ consecutive 401s — forcing logout.")
                Session.unauthorizedHits = 0
                await MainActor.run {
                    Session.logout()
                    KiniAppState.shared.checkAuth()
                }
            }
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
        
        // --- TEST FALLBACK (Unblocks Activity Testing) ---
        // Ensuring ANY activity ID starting with 'form_' or 'test_' or empty uses the Test Form
        if activityId == "form_123" || activityId.starts(with: "test") || activityId.isEmpty {
            return mockTestForm(activityId: activityId.isEmpty ? "form_123" : activityId)
        }
        
        do {
            let res: ApiResponse<[FormTemplate]>? = try await performRequest(
                "/forms/templates",
                queryItems: [URLQueryItem(name: "activity_id", value: activityId)]
            )
            
            // Server fallback: If server returns empty for an activity, provide the Test Form for stability during testing
            if (res?.data == nil || res?.data?.isEmpty == true) {
                return mockTestForm(activityId: activityId)
            }
            
            return res?.data?.first
        } catch {
            print("⚠️ FETCH_TEMPLATES_FAILED: Returning Mock Test Form as fallback.")
            return mockTestForm(activityId: activityId)
        }
    }
    
    private func mockTestForm(activityId: String) -> FormTemplate {
        return FormTemplate(
            id: "tmp_form_unified_001",
            activityId: activityId,
            name: "Ultimate Retail Audit",
            description: "Phase-based synthesis with specialized keyboards.",
            requiresPhoto: true,
            requiresGps: true,
            fields: [
                // Page 1: Initial Details
                FormField(id: "s1", label: "Initial Details", fieldKey: "sec_1", fieldType: "section_header", placeholder: nil, helpText: nil, isRequired: false, sortOrder: 1, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p1", keyboardType: nil),
                FormField(id: "f1", label: "Audit Date", fieldKey: "audit_date", fieldType: "date", placeholder: nil, helpText: "Target date for this audit", isRequired: true, sortOrder: 2, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p1", keyboardType: nil),
                FormField(id: "f2", label: "Store Email", fieldKey: "email", fieldType: "email", placeholder: "manager@store.com", helpText: nil, isRequired: false, sortOrder: 3, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p1", keyboardType: "email"),
                FormField(id: "f10", label: "FE Mobile", fieldKey: "mobile", fieldType: "short_text", placeholder: "Contact number", helpText: nil, isRequired: true, sortOrder: 4, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p1", keyboardType: "phone"),
                
                // Page 2: Product Visibility
                FormField(id: "s2", label: "Product Visibility", fieldKey: "sec_2", fieldType: "section_header", placeholder: nil, helpText: nil, isRequired: false, sortOrder: 4, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p2", keyboardType: nil),
                FormField(id: "f3", label: "Display Correct?", fieldKey: "is_correct", fieldType: "yes_no", placeholder: nil, helpText: "Check against Planogram V4", isRequired: true, sortOrder: 5, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p2", keyboardType: nil),
                FormField(id: "f4", label: "Condition Rating", fieldKey: "rating", fieldType: "rating", placeholder: nil, helpText: "Rate the shelf presentation", isRequired: true, sortOrder: 6, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p2", keyboardType: nil),
                
                // Page 3: Inventory Logic
                FormField(id: "s3", label: "Inventory Logic", fieldKey: "sec_3", fieldType: "section_header", placeholder: nil, helpText: nil, isRequired: false, sortOrder: 7, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p3", keyboardType: nil),
                FormField(id: "f5", label: "Stock Priority", fieldKey: "stock_priority", fieldType: "radio", placeholder: nil, helpText: "Choose one", isRequired: true, sortOrder: 8, options: [
                    FormOption(label: "Critical", value: "crit"),
                    FormOption(label: "Normal", value: "norm"),
                    FormOption(label: "Low", value: "low")
                ], dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p3", keyboardType: nil),
                FormField(id: "f11", label: "Unit Count", fieldKey: "units", fieldType: "short_text", placeholder: "0", helpText: "Numerical count", isRequired: true, sortOrder: 9, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p3", keyboardType: "number"),
                
                // Page 4: Evidence
                FormField(id: "s4", label: "Evidence & Signature", fieldKey: "sec_4", fieldType: "section_header", placeholder: nil, helpText: nil, isRequired: false, sortOrder: 10, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p4", keyboardType: nil),
                FormField(id: "f7", label: "Audit Photos", fieldKey: "photos", fieldType: "image", placeholder: nil, helpText: "Capture photos of the shelf", isRequired: true, sortOrder: 11, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: 5, cameraOnly: true, pageId: "p4", keyboardType: nil),
                FormField(id: "f8", label: "Confirm Location", fieldKey: "gps", fieldType: "location", placeholder: nil, helpText: "Fetch exact audit point", isRequired: true, sortOrder: 12, options: nil, dependsOnId: nil, dependsOnValue: nil, imageCount: nil, cameraOnly: nil, pageId: "p4", keyboardType: nil),
            ],
            pages: [
                FormPage(id: "p1", title: "Setup", description: "Standard identity validation", order: 1),
                FormPage(id: "p2", title: "Visibility", description: "Visual audit metrics", order: 2),
                FormPage(id: "p3", title: "Inventory", description: "Stock level checks", order: 3),
                FormPage(id: "p4", title: "Verification", description: "Final proof of check", order: 4)
            ]
        )
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
    
    func login(email: String, phone: String?, pass: String) async -> (Bool, String?) {
        guard let url = URL(string: "\(baseURL)/auth/login") else { return (false, "Invalid URL") }
        let identifier = (phone != nil && !phone!.isEmpty) ? phone! : email
        let payload: [String: String] = ["email": identifier, "password": pass]
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

@main
struct KinematicApp: App {
    @StateObject private var locationService = LocationTrackingService.shared
    @StateObject private var appState = KiniAppState.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSplashScreenActive = true
    @State private var isDataReady = false

    init() {
        print("🚀 APP_LIFE: KinematicApp launched")
        UITabBar.appearance().isHidden = true
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isSplashScreenActive {
                    SplashView()
                        .transition(.opacity)
                } else {
                    ContentView()
                        .environmentObject(locationService)
                        .environmentObject(appState)
                }
            }
            .preferredColorScheme(appState.theme == .system ? nil : (appState.theme == .dark ? .dark : .light))
            .onChange(of: scenePhase) { phase in
                // Drain queued attendance + distribution writes whenever the
                // app comes back to the foreground. No-ops if the queue is
                // empty or the user is offline.
                if phase == .active && Session.isAuthenticated {
                    Task { await AttendanceCache.shared.flush() }
                }
            }
            .task {
                UIDevice.current.isBatteryMonitoringEnabled = true
                locationService.requestPermissions()
                // Pre-warm camera permission so the selfie sheet opens instantly
                AVCaptureDevice.requestAccess(for: .video) { _ in }

                // --- PERFORMANCE: Background Sync moved to ContentView to avoid root loop ---
                if Session.isAuthenticated {
                    // One-time pre-warm logic if needed, but NOT refresh()
                }
                
                // 1.0s splash — long enough to register the brand, short
                // enough to never feel like a hang. The system launch screen
                // already runs first, so total time-to-app is ~1.5-2s.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        isSplashScreenActive = false
                    }
                }
            }
        }
    }
}

