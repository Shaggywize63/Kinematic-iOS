import Foundation
import CoreLocation
import UIKit

/// Manages continuous background location tracking for Field Executives
class LocationTrackingService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationTrackingService()
    
    private let locationManager = CLLocationManager()
    @Published var isTrackingActive = false
    
    // Limits the frequency of API calls during movement
    private var lastPingTime: Date = Date.distantPast
    private let pingInterval: TimeInterval = 60.0 // 1 minute
    
    override private init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // Only update if the user moves 10 meters, saving battery
        locationManager.distanceFilter = 10.0
        
        // Critical for iOS background execution matching Android's Foreground Service
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    func requestPermissions() {
        // iOS requires 'WhenInUse' first, then 'Always' can be requested later or implicitly depending on plist.
        locationManager.requestAlwaysAuthorization()
    }
    
    func startTracking() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        
        UIDevice.current.isBatteryMonitoringEnabled = true
        locationManager.startUpdatingLocation()
        // Standard monitoring for significant changes to keep app alive
        locationManager.startMonitoringSignificantLocationChanges()
        
        isTrackingActive = true
        print("Started Kinematic iOS Background Tracking")
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        isTrackingActive = false
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // --- 1. Mock Location Detection (Security) ---
        // Apple provides sourceInformation in iOS 15+ to detect if location is simulated by Xcode or GPS spoofers
        if #available(iOS 15.0, *) {
            if let source = location.sourceInformation {
                if source.isSimulatedBySoftware || source.isProducedByAccessory {
                    print("SECURITY WARNING: Simulated location detected!")
                    // We could mark attendance as invalid here
                }
            }
        }
        
        // --- 2. Rate Limiting ---
        let now = Date()
        guard now.timeIntervalSince(lastPingTime) >= pingInterval else {
            return
        }
        lastPingTime = now
        
        // --- 3. Gather Battery Data ---
        let batteryLevel = Int(abs(UIDevice.current.batteryLevel) * 100) // Converts 0.85 -> 85
        let finalBattery = batteryLevel < 0 ? 50 : batteryLevel // fallback if unsupported
        
        // --- 4. Fire Heartbeat API ---
        KinematicRepository.shared.updateStatus(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            batteryPercentage: finalBattery,
            activityType: "HEARTBEAT"
        )
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed: \(error.localizedDescription)")
    }
}
