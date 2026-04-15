import SwiftUI
import Combine
import CoreLocation

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
    case profile, broadcast, learning, settings
    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var isAuthenticated = Session.isAuthenticated
    @Published var selectedTab: Int = 0
    @Published var selectedOutlet: RouteOutlet? = nil
    @Published var attendanceVM = AttendanceViewModel()
    
    // --- Shared Home Data (Parity with Android AppViewModel) ---
    @Published var summary: AnalyticsSummary? = nil
    @Published var quote: MotivationQuote? = nil
    
    // --- Navigation & UI ---
    @Published var showSideMenu = false
    @Published var activeSecondaryRoute: SecondaryRoute? = nil
    @Published var theme: AppTheme = .dark {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "app_theme") }
    }
    
    // --- Visit Management ---
    @Published var activeVisitId: String? = nil
    @Published var activeVisitOutletId: String? = nil
    
    init() {
        // Load persisted theme or default to dark
        let savedTheme = UserDefaults.standard.string(forKey: "app_theme") ?? AppTheme.dark.rawValue
        self.theme = AppTheme(rawValue: savedTheme) ?? .dark
    }
    
    func checkAuth() {
        self.isAuthenticated = Session.isAuthenticated
    }
    
    func logout() {
        Session.logout()
        self.isAuthenticated = false
        self.selectedTab = 0
        self.showSideMenu = false
        self.activeSecondaryRoute = nil
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
    let message: String?
}

struct AttendanceRecord: Codable {
    let id: String?
    let date: String?
    let status: String?
    let checkinAt: String?
    let checkoutAt: String?
    let totalHours: Double?
    let checkinSelfieUrl: String?
    let checkoutSelfieUrl: String?
    let checkinLatitude: Double?
    let checkinLongitude: Double?
    let checkoutLatitude: Double?
    let checkoutLongitude: Double?
    let checkinAddress: String?
    let checkoutAddress: String?

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
        case checkinLatitude = "checkin_latitude"
        case checkinLongitude = "checkin_longitude"
        case checkoutLatitude = "checkout_latitude"
        case checkoutLongitude = "checkout_longitude"
        case checkinAddress = "checkin_address"
        case checkoutAddress = "checkout_address"
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
        checkoutAddress: String? = nil
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
        // Address: prefer dedicated field, fall back to generic "location"
        checkinAddress = container.decodeLossyString(forKey: .checkinAddress)
            ?? container.decodeLossyString(forKey: .location)
        checkoutAddress = container.decodeLossyString(forKey: .checkoutAddress)
    }
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
    let tffCount: Int
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
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, fields
        case activityId = "activity_id"
        case requiresPhoto = "requires_photo"
        case requiresGps = "requires_gps"
    }
}

struct FormField: Codable, Identifiable {
    let id: String
    let label: String
    let fieldKey: String
    let fieldType: String // text, number, select, signature, section, etc.
    let placeholder: String?
    let isRequired: Bool
    let options: [FormOption]?
    
    enum CodingKeys: String, CodingKey {
        case id, label, options
        case fieldKey = "field_key"
        case fieldType = "field_type"
        case placeholder = "placeholder"
        case isRequired = "is_required"
    }
}

struct FormOption: Codable {
    let label: String
    let value: String
}

struct FormSubmissionRequest: Codable {
    let templateId: String
    let activityId: String?
    let outletId: String?
    let submittedAt: String
    let responses: [FormResponse]
    
    enum CodingKeys: String, CodingKey {
        case responses
        case templateId = "template_id"
        case activityId = "activity_id"
        case outletId = "outlet_id"
        case submittedAt = "submitted_at"
    }
}

struct FormResponse: Codable {
    let fieldId: String
    let value: String?
    
    enum CodingKeys: String, CodingKey {
        case value
        case fieldId = "field_id"
    }
}

struct RoutePlan: Codable, Identifiable {
    let id: String?
    let planDate: String?
    let status: String?
    var outlets: [RouteOutlet]?
    
    enum CodingKeys: String, CodingKey {
        case id, status, outlets, stores
        case planDate = "plan_date"
        case date
    }
    
    init(id: String?, planDate: String?, status: String?, outlets: [RouteOutlet]?) {
        self.id = id
        self.planDate = planDate
        self.status = status
        self.outlets = outlets
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        planDate = try container.decodeIfPresent(String.self, forKey: .planDate)
            ?? container.decodeIfPresent(String.self, forKey: .date)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        outlets = try container.decodeIfPresent([RouteOutlet].self, forKey: .outlets)
            ?? container.decodeIfPresent([RouteOutlet].self, forKey: .stores)
    }
}

struct RouteOutlet: Codable, Identifiable {
    let rawId: String?
    let storeId: String?
    let storeName: String?
    let address: String?
    let status: String?
    var activities: [RouteActivity]?
    
    var id: String { rawId ?? storeId ?? UUID().uuidString }
    
