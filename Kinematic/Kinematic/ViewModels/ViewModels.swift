import SwiftUI
import Combine
import CoreLocation

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
    @Published var showSubmissionSuccess = false
    
    var uniqueOutlets: [RouteOutlet] {
        let raw = data?.routePlan?.flatMap { $0.outlets ?? [] } ?? []
        var unique: [RouteOutlet] = []
        var seenIds = Set<String>()
        for o in raw {
            let oid = o.id
            if !seenIds.contains(oid) {
                unique.append(o)
                seenIds.insert(oid)
            }
        }
        return unique
    }
    
    var totalStoreCount: Int {
        uniqueOutlets.count
    }
    
    var visitedStoreCount: Int {
        uniqueOutlets.filter { $0.status == "visited" }.count
    }
    
    private var lastRefreshTime: Date?
    
    func refresh() async {
        // --- PERFORMANCE: Throttling (Parity with high-end Android) ---
        // Avoid redundant calls if refreshed in last 30 seconds
        if let last = lastRefreshTime, Date().timeIntervalSince(last) < 30 {
            print("🕒 [HomeVM] Throttled. Using fresh AppState.")
            return
        }
        
        await MainActor.run { isLoading = true }
        let newData = await KinematicRepository.shared.getMobileHome()
        await MainActor.run { 
            self.data = newData
            self.isLoading = false
            self.lastRefreshTime = Date()
            
            // Centralized State Sync (Android Parity)
            if let today = newData?.today {
                AppState.shared.today = today
            }
            
            if let summ = newData?.summary {
                AppState.shared.summary = summ
            }
            if let q = newData?.quote {
                AppState.shared.quote = q
            }
        }
    }
    
    func submitBroadcastAnswer(id: String, selectedIndex: Int) async {
        // Optimistic UI update: instantly mark as answered and force local refresh
        await MainActor.run {
            if var broadcast = data?.broadcast, broadcast.id == id {
                broadcast.alreadyAnswered = true
                self.data?.broadcast = broadcast
                self.data?.alreadyAnswered = true // Critical Sync: Update top-level flag too
                self.showSubmissionSuccess = true
            }
        }
        
        _ = await KinematicRepository.shared.sendBroadcastAnswer(id: id, selectedIndex: selectedIndex)
        
        // Keep success message for 3 seconds
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await MainActor.run { self.showSubmissionSuccess = false }
        
        // Refresh from server to get final consistent state
        await refresh()
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
    /// Locally persisted check-in location stamp (lat,lng string) shown when the
    /// server does not return location coordinates in the AttendanceRecord.
    @Published var checkinLocationStamp: String? = UserDefaults.standard.string(forKey: "checkin_location_stamp")
    @Published var selfie: UIImage? {
        didSet {
            // Automatically trigger attendance if we are in automated flow
            if selfie != nil && autoSubmitScheduled {
                checkLocationAndSubmit()
            }
        }
    }
    @Published var showCamera = false
    private var autoSubmitScheduled = false
    private var cancellables = Set<AnyCancellable>()
    
    private func checkLocationAndSubmit() {
        if let loc = LocationTrackingService.shared.lastLocation {
            autoSubmitScheduled = false
            Task { await toggleAttendance(loc: loc) }
        } else {
            message = "Waiting for GPS..."
            LocationTrackingService.shared.startTracking()
            
            // Parity with Android: Listen for first valid location update to resume flow
            LocationTrackingService.shared.$lastLocation
                .compactMap { $0 }
                .first()
                .sink { [weak self] loc in
                    guard let self = self, self.autoSubmitScheduled else { return }
                    self.autoSubmitScheduled = false
                    Task { await self.toggleAttendance(loc: loc) }
                }
                .store(in: &cancellables)
        }
    }
    
    func useMockSelfie() {
        // Create a professional colored placeholder to represent a successful mock capture
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        UIGraphicsBeginImageContext(rect.size)
        if let context = UIGraphicsGetCurrentContext() {
            context.setFillColor(UIColor.systemRed.cgColor)
            context.fill(rect)
            
            // Draw a simple smiley or text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let string = NSAttributedString(string: "☺", attributes: attributes)
            string.draw(in: CGRect(x: 80, y: 70, width: 60, height: 60))
        }
        let mockImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        self.selfie = mockImage
        self.message = "SIMULATOR: Mock selfie captured."
    }
    
    func startFlow() {
        self.autoSubmitScheduled = true
        
        // --- STABILITY: Immediate UI State Change (Priority 1) ---
        // We set showCamera BEFORE starting other tasks to ensure the sheet animation begins.
        self.showCamera = true
        
        // --- STABILITY: Defer GPS start by a few ms to allow UI to breathe ---
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await MainActor.run {
                LocationTrackingService.shared.startTracking()
            }
        }
    }

    
    private var lastRefreshTime: Date?

    func refresh() async {
        // --- PERFORMANCE: Throttling ---
        if let last = lastRefreshTime, Date().timeIntervalSince(last) < 30 {
            return
        }

        let data = await KinematicRepository.shared.getMobileHome()
        await MainActor.run { 
            self.lastRefreshTime = Date()
            let serverToday = data?.today
            
            // ── STABILITY FIX (Android Parity) ──────────────────────
            // If server returns null but we are ALREADY checked in locally, 
            // PRESERVE the status to prevent UI flickering or session loss.
            if serverToday == nil && (AppState.shared.today?.checkinAt != nil && AppState.shared.today?.checkoutAt == nil) {
                print("⚠️ [Attendance] Server sent null, but local is active. Preserving state.")
                return 
            }
            
            AppState.shared.today = serverToday
            
            // Android Parity: Resume tracking if checked in
            if let status = serverToday?.status, status == "present" || status == "checked_in" {
                LocationTrackingService.shared.startTracking()
            }
        }
    }
    
    // ── Security Check Helper ──────────────────────────────────
    private func checkSecurity(action: String, lat: Double? = nil, lng: Double? = nil) async -> Bool {
        // [iOS Parity] Mock Location check via accuracy
        if let loc = LocationTrackingService.shared.lastLocation, loc.horizontalAccuracy < 0 {
            let msg = "Unreliable location detected. Please disable mock apps."
            await MainActor.run { message = msg }
            // Log violation to backend for parity
            await KinematicRepository.shared.logSecurityViolation(type: "MOCK_LOCATION", action: action, lat: lat, lng: lng)
            return false
        }
        
        return true
    }

    func toggleAttendance(loc: CLLocation) async {
        let currentSession = AppState.shared.today
        let isCheckIn = currentSession?.checkinAt == nil || (currentSession?.checkinAt != nil && currentSession?.checkoutAt != nil)
        let action = isCheckIn ? "CHECK_IN" : "CHECK_OUT"
        
        guard await checkSecurity(action: action, lat: loc.coordinate.latitude, lng: loc.coordinate.longitude) else { return }
        
        await MainActor.run { isLoading = true; message = "" }
        
        // Integrate Battery Telemetry
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = Int(UIDevice.current.batteryLevel * 100)
        
        var selfieUrl: String? = nil
        if let img = selfie {
            selfieUrl = await KinematicRepository.shared.uploadImage(image: img, type: "selfie")
            if selfieUrl == nil {
                await MainActor.run {
                    isLoading = false
                    message = "Failed to upload selfie"
                }
                return
            }
        } else {
            // Android Parity: Force selfie for Field Executives
            let isExecutive = Session.currentUser?.role.lowercased().contains("executive") ?? false
            if isExecutive {
                await MainActor.run {
                    isLoading = false
                    message = "Selfie is required for Executives"
                }
                return
            }
        }
        
        let (success, err, record) = await KinematicRepository.shared.markAttendance(
            isCheckIn: isCheckIn, 
            lat: loc.coordinate.latitude, 
            lng: loc.coordinate.longitude, 
            selfieUrl: selfieUrl,
            battery: batteryLevel >= 0 ? batteryLevel : nil // -100 if unknown
        )
        
        await MainActor.run {
            isLoading = false
            if success {
                // ── IMMEDIATE STATE UPDATE (Android Parity) ─────────
                // Instantly update the UI with the record returned from the API
                if let newRecord = record {
                    AppState.shared.today = newRecord
                }
                
                message = isCheckIn ? "Checked in!" : "Checked out!"
                // Clear local selfie so it doesn't persist
                selfie = nil
                
                if isCheckIn {
                    let stamp = String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)
                    checkinLocationStamp = stamp
                    UserDefaults.standard.set(stamp, forKey: "checkin_location_stamp")
                    LocationTrackingService.shared.startTracking()
                } else {
                    checkinLocationStamp = nil
                    UserDefaults.standard.removeObject(forKey: "checkin_location_stamp")
                    LocationTrackingService.shared.stopTracking()
                }
            } else {
                message = err ?? "Failed"
            }
        }
        await refresh()
    }
}

