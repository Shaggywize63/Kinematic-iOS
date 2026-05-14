import SwiftUI

private let brandRed = Color(red: 0xE0/255, green: 0x1E/255, blue: 0x2C/255)
private let brandRedLight = Color(red: 0xFF/255, green: 0x4D/255, blue: 0x4D/255)
private let fabGradient = LinearGradient(
    colors: [brandRed, brandRedLight],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// The persistent KINI launcher — a red gradient circular button anchored
/// to the bottom-right of every screen (except the chat itself). Mirrors
/// the web `KinematicAI` FAB. Tapping opens KiniChatView as a fullScreenCover.
///
/// Surfaces a small `used/cap` credits chip in the top-right corner so the
/// user always sees their monthly KINI quota at a glance, even without
/// opening the chat. The chip hides for `exempt` callers (super-admin).
struct KiniFAB: View {
    let usage: KiniUsage?
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(fabGradient)
                        .frame(width: 56, height: 56)
                        .shadow(color: brandRed.opacity(0.45), radius: 14, x: 0, y: 8)
                    Text("✦")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask KINI")

            if let u = usage, !u.exempt {
                Text("\(u.used)/\(u.cap)")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(u.remaining == 0 ? .white : brandRed)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(u.remaining == 0 ? Color(white: 0.1) : Color.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .offset(x: 6, y: -4)
            }
        }
        .frame(width: 72, height: 72, alignment: .bottomTrailing)
    }
}
