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

            VStack(spacing: 0) {
                Image("KinematicLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220)
                    .scaleEffect(appeared ? 1.0 : 0.95)
                    .opacity(appeared ? 1.0 : 0.0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { appeared = true }
            }
        }
    }
}

#Preview("Dark")  { SplashView().preferredColorScheme(.dark)  }
#Preview("Light") { SplashView().preferredColorScheme(.light) }
