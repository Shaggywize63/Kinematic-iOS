import SwiftUI

/// Reusable green WhatsApp pill that opens wa.me/<phone>?text=<msg>
/// in WhatsApp Web or the native app.
struct WhatsAppButton: View {
    let phone: String?
    let prefillText: String?
    var compact: Bool = true

    var body: some View {
        if let phone, WhatsAppHelper.canOpen(phone: phone) {
            Button {
                _ = WhatsAppHelper.open(phone: phone, text: prefillText)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "message.fill")
                        .font(.system(size: compact ? 11 : 13, weight: .bold))
                    Text("WhatsApp")
                        .font(.system(size: compact ? 11 : 13, weight: .bold))
                }
                .padding(.horizontal, compact ? 9 : 12)
                .padding(.vertical, compact ? 4 : 7)
                .foregroundColor(.white)
                .background(Color(red: 0.145, green: 0.827, blue: 0.4))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
    }
}
