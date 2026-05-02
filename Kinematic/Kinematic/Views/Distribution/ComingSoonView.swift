import SwiftUI

/// Placeholder shown for distribution modules that ship in a later milestone
/// (Payments, Returns, Distributor Stock, Secondary Sales). The route is
/// already wired so the launcher chip stays in place; the view fills in M2/M3.
struct ComingSoonView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox").font(.system(size: 44)).foregroundColor(.secondary)
            Text("Coming soon").font(.title3).bold()
            Text("This part of the Distribution module ships in the next milestone.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
