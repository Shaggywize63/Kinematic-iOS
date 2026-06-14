import SwiftUI

/// Header chip that shows how many CRM mutations are queued locally
/// (offline / weak signal). Hidden when the queue is empty. Tapping
/// kicks the drain manually so reps don't have to wait for the next
/// network path callback.
struct PendingSyncChip: View {
    @ObservedObject private var queue = OfflineMutationQueue.shared

    var body: some View {
        if queue.pendingCount > 0 {
            Button {
                queue.drain()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(queue.pendingCount) pending")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color(red: 1.0, green: 0.95, blue: 0.80))
                )
                .foregroundColor(Color(red: 0.47, green: 0.35, blue: 0.0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(queue.pendingCount) CRM updates pending sync — tap to retry")
        }
    }
}
