import SwiftUI

/// Official WhatsApp brand mark — speech bubble with the phone handset
/// carved out. Same path data as the dashboard's WhatsAppLogo.tsx and
/// the Android WhatsAppLogo composable so the glyph looks identical
/// across all three platforms.
///
/// Uses `.evenOdd` fill rule: the path is a compound shape (outer
/// bubble + handset cutout). Without `.evenOdd` the cutout fills
/// solid and the mark renders as a vaguely heart-shaped green blob —
/// the original "green heart" bug users have flagged multiple times.
struct WhatsAppLogo: View {
    var size: CGFloat = 18
    var color: Color = Color(red: 0.145, green: 0.827, blue: 0.4) // #25D366

    var body: some View {
        Canvas { ctx, canvasSize in
            // Source path is authored against a 24×24 viewBox. Scale the
            // GraphicsContext (instead of transforming the Path) so we
            // get a real `Path` back to hand to ctx.fill — Shape.transform
            // returns a TransformedShape which fill won't accept.
            let s = canvasSize.width / 24.0
            ctx.scaleBy(x: s, y: s)
            ctx.fill(Self.cachedPath, with: .color(color), style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("WhatsApp")
    }

    private static let cachedPath: Path = {
        // Compound shape — outer bubble + handset cutout. EvenOdd fill
        // is what carves the handset out of the bubble.
        var p = Path()
        p.move(to: CGPoint(x: 17.472, y: 14.382))
        p.addCurve(to: CGPoint(x: 15.442, y: 13.415),
                   control1: CGPoint(x: 17.175, y: 14.233),
                   control2: CGPoint(x: 15.714, y: 13.515))
        p.addCurve(to: CGPoint(x: 14.772, y: 13.565),
                   control1: CGPoint(x: 15.169, y: 13.316),
                   control2: CGPoint(x: 14.971, y: 13.267))
        p.addCurve(to: CGPoint(x: 13.832, y: 14.729),
                   control1: CGPoint(x: 14.575, y: 13.862),
                   control2: CGPoint(x: 14.005, y: 14.531))
        p.addCurve(to: CGPoint(x: 13.188, y: 14.804),
                   control1: CGPoint(x: 13.659, y: 14.928),
                   control2: CGPoint(x: 13.485, y: 14.952))
        p.addCurve(to: CGPoint(x: 10.798, y: 13.329),
                   control1: CGPoint(x: 12.891, y: 14.654),
                   control2: CGPoint(x: 11.933, y: 14.341))
        p.addCurve(to: CGPoint(x: 9.145, y: 11.270),
                   control1: CGPoint(x: 9.915, y: 12.541),
                   control2: CGPoint(x: 9.318, y: 11.568))
        p.addCurve(to: CGPoint(x: 9.275, y: 10.664),
                   control1: CGPoint(x: 8.972, y: 10.973),
                   control2: CGPoint(x: 9.127, y: 10.812))
        p.addCurve(to: CGPoint(x: 9.721, y: 10.144),
                   control1: CGPoint(x: 9.409, y: 10.531),
                   control2: CGPoint(x: 9.573, y: 10.317))
        p.addCurve(to: CGPoint(x: 10.019, y: 9.647),
                   control1: CGPoint(x: 9.870, y: 9.970),
                   control2: CGPoint(x: 9.919, y: 9.846))
        p.addCurve(to: CGPoint(x: 9.994, y: 9.127),
                   control1: CGPoint(x: 10.118, y: 9.449),
                   control2: CGPoint(x: 10.069, y: 9.276))
        p.addCurve(to: CGPoint(x: 9.078, y: 6.920),
                   control1: CGPoint(x: 9.919, y: 8.978),
                   control2: CGPoint(x: 9.325, y: 7.515))
        p.addCurve(to: CGPoint(x: 8.409, y: 6.410),
                   control1: CGPoint(x: 8.836, y: 6.341),
                   control2: CGPoint(x: 8.591, y: 6.420))
        p.addCurve(to: CGPoint(x: 7.839, y: 6.400),
                   control1: CGPoint(x: 8.236, y: 6.402),
                   control2: CGPoint(x: 8.038, y: 6.400))
        p.addCurve(to: CGPoint(x: 7.047, y: 6.772),
                   control1: CGPoint(x: 7.641, y: 6.400),
                   control2: CGPoint(x: 7.319, y: 6.474))
        p.addCurve(to: CGPoint(x: 6.007, y: 9.251),
                   control1: CGPoint(x: 6.775, y: 7.069),
                   control2: CGPoint(x: 6.007, y: 7.788))
        p.addCurve(to: CGPoint(x: 7.220, y: 12.325),
                   control1: CGPoint(x: 6.007, y: 10.713),
                   control2: CGPoint(x: 7.072, y: 12.126))
        p.addCurve(to: CGPoint(x: 12.297, y: 16.812),
                   control1: CGPoint(x: 7.369, y: 12.523),
                   control2: CGPoint(x: 9.316, y: 15.525))
        p.addCurve(to: CGPoint(x: 13.991, y: 17.437),
                   control1: CGPoint(x: 13.006, y: 17.118),
                   control2: CGPoint(x: 13.559, y: 17.301))
        p.addCurve(to: CGPoint(x: 15.862, y: 17.555),
                   control1: CGPoint(x: 14.703, y: 17.664),
                   control2: CGPoint(x: 15.351, y: 17.632))
        p.addCurve(to: CGPoint(x: 17.868, y: 16.142),
                   control1: CGPoint(x: 16.433, y: 17.470),
                   control2: CGPoint(x: 17.620, y: 16.836))
        p.addCurve(to: CGPoint(x: 18.041, y: 14.729),
                   control1: CGPoint(x: 18.116, y: 15.448),
                   control2: CGPoint(x: 18.116, y: 14.853))
        p.addCurve(to: CGPoint(x: 17.472, y: 14.382),
                   control1: CGPoint(x: 17.967, y: 14.605),
                   control2: CGPoint(x: 17.770, y: 14.531))
        p.closeSubpath()

        // Outer bubble (the silhouette).
        p.move(to: CGPoint(x: 12.051, y: 21.785))
        p.addLine(to: CGPoint(x: 12.047, y: 21.785))
        p.addCurve(to: CGPoint(x: 7.016, y: 20.407),
                   control1: CGPoint(x: 10.272, y: 21.784),
                   control2: CGPoint(x: 8.531, y: 21.307))
        p.addLine(to: CGPoint(x: 6.655, y: 20.193))
        p.addLine(to: CGPoint(x: 2.914, y: 21.175))
        p.addLine(to: CGPoint(x: 3.912, y: 17.527))
        p.addLine(to: CGPoint(x: 3.677, y: 17.153))
        p.addCurve(to: CGPoint(x: 2.167, y: 11.893),
                   control1: CGPoint(x: 2.701, y: 15.603),
                   control2: CGPoint(x: 2.167, y: 13.788))
        p.addCurve(to: CGPoint(x: 12.055, y: 2.009),
                   control1: CGPoint(x: 2.168, y: 6.443),
                   control2: CGPoint(x: 6.603, y: 2.009))
        p.addCurve(to: CGPoint(x: 19.043, y: 4.907),
                   control1: CGPoint(x: 14.695, y: 2.009),
                   control2: CGPoint(x: 17.177, y: 3.039))
        p.addCurve(to: CGPoint(x: 21.936, y: 11.901),
                   control1: CGPoint(x: 20.911, y: 6.775),
                   control2: CGPoint(x: 21.939, y: 9.261))
        p.addCurve(to: CGPoint(x: 12.051, y: 21.785),
                   control1: CGPoint(x: 21.933, y: 17.351),
                   control2: CGPoint(x: 17.499, y: 21.785))
        p.closeSubpath()

        p.move(to: CGPoint(x: 20.464, y: 3.488))
        p.addCurve(to: CGPoint(x: 12.050, y: 0.0),
                   control1: CGPoint(x: 18.247, y: 1.247),
                   control2: CGPoint(x: 15.241, y: 0.0))
        p.addCurve(to: CGPoint(x: 0.157, y: 11.892),
                   control1: CGPoint(x: 5.495, y: 0.0),
                   control2: CGPoint(x: 0.160, y: 5.335))
        p.addCurve(to: CGPoint(x: 1.745, y: 17.837),
                   control1: CGPoint(x: 0.157, y: 13.988),
                   control2: CGPoint(x: 0.704, y: 16.034))
        p.addLine(to: CGPoint(x: 0.057, y: 24.0))
        p.addLine(to: CGPoint(x: 6.362, y: 22.346))
        p.addCurve(to: CGPoint(x: 12.045, y: 23.794),
                   control1: CGPoint(x: 8.094, y: 23.291),
                   control2: CGPoint(x: 10.045, y: 23.794))
        p.addLine(to: CGPoint(x: 12.050, y: 23.794))
        p.addCurve(to: CGPoint(x: 23.943, y: 11.901),
                   control1: CGPoint(x: 18.604, y: 23.794),
                   control2: CGPoint(x: 23.940, y: 18.459))
        p.addCurve(to: CGPoint(x: 20.464, y: 3.488),
                   control1: CGPoint(x: 23.946, y: 9.155),
                   control2: CGPoint(x: 22.681, y: 5.728))
        p.closeSubpath()
        return p
    }()
}
