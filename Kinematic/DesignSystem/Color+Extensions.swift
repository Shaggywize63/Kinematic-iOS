import SwiftUI

extension Color {
    // Kinematic Brand Colors
    static let kRed = Color(hex: "E01E2C")
    static let kDark = Color(hex: "0A0E17")
    
    // Vibrant Gradients (for Liquid Glass backgrounds)
    static let kGradient1 = Color(hex: "4A00E0")
    static let kGradient2 = Color(hex: "8E2DE2")
    static let kGradient3 = Color(hex: "FF416C")
    static let kGradient4 = Color(hex: "FF4B2B")
    
    // Utilities
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
