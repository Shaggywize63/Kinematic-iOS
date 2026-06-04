import SwiftUI

/// The Kinematic brand mark, rendered with the correct light/dark artwork for
/// the current appearance. There are two source assets — a colour mark for
/// light backgrounds and a reversed (white) mark for dark backgrounds — and
/// relying on asset-catalog luminosity alone proved fragile when the CRM shell
/// is presented in a context whose colorScheme didn't update (e.g. a
/// fullScreenCover). Selecting explicitly off `@Environment(\.colorScheme)`
/// guarantees the mark is always legible.
///
/// Use this everywhere the brand mark appears so light/dark handling stays
/// consistent across the app.
struct KinematicBrandMark: View {
    var size: CGFloat = 36
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(colorScheme == .dark ? "KinematicMarkReverse" : "KinematicMarkPrimary")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Kinematic")
    }
}
