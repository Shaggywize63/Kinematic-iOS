// Kinematic Mark — see BRAND.md
// The kinematic chain: one red disc anchored, two satellite discs in coordinated orbit.
// Geometry per spec: an invisible 6×6 grid; primary disc 4 units, satellites 2.4 units;
// optical centre of the satellite pair sits on the right edge of the primary.

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
        let primaryD: CGFloat = size
        let satelliteD: CGFloat = size * 0.6
        let canvasW: CGFloat = primaryD + satelliteD * 1.25
        let canvasH: CGFloat = primaryD

        ZStack(alignment: .topLeading) {
            Circle()
                .fill(primaryColor)
                .frame(width: primaryD, height: primaryD)
                .position(x: primaryD / 2, y: canvasH / 2)

            Circle()
                .fill(satelliteColor)
                .frame(width: satelliteD, height: satelliteD)
                .position(x: primaryD, y: canvasH * 0.34)

            Circle()
                .fill(satelliteColor)
                .frame(width: satelliteD, height: satelliteD)
                .position(x: primaryD, y: canvasH * 0.66)
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
