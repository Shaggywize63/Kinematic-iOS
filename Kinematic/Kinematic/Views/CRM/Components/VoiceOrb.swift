import SwiftUI

// Brand palette (file-local so this shared component is self-contained).
private let voiceOrbRed = Color(red: 0xE0/255, green: 0x1E/255, blue: 0x2C/255)
private let voiceOrbRedLight = Color(red: 0xFF/255, green: 0x4D/255, blue: 0x4D/255)
private let voiceOrbBlue = Color(red: 0x1E/255, green: 0x3A/255, blue: 0x8A/255)

/// Amplitude-reactive voice orb — a radial-gradient core (KINI's mascot at its
/// centre) that scales and glows with a live 0…1 microphone amplitude
/// (`KiniVoiceRecognizer.level`), wrapped in concentric rings that expand with
/// it. Breathes gently at idle. Shared by the voice surfaces (currently the
/// lead-form "Fill with voice" panel); the KINI chat has its own private copy.
struct VoiceInputOrb: View {
    var level: CGFloat        // 0…1 live mic amplitude
    var active: Bool
    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let core = side * 0.5
            let amp = max(0, min(1, level))
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(voiceOrbRed.opacity(0.22 - Double(i) * 0.06), lineWidth: 2)
                        .frame(width: core + CGFloat(i) * side * 0.14 + (active ? amp * side * 0.35 : 0),
                               height: core + CGFloat(i) * side * 0.14 + (active ? amp * side * 0.35 : 0))
                        .scaleEffect(breathe ? 1.04 : 0.96)
                        .animation(.easeInOut(duration: 2.4 + Double(i) * 0.4).repeatForever(autoreverses: true), value: breathe)
                }

                Circle()
                    .fill(RadialGradient(colors: [voiceOrbRedLight, voiceOrbRed, voiceOrbBlue], center: .center, startRadius: 2, endRadius: core * 0.75))
                    .frame(width: core, height: core)
                    .scaleEffect(1 + (active ? amp * 0.30 : 0) + (breathe ? 0.02 : -0.02))
                    .shadow(color: voiceOrbRed.opacity(0.5), radius: 20 + (active ? amp * 26 : 6))
                    .overlay(
                        Circle().fill(Color.white.opacity(0.18))
                            .frame(width: core * 0.42, height: core * 0.42)
                            .offset(x: -core * 0.12, y: -core * 0.14)
                            .blur(radius: 6)
                    )

                KiniMascotView(size: core * 0.46)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeOut(duration: 0.12), value: level)
        }
        .onAppear { breathe = true }
        .accessibilityHidden(true)
    }
}
