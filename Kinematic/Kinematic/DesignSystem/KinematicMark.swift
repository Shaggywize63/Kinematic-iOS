import SwiftUI

public struct KinematicMark: View {
    public enum Variant {
        case primary   // dark/colored mark — for light surfaces
        case reverse   // white mark — for dark surfaces
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
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: size * 1.6, maxHeight: size)
            .accessibilityLabel("Kinematic")
    }

    private var assetName: String {
        switch variant {
        case .primary:   return "KinematicMarkPrimary"
        case .reverse:   return "KinematicMarkReverse"
        case .monoBlack: return "KinematicMarkMonoBlack"
        case .monoWhite: return "KinematicMarkMonoWhite"
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
