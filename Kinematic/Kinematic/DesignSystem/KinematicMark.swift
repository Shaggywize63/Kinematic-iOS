// Kinematic Mark — see BRAND.md
// The kinematic chain: one red disc anchored, two satellite discs in coordinated orbit.
//
// Geometry mirrors the brand favicon (which is the source of truth for the mark):
//   <circle cx="36" cy="50" r="24" fill="#D01E2C"/>
//   <circle cx="66" cy="36" r="12" fill="#0A0E1A"/>
//   <circle cx="66" cy="64" r="12" fill="#0A0E1A"/>
// In primary-disc-diameter (D) units:
//   primary  : centred at (0.50D, 0.50D), radius 0.50D
//   sat top  : centred at (1.125D, 0.208D), radius 0.25D
//   sat bot  : centred at (1.125D, 0.792D), radius 0.25D
// This produces three clearly-separated discs with the satellite pair sitting
// just past the primary's right edge per the brand spec.

import SwiftUI

public struct KinematicMark: View {
    public enum Variant {
        case primary   // Red anchor + Ink satellites — default for light surfaces
        case reverse   // Red anchor + White satellites — for dark surfaces and Deep Navy
        case monoBlack // All ink — single-colour print
        case monoWhite // All white — photographic backgrounds, hero
    }

    private let variant: Variant
    private let size: CGFloat

    public init(_ variant: Variant = .primary, size: CGFloat = 96) {
        self.variant = variant
        self.size = size
    }

    public var body: some View {
        // `size` is the diameter of the primary disc.
        let D: CGFloat = size
        let primaryD: CGFloat   = D
        let satelliteD: CGFloat = D * 0.50              // 24/48 — favicon ratio

        let satelliteCenterX: CGFloat    = D * 1.125    // 66/48 — favicon offset
        let satelliteCenterYTop: CGFloat = D * 0.208    // 36/(2*48*0.5) — favicon offset
        let satelliteCenterYBot: CGFloat = D * 0.792    // 64/...

        let canvasW: CGFloat = satelliteCenterX + satelliteD / 2  // ~1.375 D
        let canvasH: CGFloat = max(primaryD, satelliteCenterYBot + satelliteD / 2) // ~1.042 D

        ZStack(alignment: .topLeading) {
            // Primary disc — red anchor
            Circle()
                .fill(primaryColor)
                .frame(width: primaryD, height: primaryD)
                .position(x: primaryD / 2, y: primaryD / 2)

            // Upper satellite
            Circle()
                .fill(satelliteColor)
                .frame(width: satelliteD, height: satelliteD)
                .position(x: satelliteCenterX, y: satelliteCenterYTop)

            // Lower satellite
            Circle()
                .fill(satelliteColor)
                .frame(width: satelliteD, height: satelliteD)
                .position(x: satelliteCenterX, y: satelliteCenterYBot)
        }
        .frame(width: canvasW, height: canvasH)
        .accessibilityLabel("Kinematic")
    }

    private var primaryColor: Color {
        switch variant {
        case .primary, .reverse: return Brand.red
        case .monoBlack:         return Brand.ink
        case .monoWhite:         return .white
        }
    }

    private var satelliteColor: Color {
        switch variant {
        case .primary:    return Brand.ink
        case .reverse:    return .white
        case .monoBlack:  return Brand.ink
        case .monoWhite:  return .white
        }
    }
}

/// Full lockup: mark + Manrope ExtraBold wordmark.
public struct KinematicLockup: View {
    public enum Tone { case onLight, onDark }
    private let tone: Tone
    private let markSize: CGFloat

    public init(tone: Tone = .onLight, markSize: CGFloat = 64) {
        self.tone = tone
        self.markSize = markSize
    }

    public var body: some View {
        HStack(spacing: markSize * 0.35) {
            KinematicMark(tone == .onDark ? .reverse : .primary, size: markSize)
            Text("Kinematic")
                .font(Brand.Display.extraBold(markSize * 0.78))
                .tracking(-0.5)
                .foregroundColor(tone == .onDark ? Brand.paper : Brand.ink)
        }
    }
}
