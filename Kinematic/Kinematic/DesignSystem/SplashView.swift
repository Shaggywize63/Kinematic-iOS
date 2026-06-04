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

            VStack(spacing: 18) {
                // Explicit PNG mark per appearance so the black satellite discs
                // never disappear on the dark navy background (the reverse mark
                // is white). Both are PNG assets.
                Image(isDark ? "KinematicMarkReverse" : "KinematicMarkPrimary")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .scaleEffect(appeared ? 1.0 : 0.92)
                    .opacity(appeared ? 1.0 : 0.0)
                    .accessibilityLabel("Kinematic")

                Text("Kinematic")
                    .font(Brand.Display.bold(40))
                    .tracking(-0.5)
                    .foregroundColor(textColor)
                    .opacity(appeared ? 1.0 : 0.0)

                Text("Motion, made measurable.")
                    .font(Brand.Body.regular(15))
                    .foregroundColor(textColor.opacity(0.6))
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
