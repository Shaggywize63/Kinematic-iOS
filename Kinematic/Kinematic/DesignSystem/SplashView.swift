// Brand splash — shown briefly on app launch before routing to login or the main app.
// Background: Deep Navy. Foreground: KinematicMark (reverse) + wordmark in white.

import SwiftUI

public struct SplashView: View {
    @State private var appeared = false

    public init() {}

    public var body: some View {
        ZStack {
            Brand.navy.ignoresSafeArea()

            VStack(spacing: 28) {
                KinematicMark(.reverse, size: 96)
                    .scaleEffect(appeared ? 1.0 : 0.94)
                    .opacity(appeared ? 1.0 : 0.0)

                VStack(spacing: 8) {
                    Text("Kinematic")
                        .font(Brand.Display.extraBold(36))
                        .tracking(-0.5)
                        .foregroundColor(Brand.paper)

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

#Preview {
    SplashView()
}
