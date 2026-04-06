import Foundation
import UIKit
import SwiftData

/// Simulates the user session. In a full implementation, this holds the JWT.
struct Session {
    static var sharedToken = ""
}

class KinematicRepository: ObservableObject {
    static let shared = KinematicRepository()
    
    // Configurable base URL
    private let baseURL = "https://your-kinematic-backend.com/api/v1"
    
    /// Sends the location heartbeat to the Node.js backend.
    func updateStatus(
        latitude: Double,
        longitude: Double,
        batteryPercentage: Int,
        activityType: String = "HEARTBEAT"
    ) {
        guard let url = URL(string: "\(baseURL)/misc/update-status") else { return }
        
        let deviceModel = UIDevice.current.model
        let osVersion = UIDevice.current.systemVersion
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
    
    /// Entry point for submitting a form. 
    /// Automatically handles the choice between API upload and Offline Storage.
    @MainActor
    func submitForm(
        templateId: String,
        activityId: String? = nil,
        outletId: String? = nil,
        outletName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        responses: [String: Any],
        context: ModelContext
    ) async -> Bool {
        // 1. Serialize responses to JSON string for storage/transmission
        guard let jsonData = try? JSONSerialization.data(withJSONObject: responses),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return false
        }
        
        // 2. Check Connection
        if NetworkMonitor.shared.isConnected {
            print("Kinematic iOS: Device is online — Attempting API upload")
            let success = await uploadSubmission(
                templateId: templateId,
                activityId: activityId,
                outletId: outletId,
                outletName: outletName,
                latitude: latitude,
                longitude: longitude,
                responsesJson: jsonString
            )
            if success { return true }
        }
        
        // 3. If offline or API fails, Save to local SwiftData
        print("Kinematic iOS: Device is offline or API failed — Saving to local storage")
        let offlineItem = OfflineSubmission(
            templateId: templateId,
            activityId: activityId,
            outletId: outletId,
            outletName: outletName,
            latitude: latitude,
            longitude: longitude,
            responsesJson: jsonString
        )
        context.insert(offlineItem)
        
        do {
            try context.save()
            return false // Return false to indicate it wasn't a live sync, but it is "saved"
        } catch {
            print("Kinematic iOS: Failed to save offline submission — \(error.localizedDescription)")
            return false
        }
    }
    
    // ── Dynamic Form Offline Sync Logic ────────────────────────
    
    /// Syncs all pending offline submissions to the remote server.
    /// This precisely mirrors the Android 'syncOfflineSubmissions' logic.
    @MainActor
    func syncPendingSubmissions(context: ModelContext) async -> Int {
        print("Kinematic iOS: Checking for pending submissions...")
        
        let descriptor = FetchDescriptor<OfflineSubmission>(predicate: #Predicate { $0.isSynced == false })
        
        do {
            let pendingArr = try context.fetch(descriptor)
            var count = 0
            
            for item in pendingArr {
                let success = await uploadSubmission(item)
                if success {
                    context.delete(item)
                    count += 1
                }
            }
            
            try context.save()
            print("Kinematic iOS: Synchronized \(count) pending items.")
            return count
        } catch {
            print("Kinematic iOS: Sync failed — \(error.localizedDescription)")
            return 0
        }
    }
    
    /// Private helper to attempt a single API upload.
    private func uploadSubmission(
        templateId: String,
        activityId: String? = nil,
        outletId: String? = nil,
        outletName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        responsesJson: String
    ) async -> Bool {
        guard let url = URL(string: "\(baseURL)/forms/submit") else { return false }
        
        // Reconstruct for payload
        guard let data = responsesJson.data(using: .utf8),
              let jsonResponses = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        
        let payload: [String: Any] = [
            "template_id": templateId,
            "activity_id": activityId ?? NSNull(),
            "outlet_id": outletId ?? NSNull(),
            "outlet_name": outletName ?? NSNull(),
            "latitude": latitude ?? 0.0,
            "longitude": longitude ?? 0.0,
            "submitted_at": ISO8601DateFormatter().string(from: Date()),
            "is_converted": true,
            "responses": jsonResponses
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                return true
            }
        } catch {
            print("Kinematic iOS: Network upload failed — \(error.localizedDescription)")
        }
        return false
    }
    
    @MainActor
    private func uploadSubmission(_ item: OfflineSubmission) async -> Bool {
        return await uploadSubmission(
            templateId: item.templateId,
            activityId: item.activityId,
            outletId: item.outletId,
            outletName: item.outletName,
            latitude: item.latitude,
            longitude: item.longitude,
            responsesJson: item.responsesJson
        )
    }
}
