import Foundation
import UIKit

/// Simulates the user session. In a full implementation, this holds the JWT.
struct Session {
    static var sharedToken = ""
}

class KinematicRepository {
    static let shared = KinematicRepository()
    
    // Configurable base URL
    private let baseURL = "https://your-kinematic-backend.com/api/v1"
    
    /// Sends the location heartbeat to the Node.js backend.
    /// This mirrors the `updateStatus` function from the Android application.
    func updateStatus(
        latitude: Double,
        longitude: Double,
        batteryPercentage: Int,
        activityType: String = "HEARTBEAT"
    ) {
        guard let url = URL(string: "\(baseURL)/misc/update-status") else { return }
        
        // Capture Apple device information to parallel the Android 'android.os.Build' hardware capture
        let deviceModel = UIDevice.current.model // e.g. "iPhone" or "iPad"
        let osVersion = UIDevice.current.systemVersion // e.g. "17.4"
        let deviceBrand = "Apple"
        
        let payload: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "battery_percentage": batteryPercentage,
            "activity_type": activityType,
            "device_model": deviceModel,
            "device_brand": deviceBrand,
            "os_version": osVersion
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Use the auth token generated during Phase 1 login
        request.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            print("Failed to serialize heartbeat payload: \(error)")
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Heartbeat network error: \(error.localizedDescription)")
                return
            }
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                print("Successfully pinged backend at lat: \(latitude), lng: \(longitude)")
            } else {
                print("Heartbeat rejected by backend.")
            }
        }
        task.resume()
    }
}
