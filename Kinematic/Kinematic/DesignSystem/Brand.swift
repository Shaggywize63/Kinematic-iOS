// Kinematic Brand Identity v1.0 — see BRAND.md
// The visual and verbal system for the Kinematic field force management platform.

import SwiftUI

public enum Brand {

    // MARK: - Primary palette
    public static let red    = Color(red: 0xD0/255.0, green: 0x1E/255.0, blue: 0x2C/255.0) // Kinematic Red · Pantone 186 C
    public static let ink    = Color(red: 0x0A/255.0, green: 0x0E/255.0, blue: 0x1A/255.0) // Kinematic Ink · Pantone Black 6 C
    public static let paper  = Color.white                                                  // Paper White

    // MARK: - Secondary palette
    public static let navy   = Color(red: 0x0E/255.0, green: 0x1A/255.0, blue: 0x2E/255.0) // Deep Navy · Pantone 5395 C
    public static let stone  = Color(red: 0xFA/255.0, green: 0xFA/255.0, blue: 0xFB/255.0) // Stone
    public static let rule   = Color(red: 0xE4/255.0, green: 0xE6/255.0, blue: 0xEB/255.0) // Rule Grey

    // MARK: - Functional palette (product UI only — never marketing)
    public static let success = Color(red: 0x0A/255.0, green: 0x8A/255.0, blue: 0x4E/255.0) // Success Green
    public static let caution = Color(red: 0xC9/255.0, green: 0x7A/255.0, blue: 0x00/255.0) // Caution Amber
    public static let info    = Color(red: 0x00/255.0, green: 0x66/255.0, blue: 0xFF/255.0) // Information Blue

    // MARK: - Typography
    /// Display & headlines — Manrope. Never use for body. Always pair with Inter for body.
    public enum Display {
        public static func extraBold(_ size: CGFloat) -> Font { custom("Manrope-ExtraBold", weight: .black, size: size) }
        public static func bold(_ size: CGFloat)      -> Font { custom("Manrope-Bold",      weight: .bold,  size: size) }
        public static func semiBold(_ size: CGFloat)  -> Font { custom("Manrope-SemiBold",  weight: .semibold, size: size) }
        public static func medium(_ size: CGFloat)    -> Font { custom("Manrope-Medium",    weight: .medium, size: size) }
        public static func regular(_ size: CGFloat)   -> Font { custom("Manrope-Regular",   weight: .regular, size: size) }
    }

    /// Body & interface — Inter. Never bold body text — use weight 500 (Medium) or italics for inline emphasis.
    public enum Body {
        public static func regular(_ size: CGFloat) -> Font { custom("Inter-Regular", weight: .regular, size: size) }
        public static func medium(_ size: CGFloat)  -> Font { custom("Inter-Medium",  weight: .medium,  size: size) }
        public static func semiBold(_ size: CGFloat)-> Font { custom("Inter-SemiBold",weight: .semibold,size: size) }
    }

    /// Data, code & labels — JetBrains Mono. Used sparingly. Never for body or headlines longer than three words.
    public enum Mono {
        public static func regular(_ size: CGFloat) -> Font { custom("JetBrainsMono-Regular", weight: .regular, size: size) }
        public static func bold(_ size: CGFloat)    -> Font { custom("JetBrainsMono-Bold",    weight: .bold,    size: size) }
    }

    // MARK: - Type scale (digital, in points)
    public enum Scale {
        public static let heroDisplay:   CGFloat = 56   // Manrope ExtraBold
        public static let display1:      CGFloat = 40
        public static let display2:      CGFloat = 30
        public static let heading1:      CGFloat = 24
        public static let heading2:      CGFloat = 20
        public static let heading3:      CGFloat = 18
        public static let leadParagraph: CGFloat = 18
        public static let body:          CGFloat = 15
        public static let bodySmall:     CGFloat = 13
        public static let eyebrow:       CGFloat = 11   // JetBrains Mono Bold, ALL CAPS, +0.8 tracking
    }

    // MARK: - Boilerplate
    public static let boilerplate = """
    Kinematic is a B2B SaaS field force management platform purpose-built for FMCG companies. \
    We give enterprise teams real-time visibility into thousands of field executives across hundreds of cities — \
    from geo-fenced attendance to consumer contact reporting to incentive-linked performance — \
    in a single, mobile-first system designed for the conditions of actual fieldwork.
    """

    // MARK: - Internals
    /// Resolves the brand font with a system fallback when the bundled face is unavailable.
    /// System fallbacks per the brand guide:
    /// - Manrope → Segoe UI / Helvetica Neue / Roboto / Arial
    /// - Inter → -apple-system / Segoe UI / Roboto / Arial
    /// - JetBrains Mono → SF Mono / Consolas / Menlo / Courier New
    private static func custom(_ name: String, weight: Font.Weight, size: CGFloat) -> Font {
        Font.custom(name, size: size).weight(weight)
    }
}

// MARK: - SwiftUI sugar
public extension View {
    /// Eyebrow label per spec: JetBrains Mono Bold, ALL CAPS, tracking +0.8 px.
    func brandEyebrow() -> some View {
        self.font(Brand.Mono.bold(Brand.Scale.eyebrow))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundColor(Brand.red)
    }
}

// Note: Color convenience accessors (Color.brandRed, Color.brandInk, ...) are intentionally
// not exposed here — `Brand.red`, `Brand.ink`, etc. already read clearly at call sites and
// avoid colliding with any existing Color extensions elsewhere in the app.