    enum CodingKeys: String, CodingKey {
        case status, activities, address, tasks
        case rawId = "id"
        case storeId = "store_id"
        case storeName = "store_name"
        case name
    }
    
    init(rawId: String?, storeId: String?, storeName: String?, address: String?, status: String?, activities: [RouteActivity]?) {
        self.rawId = rawId
        self.storeId = storeId
        self.storeName = storeName
        self.address = address
        self.status = status
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
        activities = try container.decodeIfPresent([RouteActivity].self, forKey: .activities)
            ?? container.decodeIfPresent([RouteActivity].self, forKey: .tasks)
    }
}

struct RouteActivity: Codable, Identifiable {
    let id: String?
    let name: String?
    let status: String?
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
        
        // Defer background update activation to prevent launch-time crashes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            #if !targetEnvironment(simulator)
            // CRITICAL: This requires 'location' in UIBackgroundModes in project settings/Info.plist
            self.locationManager.allowsBackgroundLocationUpdates = true
            #endif
        }
    }
    func requestPermissions() { locationManager.requestWhenInUseAuthorization() }
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
        if Session.isDemoMode { return "demo-visit-id" }
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
            print("❌ LOG_VISIT_ERROR: \(error)")
            return nil
        }
    }
    
    // --- New Deep Diagnostic Helper ---
    private func performRequest<T: Codable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil
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
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        
        // --- PROD SYNC: Inject X-Org-Id if available ---
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
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
        
        if statusCode == 401 {
            print("⚠️ AUTH_ERROR: Unauthorized (401). Triggering Auto-Logout.")
            await MainActor.run { 
                Session.logout()
                AppState.shared.checkAuth()
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
        if Session.isDemoMode { return nil }
        print("LOADING_TEMPLATE_FOR_ACTIVITY: \(activityId)")
        
        do {
            let res: ApiResponse<[FormTemplate]>? = try await performRequest(
                "/forms/templates",
                queryItems: [URLQueryItem(name: "activity_id", value: activityId)]
            )
            return res?.data?.first
        } catch {
            return nil
        }
    }
    
    func submitForm(request: FormSubmissionRequest) async -> Bool {
        if Session.isDemoMode { return true }
        do {
            let body = try? JSONEncoder().encode(request)
            let res: ApiResponse<[String: String]>? = try await performRequest(
                "/forms/submit",
                method: "POST",
                body: body
            )
            return res?.success ?? false
        } catch {
            return false
        }
    }
    
    // --- BROADCAST ---
    func getBroadcastHistory() async -> [BroadcastQuestion] {
        if Session.isDemoMode { return [] }
        do {
            let res: ApiResponse<[BroadcastQuestion]>? = try await performRequest("/analytics/broadcasts")
            return res?.data ?? []
        } catch {
            return []
        }
    }
    
    func sendBroadcastAnswer(id: String, selectedIndex: Int) async -> Bool {
        if Session.isDemoMode { return true }
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
        if Session.isDemoMode { return [] }
        do {
            let res: ApiResponse<[LearningMaterial]>? = try await performRequest("/analytics/learning")
            return res?.data ?? []
        } catch {
            return []
        }
    }
    
    func login(email: String, phone: String?, pass: String) async -> (Bool, String?) {
        if email.lowercased() == "demo@kinematic.com" {
            await MainActor.run {
                Session.isDemoMode = true
                Session.sharedToken = "demo-token-123"
                Session.currentUser = User(id: "demo-id", name: "Demo Executive", role: "Field Executive", email: "demo@kinematic.com", mobile: "9999999999", orgId: "Kinematic Demo")
                AppState.shared.checkAuth()
            }
            return (true, nil)
        }
        
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
                        AppState.shared.checkAuth()
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
        if Session.isDemoMode { return "https://demo.kinematic.com/selfie.jpg" }
        
        let url = URL(string: "\(baseURL)/upload/\(type)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        if let orgId = Session.currentUser?.orgId { request.setValue(orgId, forHTTPHeaderField: "X-Org-Id") }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let imageData = image.jpegData(compressionQuality: 0.5) else { return nil }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"selfie.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("🚀 UPLOAD_START: \(url.absoluteString)")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let res = try JSONDecoder().decode(ApiResponse<UploadResponse>.self, from: data)
            return res.data?.url
        } catch {
            print("❌ UPLOAD_ERROR: \(error)")
            return nil
        }
    }
    
    func markAttendance(isCheckIn: Bool, lat: Double, lng: Double, selfieUrl: String? = nil, battery: Int? = nil) async -> (Bool, String?) {
        if Session.isDemoMode { return (true, nil) }
        let endpoint = isCheckIn ? "/attendance/checkin" : "/attendance/checkout"
        
        do {
            var payload: [String: Any] = ["latitude": lat, "longitude": lng]
            if let selfie = selfieUrl { payload["selfie_url"] = selfie }
            if let battery = battery { payload["battery_percentage"] = battery }
            
            let body = try? JSONSerialization.data(withJSONObject: payload)
            let res: ApiResponse<AttendanceRecord>? = try await performRequest(
                endpoint,
                method: "POST",
                body: body
            )
            if res?.success == true { return (true, nil) }
            return (false, res?.error ?? res?.message ?? "Failed to mark attendance")
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    func logSecurityViolation(type: String, action: String, lat: Double?, lng: Double?) async {
        if Session.isDemoMode { return }
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
        if Session.isDemoMode { return mockMobileHome() }
        do {
            let res: ApiResponse<MobileHomeResponse>? = try await performRequest("/analytics/mobile-home")
            if let home = res?.data {
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
        if Session.isDemoMode { return mockFeed() }
        do {
            let res: ApiResponse<[ActivityFeedItem]>? = try await performRequest("/feed")
            return res?.data ?? []
        } catch {
            return []
        }
    }
    
    func fetchMyRoutePlan() async -> [RoutePlan] {
        if Session.isDemoMode { return mockRoute() }
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
                    cache(data, forKey: cachedRoutePlanKey)
                } else {
                    // Server returned empty for today — clear stale cache so old data is not shown
                    UserDefaults.standard.removeObject(forKey: cachedRoutePlanKey)
                }
                // Always trust fresh server response, even if empty
                return data
            } else {
                print("⚠️ FETCH_ROUTE_PLAN_EMPTY: Success but no data. Message: \(res?.message ?? "N/A")")
                return loadCached([RoutePlan].self, forKey: cachedRoutePlanKey) ?? []
            }
        } catch {
            print("❌ FETCH_ROUTE_PLAN_ERROR: \(error)")
            // Only fall back to cache on network/decode errors
            return loadCached([RoutePlan].self, forKey: cachedRoutePlanKey) ?? []
        }
    }
    
    private func cache<T: Encodable>(_ value: T, forKey key: String) {
        guard let encoded = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }
    
    private func loadCached<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let raw = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: raw)
    }
    // --- MOCK DATA PROVIDER ---
    private func mockMobileHome() -> MobileHomeResponse {
        return MobileHomeResponse(
            today: AttendanceRecord(id: "1", date: "2024-04-08", status: "present", checkinAt: "2024-04-08T09:00:00Z", checkoutAt: nil, totalHours: 4.5, checkinSelfieUrl: nil, checkoutSelfieUrl: nil),
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
            RouteOutlet(rawId: "o1", storeId: "s1", storeName: "Global Mart", address: "123 Outer Ring Rd", status: "visited", activities: [
                RouteActivity(id: "a1", name: "Shelf Stocking", status: "completed")
            ]),
            RouteOutlet(rawId: "o2", storeId: "s2", storeName: "Metro Corner", address: "456 Inner Circle", status: "pending", activities: [
                RouteActivity(id: "a2", name: "Merchandising", status: "pending"),
                RouteActivity(id: "a3", name: "Price Audit", status: "pending")
            ]),
            RouteOutlet(rawId: "o3", storeId: "s3", storeName: "City Supermarket", address: "Market St, Plaza", status: "pending", activities: [
                RouteActivity(id: "a4", name: "Inventory", status: "pending")
            ])
        ]
        return [RoutePlan(id: "p1", planDate: "2024-04-08", status: "active", outlets: outlets)]
    }
}

