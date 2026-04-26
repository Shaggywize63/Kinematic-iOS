// Kinematic Mark — see BRAND.md
// The kinematic chain: one red disc anchored, two satellite discs in coordinated orbit.
//
// Geometry: an invisible 6×6 grid; primary disc 4 units, satellites 2.4 units.
// The satellite pair sits to the right of the primary so the discs read as
// three distinct bodies (no overlap into the primary, no overlap with each
// other) rather than a melted blob.

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
        let primaryD: CGFloat   = size
        let satelliteD: CGFloat = size * 0.55             // 2.4 / ~4.4 — a touch smaller for cleaner separation

        // Satellite centre sits just outside the primary's right edge so the
        // inner edge of each satellite tangents (no overlap into the red disc).
        let satelliteCenterX: CGFloat = primaryD + satelliteD * 0.10
        let satelliteCenterYTop: CGFloat = primaryD * 0.18
        let satelliteCenterYBot: CGFloat = primaryD * 0.82

        // Canvas extends to fully contain both satellites.
        let canvasW: CGFloat = satelliteCenterX + satelliteD / 2
        let canvasH: CGFloat = satelliteCenterYBot + satelliteD / 2

        ZStack(alignment: .topLeading) {
            // Primary disc — anchored at the centre of the primary's height.
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
