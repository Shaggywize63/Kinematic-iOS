import Foundation
import UIKit

/// Click-to-chat helpers for WhatsApp.
/// Builds wa.me deep links and opens them via the system; the app or web
/// version of WhatsApp handles delivery — we never call the Business API.
enum WhatsAppHelper {
    static func sanitize(_ phone: String) -> String? {
        let digits = phone
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "+", with: "")
        guard digits.count >= 8, digits.allSatisfy({ $0.isNumber }) else { return nil }
        return digits
    }

    static func waLink(phone: String, text: String? = nil) -> URL? {
        guard let digits = sanitize(phone) else { return nil }
        var components = URLComponents(string: "https://wa.me/\(digits)")
        if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components?.queryItems = [URLQueryItem(name: "text", value: t)]
        }
        return components?.url
    }

    static func canOpen(phone: String?) -> Bool {
        guard let phone, let _ = sanitize(phone) else { return false }
        return true
    }

    @MainActor
    static func open(phone: String, text: String? = nil) -> Bool {
        guard let url = waLink(phone: phone, text: text) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}
