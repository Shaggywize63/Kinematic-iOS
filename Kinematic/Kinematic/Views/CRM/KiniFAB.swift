import SwiftUI

private let brandRed = Color(red: 0xE0/255, green: 0x1E/255, blue: 0x2C/255)

/// The persistent KINI launcher — a white circular button showing the KINI
/// mascot that **the user can drag anywhere on screen**. Position is persisted in
/// UserDefaults so dragging stays put across screen / tab changes.
///
/// Tapping opens KiniChatView as a fullScreenCover. The `used/cap` credits
/// chip overlays the top-right corner of the FAB; hidden for `exempt`
/// callers (super-admin).
struct KiniFAB: View {
    let usage: KiniUsage?
    let onTap: () -> Void

    // Persist drag offset across screen changes so the FAB doesn't snap
    // back to the bottom-right corner every time the user navigates.
    @AppStorage("kini_fab_offset_x") private var savedOffsetX: Double = 0
    @AppStorage("kini_fab_offset_y") private var savedOffsetY: Double = 0
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        let totalOffset = CGSize(
            width: savedOffsetX + dragOffset.width,
            height: savedOffsetY + dragOffset.height
        )

        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 56, height: 56)
                    .shadow(color: brandRed.opacity(0.45), radius: 14, x: 0, y: 8)
                // KINI mascot on a white disc so the red robot reads on any
                // background. Replaces the old generic ✦ glyph.
                Image("KiniMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
            }
            .accessibilityLabel("Ask KINI")
            .onTapGesture(perform: onTap)

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
        .offset(totalOffset)
        .gesture(
            DragGesture()
                .onChanged { v in dragOffset = v.translation }
                .onEnded { _ in
                    savedOffsetX += dragOffset.width
                    savedOffsetY += dragOffset.height
                    dragOffset = .zero
                }
        )
    }
}
