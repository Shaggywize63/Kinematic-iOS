import SwiftUI

struct ActivityTimelineItem: View {
    let activity: Activity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 14, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.subject ?? activity.type?.capitalized ?? "Activity")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(uiColor: .label))
                    Spacer()
                    if let when = (activity.completedAt ?? activity.dueAt ?? activity.createdAt)?.prefix(10) {
                        Text(String(when))
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                if let d = activity.description, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var icon: String {
        switch (activity.type ?? "").lowercased() {
        case "call":     return "phone.fill"
        case "email":    return "envelope.fill"
        case "meeting":  return "person.2.fill"
        case "note":     return "note.text"
        case "task":     return "checkmark.square.fill"
        default:         return "circle.fill"
        }
    }

    private var color: Color {
        switch (activity.type ?? "").lowercased() {
        case "call":    return .green
        case "email":   return .blue
        case "meeting": return .orange
        case "note":    return .purple
        case "task":    return .red
        default:        return .gray
        }
    }
}
