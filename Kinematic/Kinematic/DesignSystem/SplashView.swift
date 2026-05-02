// Brand splash — shown briefly on app launch before routing to login or the main app.
// Theme-aware: Deep Navy on dark, Paper White on light. Mark variant flips to suit.

import SwiftUI

public struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    public init() {}

    public var body: some View {
        let isDark = colorScheme == .dark
        let textColor: Color = isDark ? Brand.paper : Brand.navy

        ZStack {
            (isDark ? Brand.navy : Brand.paper).ignoresSafeArea()

            VStack(spacing: 18) {
                Image("KinematicLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160)
                    .scaleEffect(appeared ? 1.0 : 0.95)
                    .opacity(appeared ? 1.0 : 0.0)

                // Wordmark + tagline. Tracking + weight match the brand
                // wordmark used elsewhere; tone-aware against splash bg.
                VStack(spacing: 6) {
                    Text("KINEMATIC")
                        .font(.system(size: 28, weight: .black, design: .default))
                        .tracking(6)
                        .foregroundColor(textColor)
                        .opacity(appeared ? 1.0 : 0.0)
                        .offset(y: appeared ? 0 : 8)
                    Text("FIELD FORCE, IN MOTION.")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.8)
                        .foregroundColor(textColor.opacity(0.55))
                        .opacity(appeared ? 1.0 : 0.0)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            }
        }
    }
}

#Preview("Dark")  { SplashView().preferredColorScheme(.dark)  }
#Preview("Light") { SplashView().preferredColorScheme(.light) }
