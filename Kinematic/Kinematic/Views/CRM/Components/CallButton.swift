import SwiftUI
import UIKit

/// Reusable blue Call pill. Opens the system dialer via tel: URL and, in
/// the same gesture, surfaces a prefilled "Log Activity" sheet so the rep
/// captures the call without leaving CRM context.
///
/// The dialer launches immediately on tap (so iOS doesn't lose the gesture
/// to the sheet animation); the composer comes up underneath and is ready
/// for notes when the user returns from the call.
struct CallButton: View {
    let phone: String?
    /// Subject the composer pre-fills with — e.g. "Call with Jane Doe".
    let prefillSubject: String
    /// Invoked after `tel:` is dispatched. Parent should present the
    /// composer sheet with `initialType="call"`, `initialSubject=prefillSubject`.
    let onCallInitiated: () -> Void
    var compact: Bool = true

    @State private var placingIvr = false
    @State private var ivrMessage: String?

    var body: some View {
        if let normalized = CallHelper.normalize(phone) {
            HStack(spacing: 6) {
                pill(title: "Call", system: "phone.fill", color: Color(red: 0.10, green: 0.55, blue: 0.95)) {
                    CallHelper.dial(normalized: normalized)
                    onCallInitiated()
                }
                // IVR Call — a recorded server-side click-to-call (CallerDesk): the
                // agent's phone rings first, then the customer. Shown only when the
                // client holds the `ivr_call` module (strict gate in ClientFeatures).
                if ClientFeatures.hasIvrCall {
                    pill(title: "IVR", system: "phone.arrow.up.right.fill", color: Color(red: 0.04, green: 0.54, blue: 0.31), disabled: placingIvr) {
                        placeIvrCall(to: normalized)
                    }
                }
            }
            .alert("IVR Call", isPresented: Binding(get: { ivrMessage != nil }, set: { if !$0 { ivrMessage = nil } })) {
                Button("OK", role: .cancel) { ivrMessage = nil }
            } message: { Text(ivrMessage ?? "") }
        }
    }

    private func pill(title: String, system: String, color: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: system).font(.system(size: compact ? 11 : 13, weight: .bold))
                Text(title).font(.system(size: compact ? 11 : 13, weight: .bold))
            }
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 4 : 7)
            .foregroundColor(.white)
            .background(color.opacity(disabled ? 0.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func placeIvrCall(to: String) {
        guard !placingIvr else { return }
        placingIvr = true
        Task {
            let message: String
            do {
                _ = try await CRMService.shared.placeIvrCall(to: to)
                message = "Your phone will ring first, then the customer."
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "Could not place the call."
            }
            await MainActor.run {
                placingIvr = false
                ivrMessage = message
            }
        }
    }
}

/// Minimal decode of the click-to-call ack (`{ ok, provider, call_id, status }`).
struct IvrCallAck: Codable {
    let ok: Bool?
    let provider: String?
    let status: String?
}

/// Phone formatting + dialing. Kept as a helper so tests / other views can
/// reuse the normalization without dragging the button view in.
enum CallHelper {
    /// Strip whitespace, dashes, and parens. Keep the leading '+' and digits.
    /// Returns nil if the input has no digits at all so the button can
    /// hide itself for blank/garbage phone fields.
    static func normalize(_ phone: String?) -> String? {
        guard let raw = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        var out = ""
        for (i, ch) in raw.enumerated() {
            if i == 0 && ch == "+" { out.append(ch); continue }
            if ch.isNumber { out.append(ch) }
        }
        // Need at least 4 digits to be a plausible number.
        let digitCount = out.filter(\.isNumber).count
        return digitCount >= 4 ? out : nil
    }

    static func dial(normalized: String) {
        guard let url = URL(string: "tel:\(normalized)") else { return }
        // Arm the CallKit observer *before* we hand off to the system
        // dialer so it catches the connect event that follows.
        CallObserver.shared.startTracking()
        UIApplication.shared.open(url)
    }
}
