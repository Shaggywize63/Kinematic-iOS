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
            print("🕒 [HomeVM] Throttled. Using fresh KiniAppState.")
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
                KiniAppState.shared.today = today
            }
            
            if let summ = newData?.summary {
                KiniAppState.shared.summary = summ
            }
            if let q = newData?.quote {
                KiniAppState.shared.quote = q
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

import Combine

extension Notification.Name {
    static let triggerCamera = Notification.Name("TriggerSelfieCamera")
}

class AttendanceViewModel: ObservableObject {
    @Published var today: AttendanceRecord?
    @Published var isLoading = false
    @Published var message = ""
    /// Locally persisted check-in location stamp (lat,lng string) shown when the
    /// server does not return location coordinates in the AttendanceRecord.
    @Published var checkinLocationStamp: String? = UserDefaults.standard.string(forKey: "checkin_location_stamp")
    @Published var selfie: UIImage?
    private var autoSubmitScheduled = false
    private var cancellables = Set<AnyCancellable>()
    
    func processCapturedSelfie(image: UIImage) {
        self.selfie = image
        self.autoSubmitScheduled = true
        checkLocationAndSubmit()
    }
    
    private func checkLocationAndSubmit() {
        if let loc = LocationTrackingService.shared.lastLocation {
            autoSubmitScheduled = false
            Task { await toggleAttendance(loc: loc) }
        } else {
            isLoading = true // Show progress while waiting
            message = "Waiting for high-precision GPS..."
            LocationTrackingService.shared.startTracking()
            
            // Listen for first valid location update to resume flow
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
        
        KiniAppState.shared.attendanceVM.processCapturedSelfie(image: mockImage ?? UIImage())
        self.message = "SIMULATOR: Mock selfie captured."
    }
    
    func startFlow() {
        print("🔥 [CRITICAL] BROADCASTING CAMERA SIGNAL")
        print("🚀 ATTEMPT: startFlow() signal broadcasted")
        print("📸 [AttendanceVM] startFlow() entered")
        self.autoSubmitScheduled = true
        
        // Drive presentation through shared state so the camera cover opens
        // even if a notification listener misses the event.
        KiniAppState.shared.triggerCamera()
        
        // Keep the broadcast as a fallback for legacy listeners.
        NotificationCenter.default.post(name: .triggerCamera, object: nil)
        
        // --- STABILITY: Defer GPS start by a few ms to allow UI to breathe ---
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await MainActor.run {
                LocationTrackingService.shared.startTracking()
            }
        }
    }

    private var lastRefreshTime: Date?
    private var lastAttendanceActionTime: Date? // Guard against stale server data
    private var isRefreshing = false

    func refresh(force: Bool = false) async {
        // --- STABILITY: Concurrency Guard ---
        guard !isRefreshing else { return }
        
        // --- PERFORMANCE: Throttling (Bypass with 'force') ---
        if !force {
            if let last = lastRefreshTime, Date().timeIntervalSince(last) < 30 {
                return
            }
        }
        
        isRefreshing = true
        defer { isRefreshing = false }

        let data = await KinematicRepository.shared.getMobileHome()
        await MainActor.run { 
            self.lastRefreshTime = Date()
            let serverToday = data?.today
            
            // ── STABILITY: Stale-State Guard (Extended 2m) ──────────
            if let lastAction = self.lastAttendanceActionTime, Date().timeIntervalSince(lastAction) < 120 {
                let localIsIn = KiniAppState.shared.today?.isIn ?? false
                let serverIsIn = serverToday?.isIn ?? false
                
                // ── SYMMETRIC PROTECTION ──
                if localIsIn != serverIsIn {
                    print("🛡️ [Attendance] Symmetric Protection: Ignoring stale server state (\(serverIsIn ? "In" : "Out")).")
                    return
                }
            }
            
            KiniAppState.shared.today = serverToday
            self.today = serverToday
            
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
        // --- CONCURRENCY LOCK (Anti-Double-Firing) ---
        guard !isLoading else { return }
        
        let currentSession = KiniAppState.shared.today
        let isCheckIn = currentSession?.checkinAt == nil
        
        // --- SINGLE-CYCLE GUARD ---
        if currentSession?.checkoutAt != nil {
            await MainActor.run { message = "Shift already completed for today." }
            return
        }
        let action = isCheckIn ? "CHECK_IN" : "CHECK_OUT"
        
        guard await checkSecurity(action: action, lat: loc.coordinate.latitude, lng: loc.coordinate.longitude) else { return }
        
        // OPTIMISTIC UI — flip `today` to the new state immediately so the
        // user sees "Checked In" / "Checked Out" the moment they commit, even
        // while the selfie upload + markAttendance round-trip is in flight.
        // Saves the perceived 1.5–2 s wait on slow networks. We hold the
        // previous value so we can revert on failure.
        let previousToday = await MainActor.run { () -> AttendanceRecord? in
            return self.today
        }
        await MainActor.run {
            isLoading = true
            message = ""
            self.lastAttendanceActionTime = Date()

            let nowIso = ISO8601DateFormatter().string(from: Date())
            var optimistic = previousToday ?? AttendanceRecord(
                id: nil, date: nil, status: nil,
                checkinAt: nil, checkoutAt: nil,
                totalHours: 0, checkinSelfieUrl: nil, checkoutSelfieUrl: nil
            )
            if isCheckIn {
                optimistic.status = "present"
                if optimistic.firstCheckinAt == nil { optimistic.firstCheckinAt = nowIso }
                optimistic.checkinAt = nowIso
                optimistic.checkoutAt = nil
            } else {
                optimistic.status = "checked_out"
                optimistic.checkoutAt = nowIso
                optimistic.lastCheckoutAt = nowIso
            }
            self.today = optimistic
            KiniAppState.shared.today = optimistic
        }

        // Integrate Battery Telemetry safely on MainActor
        let batteryLevel = await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            return Int(UIDevice.current.batteryLevel * 100)
        }

        var selfieUrl: String? = nil
        if let img = selfie {
            selfieUrl = await KinematicRepository.shared.uploadImage(image: img, type: "selfie")
            if selfieUrl == nil {
                await MainActor.run {
                    self.today = previousToday                       // rollback
                    KiniAppState.shared.today = previousToday
                    isLoading = false
                    message = "Failed to upload selfie"
                    self.lastAttendanceActionTime = nil
                }
                return
            }
        } else {
            // Android Parity: Force selfie for Field Executives
            let isExecutive = Session.currentUser?.role.lowercased().contains("executive") ?? false
            if isExecutive {
                await MainActor.run {
                    self.today = previousToday                       // rollback
                    KiniAppState.shared.today = previousToday
                    isLoading = false
                    message = "Selfie is required for Executives"
                    self.lastAttendanceActionTime = nil
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
            if success {
                // ── ATOMIC STATE PROTECTION ─────────────────────────
                // Merge server response with local intent. We NEVER want 
                // to appear Offline immediately after a 200 OK Check-In.
                let nowIso = ISO8601DateFormatter().string(from: Date())
                var merged = record ?? KiniAppState.shared.today ?? AttendanceRecord(id: nil, date: nil, status: nil, checkinAt: nil, checkoutAt: nil, totalHours: 0, checkinSelfieUrl: nil, checkoutSelfieUrl: nil)
                
                if isCheckIn {
                    merged.status = "present"
                    // Preserve FIRST check-in ever, but update CURRENT check-in for the "Ongoing since" display
                    if merged.firstCheckinAt == nil { merged.firstCheckinAt = nowIso }
                    merged.checkinAt = nowIso
                    merged.checkoutAt = nil 
                } else {
                    merged.status = "checked_out"
                    // Update CURRENT checkout and LAST checkout
                    merged.checkoutAt = nowIso
                    merged.lastCheckoutAt = nowIso 
                }
                
                KiniAppState.shared.today = merged
                self.today = merged
                
                // Track completion time for final guard window
                self.lastAttendanceActionTime = Date()
                // Clear selfie
                self.selfie = nil
                message = isCheckIn ? "Checked in!" : "Checked out!"

                if isCheckIn {
                    let stamp = String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)
                    checkinLocationStamp = stamp
                    UserDefaults.standard.set(stamp, forKey: "checkin_location_stamp")
                    LocationTrackingService.shared.startTracking()
                } else {
                    LocationTrackingService.shared.stopTracking()
                }
            } else {
                self.today = previousToday                           // rollback optimistic
                KiniAppState.shared.today = previousToday
                isLoading = false
                message = err ?? "Submission failed"
                self.lastAttendanceActionTime = nil // Release lock on failure
            }
        }
        
        // Force refresh to pull GROUND TRUTH bypassing throttles
        await refresh(force: true)
        
        // RELEASE LOADING STATE ONLY AFTER SYNC IS COMPLETE
        await MainActor.run { self.isLoading = false }
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
