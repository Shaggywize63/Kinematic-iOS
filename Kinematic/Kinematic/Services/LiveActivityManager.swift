import ActivityKit
import Foundation

/// Manages the iOS Live Activity (Dynamic Island + Lock Screen) for an active shift.
@MainActor
class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var activity: Activity<ShiftActivityAttributes>?
    private var updateTask: Task<Void, Never>?

    // MARK: - Public API

    func startActivity(userName: String, checkinDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("LiveActivity: Activities disabled on this device.")
            return
        }
        Task { await _start(userName: userName, checkinDate: checkinDate) }
    }

    func endActivity(checkinDate: Date, checkoutDate: Date) {
        Task { await _end(checkinDate: checkinDate, checkoutDate: checkoutDate) }
    }

    // MARK: - Private

    private func _start(userName: String, checkinDate: Date) async {
        // End any stale activity first
        for existing in Activity<ShiftActivityAttributes>.activities {
            await existing.end(.init(state: existing.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }

        let attributes = ShiftActivityAttributes(userName: userName, targetHours: 8)
        let state = makeState(checkinDate: checkinDate, checkoutDate: nil)

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            print("LiveActivity: Started – \(activity?.id ?? "?")")
            schedulePeriodicUpdates(checkinDate: checkinDate)
        } catch {
            print("LiveActivity: Failed to start – \(error.localizedDescription)")
        }
    }

    private func _end(checkinDate: Date, checkoutDate: Date) async {
        updateTask?.cancel()
        updateTask = nil

        let finalState = makeState(checkinDate: checkinDate, checkoutDate: checkoutDate)
        // Keep the ended activity visible on lock screen for 1 hour
        await activity?.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 3600))
        activity = nil
        print("LiveActivity: Ended.")
    }

    private func schedulePeriodicUpdates(checkinDate: Date) {
        updateTask?.cancel()
        updateTask = Task {
            // Update every 60 s so the progress bar stays fresh
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let activity else { break }
                let state = makeState(checkinDate: checkinDate, checkoutDate: nil)
                await activity.update(.init(state: state, staleDate: nil))
            }
        }
    }

    private func makeState(checkinDate: Date, checkoutDate: Date?) -> ShiftActivityAttributes.ContentState {
        let end = checkoutDate ?? Date()
        let elapsed = max(0, Int(end.timeIntervalSince(checkinDate)))
        let progress = min(Double(elapsed) / Double(8 * 3600), 1.0)
        return ShiftActivityAttributes.ContentState(
            checkinDate: checkinDate,
            checkoutDate: checkoutDate,
            progressPercent: progress,
            elapsedSeconds: elapsed,
            isActive: checkoutDate == nil
        )
    }
}
