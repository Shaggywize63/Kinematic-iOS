// Brand splash — shown briefly on app launch before routing to login or the main app.
// Theme-aware: Deep Navy on dark, Paper White on light. Uses the real
// `KinematicLogo` asset (light/dark variants) instead of a hand-drawn
// Canvas approximation — the canvas version didn't match the brand mark
// the user actually wanted on the splash.

import SwiftUI

public struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    public init() {}

    public var body: some View {
        let isDark = colorScheme == .dark
        let bg: Color = isDark ? Brand.navy : Brand.paper
        let textColor: Color = isDark ? Brand.paper : Brand.navy

        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 22) {
                // Real brand logo from the asset catalogue (KinematicLogo
                // ships separate light + dark variants — SwiftUI's Image
                // picks the right one automatically via the appearance
                // metadata in Contents.json).
                Image("KinematicLogo")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 110)
                    .scaleEffect(appeared ? 1.0 : 0.94)
                    .opacity(appeared ? 1.0 : 0.0)
                    .accessibilityLabel("Kinematic")

                Text("FIELD FORCE, IN MOTION")
                    .font(Brand.Mono.bold(Brand.Scale.eyebrow))
                    .tracking(1.6)
                    .foregroundColor(textColor.opacity(0.55))
                    .opacity(appeared ? 1.0 : 0.0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            }
        }
    }
}

#Preview("Dark")  { SplashView().preferredColorScheme(.dark)  }
#Preview("Light") { SplashView().preferredColorScheme(.light) }
