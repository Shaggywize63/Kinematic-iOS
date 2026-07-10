import SwiftUI

/// The KINI robot mascot (matches the website + dashboard): a friendly red
/// robot head with a cream face, antenna, blushing cheeks and a smile. Drawn
/// with a SwiftUI `Canvas` on a 100x100 virtual grid scaled to `size`, so it
/// stays crisp at any size and needs no image asset.
struct KiniMascotView: View {
    var size: CGFloat = 32

    var body: some View {
        Canvas { ctx, sz in
            let red     = Color(red: 0.816, green: 0.118, blue: 0.173)
            let ear     = Color(red: 0.745, green: 0.106, blue: 0.153)
            let cream   = Color(red: 0.961, green: 0.941, blue: 0.918)
            let ink     = Color(red: 0.039, green: 0.055, blue: 0.102)
            let blush   = Color(red: 0.957, green: 0.651, blue: 0.690)
            let speaker = Color(red: 0.690, green: 0.090, blue: 0.133)
            let s = min(sz.width, sz.height) / 100.0
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerRadius: r * s)
            }
            func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (cx - rx) * s, y: (cy - ry) * s, width: rx * 2 * s, height: ry * 2 * s))
            }

            // Antenna
            var stem = Path(); stem.move(to: P(50, 36)); stem.addLine(to: P(50, 21))
            ctx.stroke(stem, with: .color(red), style: StrokeStyle(lineWidth: 3.2 * s, lineCap: .round))
            ctx.fill(oval(50, 14, 8.2, 8.2), with: .color(cream))
            ctx.stroke(oval(50, 14, 8.2, 8.2), with: .color(red), lineWidth: 3 * s)

            // Ears
            ctx.fill(rrect(9, 49, 11, 22, 5.5), with: .color(ear))
            ctx.fill(rrect(80, 49, 11, 22, 5.5), with: .color(ear))

            // Head + face screen
            ctx.fill(rrect(17, 31, 66, 60, 19), with: .color(red))
            ctx.fill(rrect(27, 42, 46, 38, 13), with: .color(cream))

            // Blush
            ctx.fill(oval(35.5, 66, 4.3, 3.1), with: .color(blush))
            ctx.fill(oval(64.5, 66, 4.3, 3.1), with: .color(blush))

            // Eyes (black oval + white glint)
            ctx.fill(oval(42, 57, 5.4, 6.6), with: .color(ink))
            ctx.fill(oval(58, 57, 5.4, 6.6), with: .color(ink))
            ctx.fill(oval(40, 54.6, 1.7, 1.7), with: .color(.white))
            ctx.fill(oval(56, 54.6, 1.7, 1.7), with: .color(.white))

            // Smile
            var smile = Path(); smile.move(to: P(42, 68)); smile.addQuadCurve(to: P(58, 68), control: P(50, 77))
            ctx.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 3.2 * s, lineCap: .round))

            // Speaker slit
            ctx.fill(rrect(41, 84, 18, 3.4, 1.7), with: .color(speaker))
        }
        .frame(width: size, height: size)
    }
}
