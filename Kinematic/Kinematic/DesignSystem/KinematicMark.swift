import SwiftUI

public struct KinematicMark: View {
    public enum Variant {
        case primary   // light surfaces
        case reverse   // dark surfaces
        case monoBlack
        case monoWhite
    }

    private let variant: Variant
    private let size: CGFloat

    public init(_ variant: Variant = .primary, size: CGFloat = 96) {
        self.variant = variant
        self.size = size
    }

    public var body: some View {
        // Asset catalog "KinematicMark" has dark/light appearance slots.
        // Drop logo-light.png and logo-dark.png into the imageset folder;
        // iOS picks the right one automatically based on color scheme.
        Image("KinematicMark")
            .resizable()
            .scaledToFit()
            .frame(height: size)
            .accessibilityLabel("Kinematic")
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
