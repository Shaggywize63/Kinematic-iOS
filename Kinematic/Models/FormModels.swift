import Foundation

/// Defines the supported input types for the Kinematic dynamic forms
enum FormFieldType: String, Codable {
    case text = "text"
    case number = "number"
    case boolean = "boolean"
    case multiselect = "multiselect"
    case select = "select"
    case date = "date"
    case location = "location"
    case camera = "camera"
    case signature = "signature"
}

/// Represents a single question in the dynamic form schema
struct FormQuestion: Identifiable, Codable, Hashable {
    let id: String
    let formId: String
    let title: String
    let description: String?
    let type: FormFieldType
    let isRequired: Bool
    
    // Configurable payload specific to certain input types
    let options: [String]? // Used for select/multiselect
    let validationRegex: String?
    let orderIndex: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case formId = "form_id"
        case title
        case description
        case type
        case isRequired = "is_required"
        case options
        case validationRegex = "validation_regex"
        case orderIndex = "order_index"
    }
}

/// A wrapper to hold state representations for completed answers
class FormResponseState: ObservableObject {
    @Published var stringValues: [String: String] = [:]
    @Published var numberValues: [String: Double] = [:]
    @Published var boolValues: [String: Bool] = [:]
    @Published var stringArrayValues: [String: Set<String>] = [:]
    
    // Stores captured image URLs or local cached paths
    @Published var mediaPaths: [String: String] = [:] 
    // Latitude, Longitude combinations
    @Published var locationValues: [String: String] = [:] 
    
    func reset() {
        stringValues.removeAll()
        numberValues.removeAll()
        boolValues.removeAll()
        stringArrayValues.removeAll()
        mediaPaths.removeAll()
        locationValues.removeAll()
    }
}
