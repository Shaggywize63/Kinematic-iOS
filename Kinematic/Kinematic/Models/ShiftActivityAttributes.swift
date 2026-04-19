import ActivityKit
import Foundation

struct ShiftActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var checkinDate: Date
        var checkoutDate: Date?
        var progressPercent: Double   // 0.0 – 1.0  (based on 8-hour target)
        var elapsedSeconds: Int
        var isActive: Bool
    }

    var userName: String
    var targetHours: Int              // default 8
}
