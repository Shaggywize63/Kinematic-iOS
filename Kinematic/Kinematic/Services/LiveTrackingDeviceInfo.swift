import Foundation
import UIKit

/// Snapshot of the device fields that the dashboard's Live-Tracking page
/// expects on every heartbeat. This brings iOS to parity with Android, which
/// already populates `device_model`, `device_brand`, and `os_version` on
/// every `PATCH /api/v1/users/status` call.
struct DeviceInfoSnapshot: Codable {
    let deviceModel: String
    let deviceBrand: String
    let osVersion: String

    enum CodingKeys: String, CodingKey {
        case deviceModel = "device_model"
        case deviceBrand = "device_brand"
        case osVersion   = "os_version"
    }

    /// Best-effort capture from `UIDevice` plus the Mach `utsname` for the
    /// hardware identifier (e.g. "iPhone15,2"). The dashboard renders this
    /// alongside the FE's pin so a supervisor can spot a flaky/old device.
    static func capture() -> DeviceInfoSnapshot {
        let device = UIDevice.current
        return DeviceInfoSnapshot(
            deviceModel: hardwareIdentifier(),
            deviceBrand: "Apple",
            osVersion: "iOS \(device.systemVersion)"
        )
    }

    private static func hardwareIdentifier() -> String {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        let id = mirror.children.reduce(into: "") { acc, child in
            guard let value = child.value as? Int8, value != 0 else { return }
            acc.append(String(UnicodeScalar(UInt8(value))))
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
}

/// Heartbeat payload sent on every location update during an active shift.
/// Mirrors the Android `UserStatusUpdate` model so the backend's
/// `updateUserStatus` controller persists the same columns regardless of
/// platform. Posting to `/api/v1/users/status` (matching Android) instead of
/// the legacy `/attendance/pings` route gives the dashboard a single source
/// of truth and unlocks the device + battery columns in `live-locations`.
struct UserStatusUpdate: Codable {
    let latitude: Double
    let longitude: Double
    let batteryPercentage: Int?
    let activityType: String?
    let deviceModel: String?
    let deviceBrand: String?
    let osVersion: String?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case batteryPercentage = "battery_percentage"
        case activityType      = "activity_type"
        case deviceModel       = "device_model"
        case deviceBrand       = "device_brand"
        case osVersion         = "os_version"
    }

    /// Convenience builder with the common HEARTBEAT defaults so callers do
    /// not have to remember every field name.
    static func heartbeat(lat: Double, lng: Double, battery: Int?) -> UserStatusUpdate {
        let device = DeviceInfoSnapshot.capture()
        return UserStatusUpdate(
            latitude: lat,
            longitude: lng,
            batteryPercentage: battery,
            activityType: "HEARTBEAT",
            deviceModel: device.deviceModel,
            deviceBrand: device.deviceBrand,
            osVersion: device.osVersion
        )
    }
}

/// Current battery percentage in `0...100`. Returns `nil` when the device
/// reports `batteryLevel == -1` (e.g. simulator or monitoring is disabled).
@MainActor
func currentBatteryPercentage() -> Int? {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = UIDevice.current.batteryLevel
    if level < 0 { return nil }
    return Int((level * 100).rounded())
}