@main
struct KinematicApp: App {
    @StateObject private var locationService = LocationTrackingService.shared
    @StateObject private var appState = AppState.shared
    @State private var isSplashScreenActive = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isSplashScreenActive {
                    SplashScreenView()
                        .transition(.opacity)
                } else {
                    ContentView()
                        .environmentObject(locationService)
                        .environmentObject(appState)
                }
            }
            .preferredColorScheme(appState.theme == .system ? nil : (appState.theme == .dark ? .dark : .light))
            .task {
                locationService.requestPermissions()
                
                // Run startup sync in parallel so splash duration stays fixed at 3 seconds.
                if Session.isAuthenticated {
                    Task { await appState.attendanceVM.refresh() }
                }
                
                // Dismiss splash in exactly 3 seconds.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        isSplashScreenActive = false
                    }
                }
            }
        }
    }
}

struct SplashScreenView: View {
    @State private var startAnimation = false
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            // Atmospheric Glow
            RadialGradient(
                gradient: Gradient(colors: [Color.red.opacity(0.12), Color.clear]),
                center: .center,
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()
            
            VStack(spacing: 12) {
                Text("Kinematic")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(Color(uiColor: .label))
                    .tracking(4)
                    .scaleEffect(startAnimation ? 1.0 : 0.95)
                    .opacity(startAnimation ? 1.0 : 0)
                
                Text("Your 1 stop solution for manpower management")
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundColor(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(startAnimation ? 0.8 : 0)
                    .offset(y: startAnimation ? 0 : 10)
            }
            
            VStack {
                Spacer()
                Text("SECURED BY KINEMATIC SHIELD")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                    .tracking(2)
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                startAnimation = true
            }
        }
    }
}
