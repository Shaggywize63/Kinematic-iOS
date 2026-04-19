import ActivityKit
import SwiftUI
import WidgetKit

// ── Entry point ──────────────────────────────────────────────────────────────
@main
struct KinematicShiftWidgetBundle: WidgetBundle {
    var body: some Widget { ShiftLiveActivityWidget() }
}

struct ShiftLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            // Lock Screen / StandBy banner
            LockScreenView(state: context.state, userName: context.attributes.userName)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long-press)
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(state: context.state, userName: context.attributes.userName)
                }
            } compactLeading: {
                Image(systemName: "clock.fill")
                    .foregroundStyle(context.state.isActive ? .green : .gray)
                    .font(.caption2)
            } compactTrailing: {
                Text(elapsedString(context.state.elapsedSeconds))
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(context.state.isActive ? .white : .gray)
                    .contentTransition(.numericText())
            } minimal: {
                Image(systemName: context.state.isActive ? "clock.badge.checkmark.fill" : "clock.fill")
                    .foregroundStyle(context.state.isActive ? .green : .gray)
                    .font(.caption2)
            }
        }
    }
}

// ── Lock Screen View ─────────────────────────────────────────────────────────
struct LockScreenView: View {
    let state: ShiftActivityAttributes.ContentState
    let userName: String

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Label("Kinematic", systemImage: "briefcase.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                StatusBadge(isActive: state.isActive)
            }

            // Progress ring + time info
            HStack(spacing: 20) {
                // Circular ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: state.progressPercent)
                        .stroke(
                            AngularGradient(
                                colors: [.green, .mint, .green],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text("\(Int(state.progressPercent * 100))%")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("done")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)

                // Time columns
                VStack(alignment: .leading, spacing: 8) {
                    TimeRow(label: "Check-In", date: state.checkinDate, icon: "arrow.right.circle.fill", color: .green)
                    if let out = state.checkoutDate {
                        TimeRow(label: "Check-Out", date: out, icon: "arrow.left.circle.fill", color: .red)
                    } else {
                        TimeRow(label: "Elapsed", value: elapsedString(state.elapsedSeconds), icon: "timer", color: .orange)
                    }
                }

                Spacer()
            }

            // Linear progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 5)
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(state.progressPercent), height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    }
}

// ── Dynamic Island Expanded ───────────────────────────────────────────────────
struct ExpandedLeadingView: View {
    let state: ShiftActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CHECK-IN")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(state.checkinDate, style: .time)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.leading, 4)
    }
}

struct ExpandedTrailingView: View {
    let state: ShiftActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("PROGRESS")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text("\(Int(state.progressPercent * 100))%")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(state.progressPercent >= 1.0 ? .green : .orange)
                .contentTransition(.numericText())
        }
        .padding(.trailing, 4)
    }
}

struct ExpandedBottomView: View {
    let state: ShiftActivityAttributes.ContentState
    let userName: String

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 6)
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(state.progressPercent), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text(userName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(elapsedString(state.elapsedSeconds) + " elapsed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
struct StatusBadge: View {
    let isActive: Bool
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(isActive ? "SHIFT ACTIVE" : "SHIFT ENDED")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isActive ? .green : .secondary)
        }
    }
}

struct TimeRow: View {
    let label: String
    var date: Date? = nil
    var value: String? = nil
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Group {
                    if let d = date {
                        Text(d, style: .time)
                    } else {
                        Text(value ?? "--")
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            }
        }
    }
}

func elapsedString(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    if h > 0 { return String(format: "%dh %02dm", h, m) }
    return String(format: "%dm", m)
}
