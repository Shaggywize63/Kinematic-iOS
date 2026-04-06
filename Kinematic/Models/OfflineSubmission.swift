import Foundation
import SwiftData

/// Represents a form submission held locally when the device is offline.
/// Mirrors the Android 'OfflineSubmission' entity for data parity.
@Model
final class OfflineSubmission {
    var id: UUID
    var templateId: String
    var activityId: String?
    var outletId: String?
    var outletName: String?
    var latitude: Double?
    var longitude: Double?
    
    /// Serialized JSON string of the form responses (List<FormResponse>)
    var responsesJson: String
    var submittedAt: Date
    var isSynced: Bool
    
    init(
        templateId: String,
        activityId: String? = nil,
        outletId: String? = nil,
        outletName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        responsesJson: String,
        submittedAt: Date = Date(),
        isSynced: Bool = false
    ) {
        self.id = UUID()
        self.templateId = templateId
        self.activityId = activityId
        self.outletId = outletId
        self.outletName = outletName
        self.latitude = latitude
        self.longitude = longitude
        self.responsesJson = responsesJson
        self.submittedAt = submittedAt
        self.isSynced = isSynced
    }
}
