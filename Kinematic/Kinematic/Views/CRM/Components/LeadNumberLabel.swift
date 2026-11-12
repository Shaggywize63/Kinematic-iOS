import SwiftUI
import UIKit

/// Spark & Ray lead number (`ref_no`, e.g. "SR/LD/2627-12") in small monospaced text. The caller
/// decides whether to show it (Spark only, and only when the lead has one — see
/// `LeadNumberAndType.refDisplay`). With `copyable` it also carries a "Copy" button that puts the
/// number on the pasteboard.
struct LeadNumberLabel: View {
    let ref: String
    var copyable: Bool = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(ref)
                .font(.system(size: copyable ? 13 : 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .accessibilityLabel("Lead number \(ref)")
            if copyable {
                Button {
                    UIPasteboard.general.string = ref
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .tint(Brand.red)
                .accessibilityLabel("Copy lead number")
            }
        }
    }
}
