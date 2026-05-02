// Brand splash — shown briefly on app launch before routing to login or the main app.
// Theme-aware: Deep Navy on dark, Paper White on light. The brand mark is
// drawn as SwiftUI shapes (1 red + 2 ink circles) so it stays pixel-perfect
// at any size and on any device — no raster asset, no scaling artifacts.

import SwiftUI

/// The Kinematic brand mark — three circles arranged exactly as in the
/// brand identity (1 large red top-left, 2 smaller ink circles on the
/// right-top and bottom-right). Renders crisply at any size.
public struct KinematicCircleMark: View {
    public enum Tone {
        case onLight   // ink (dark) circles
        case onDark    // ink (dark) circles look right against light text on dark bg
    }

    private let size: CGFloat
    private let red: Color
    private let dot: Color

    public init(size: CGFloat = 96, red: Color = Brand.red, dot: Color = Brand.ink) {
        self.size = size
        self.red = red
        self.dot = dot
    }

    public var body: some View {
        // Layout is normalized to a 1.0 x 1.0 unit canvas, then scaled.
        // Ratios are taken directly from the brand-mark export.
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            // Big red circle: roughly 0..0.62 horizontally, 0.10..0.72 vertically
            let bigD: CGFloat = 0.62 * s
            let bigRect = CGRect(x: 0.02 * s, y: 0.18 * s, width: bigD, height: bigD)
            context.fill(Path(ellipseIn: bigRect), with: .color(red))

            // Top-right ink dot
            let topD: CGFloat = 0.30 * s
            let topRect = CGRect(x: 0.62 * s, y: 0.10 * s, width: topD, height: topD)
            context.fill(Path(ellipseIn: topRect), with: .color(dot))

            // Bottom-right ink dot (slightly larger, anchored lower-right)
            let botD: CGFloat = 0.34 * s
            let botRect = CGRect(x: 0.62 * s, y: 0.50 * s, width: botD, height: botD)
            context.fill(Path(ellipseIn: botRect), with: .color(dot))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Kinematic")
    }
}

public struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    public init() {}

    public var body: some View {
        let isDark = colorScheme == .dark
        let bg: Color = isDark ? Brand.navy : Brand.paper
        let textColor: Color = isDark ? Brand.paper : Brand.navy
        // On dark navy the ink dots in the mark are too dark — flip them
        // to Paper White so the mark reads against the background.
        let dotColor: Color = isDark ? Brand.paper : Brand.ink

        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 22) {
                KinematicCircleMark(size: 110, red: Brand.red, dot: dotColor)
                    .scaleEffect(appeared ? 1.0 : 0.94)
                    .opacity(appeared ? 1.0 : 0.0)

                VStack(spacing: 8) {
                    // Wordmark — Manrope ExtraBold per brand guidelines.
                    Text("KINEMATIC")
                        .font(Brand.Display.extraBold(28))
                        .tracking(6)
                        .foregroundColor(textColor)
                        .opacity(appeared ? 1.0 : 0.0)
                        .offset(y: appeared ? 0 : 8)

                    // Eyebrow / tagline — JetBrains Mono Bold, ALL CAPS,
                    // tracking +0.8 per the Brand spec.
                    Text("FIELD FORCE, IN MOTION")
                        .font(Brand.Mono.bold(Brand.Scale.eyebrow))
                        .tracking(1.6)
                        .foregroundColor(textColor.opacity(0.55))
                        .opacity(appeared ? 1.0 : 0.0)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            }
        }
    }
}

#Preview("Dark")  { SplashView().preferredColorScheme(.dark)  }
#Preview("Light") { SplashView().preferredColorScheme(.light) }
