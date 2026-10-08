import SwiftUI

/// Compact bordered "Mark complete" / "Reopen" button shown at the bottom of a
/// CRM activity card. Owns its own in-flight state: while `perform` is running it
/// swaps the icon for a spinner and disables itself, so a double tap can't fire
/// two PATCHes. `perform` is expected to update the host's list itself; if the
/// row is rebuilt (e.g. it moves between sections) the spinner state is simply
/// discarded with the old view.
///
/// It is a real `Button`, so a tap on it is handled here and does not also reach
/// the card's own `.onTapGesture` (tap-to-edit) in the Activities list.
struct ActivityCompletionButton: View {
    let kind: ActivityCompletion.Action
    let perform: () async -> Void

    @State private var busy = false

    var body: some View {
        Button {
            guard !busy else { return }
            busy = true
            Task { @MainActor in
                defer { busy = false }
                await perform()
            }
        } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: kind.systemImage)
                }
                Text(kind.title)
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(tintColor)
        .disabled(busy)
    }

    private var tintColor: Color {
        kind == .markComplete ? Brand.success : Color.secondary
    }
}

extension View {
    /// Error alert for a failed Mark complete / Reopen. Shows the server's own
    /// message (e.g. "you can't edit this activity") and clears it on dismiss.
    func activityCompletionAlert(_ message: Binding<String?>) -> some View {
        alert("Couldn't update activity", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
