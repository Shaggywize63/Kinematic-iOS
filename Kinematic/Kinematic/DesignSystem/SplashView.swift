// Brand splash — shown briefly on app launch before routing to login or the
// main app. Theme-aware: Deep Navy on dark, Paper White on light, with the
// Kinematic mark in the matching PNG variant (coloured on light, white reverse
// on dark) so it's always fully visible. Mirrors the Android BrandSplashScreen.

import SwiftUI

public struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    public init() {}

    public var body: some View {
        let isDark = colorScheme == .dark
        let bg: Color = isDark ? Brand.navy : Brand.paper
        let textColor: Color = isDark ? Brand.paper : Brand.ink

        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 16) {
                // Explicit PNG mark per appearance: the satellite discs are ink
                // on light and white on dark, so the mark is always fully
                // visible (the discs never disappear into the navy background).
                Image(isDark ? "KinematicMarkReverse" : "KinematicMarkPrimary")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 104, height: 104)
                    .scaleEffect(appeared ? 1.0 : 0.92)
                    .opacity(appeared ? 1.0 : 0.0)
                    .accessibilityLabel("Kinematic")

                // Wordmark — Manrope ExtraBold per the brand guidelines.
                Text("Kinematic")
                    .font(Brand.Display.extraBold(40))
                    .tracking(-0.5)
                    .foregroundColor(textColor)
                    .opacity(appeared ? 1.0 : 0.0)

                // Brand signature line, set as a Manrope headline (sentence case,
                // with the period) to match the guideline's treatment.
                Text("Motion, made measurable.")
                    .font(Brand.Display.medium(16))
                    .foregroundColor(textColor.opacity(0.65))
                    .opacity(appeared ? 1.0 : 0.0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            }
        }
    }
}

#Preview("Dark")  { SplashView().preferredColorScheme(.dark)  }
#Preview("Light") { SplashView().preferredColorScheme(.light) }
