// Brand splash — shown briefly on app launch before routing to login or the main app.
// Theme-aware: Deep Navy on dark, Paper White on light. Mark variant flips to suit.

import SwiftUI

public struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    public init() {}

    public var body: some View {
        let isDark = colorScheme == .dark

        ZStack {
            (isDark ? Brand.navy : Brand.paper).ignoresSafeArea()

            VStack(spacing: 28) {
                KinematicMark(isDark ? .reverse : .primary, size: 96)
                    .scaleEffect(appeared ? 1.0 : 0.94)
                    .opacity(appeared ? 1.0 : 0.0)

                VStack(spacing: 8) {
                    Text("Kinematic")
                        .font(Brand.Display.extraBold(36))
                        .tracking(-0.5)
                        .foregroundColor(isDark ? Brand.paper : Brand.ink)

                    Text("FIELD FORCE MANAGEMENT")
                        .font(Brand.Mono.bold(Brand.Scale.eyebrow))
                        .tracking(2.0)
                        .foregroundColor(Brand.red)
                }
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