class BroadcastHubViewModel: ObservableObject {
    @Published var broadcasts: [BroadcastQuestion] = []
    @Published var isLoading = false
    
    func refresh() async {
        await MainActor.run { isLoading = true }
        let newBroadcasts = await KinematicRepository.shared.getBroadcastHistory()
        await MainActor.run {
            self.broadcasts = newBroadcasts
            self.isLoading = false
        }
    }
    
    func submitAnswer(id: String, selectedIndex: Int) async {
        await MainActor.run { isLoading = true }
        _ = await KinematicRepository.shared.sendBroadcastAnswer(id: id, selectedIndex: selectedIndex)
        await refresh()
    }
}

class LearningHubViewModel: ObservableObject {
    @Published var materials: [LearningMaterial] = []
    @Published var isLoading = false
    
    var categories: [String] {
        let cats = Set(materials.compactMap { $0.category })
        return ["All"] + Array(cats).sorted()
    }
    
    var completedMandatoryCount: Int {
        materials.filter { ($0.isMandatory ?? false) && ($0.myProgress?.isCompleted ?? false) }.count
    }
    
    var totalMandatoryCount: Int {
        materials.filter { $0.isMandatory ?? false }.count
    }
    
    var progressPercentage: Double {
        guard totalMandatoryCount > 0 else { return 100 }
        return Double(completedMandatoryCount) / Double(totalMandatoryCount)
    }
    
    func refresh() async {
        await MainActor.run { isLoading = true }
        let newMaterials = await KinematicRepository.shared.getLearningMaterials()
        await MainActor.run {
            self.materials = newMaterials
            self.isLoading = false
        }
    }
}
