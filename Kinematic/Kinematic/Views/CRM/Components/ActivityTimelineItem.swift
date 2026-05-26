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
                // Photo attached to the activity. AsyncImage handles its
                // own loading + placeholder. Tap to open full-size in
                // the system browser via Link (the URL is already public
                // — uploads go through the same storage bucket the web
                // version uses).
                if let urlString = activity.imageUrl,
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: 220, maxHeight: 160)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: 220, maxHeight: 160)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            case .failure:
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                    .frame(width: 220, height: 160)
                                    .background(Color(uiColor: .tertiarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
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
        case "call":    return Brand.red
        case "email":   return Brand.red
        case "meeting": return Brand.red
        case "note":    return Brand.red
        case "task":    return .red
        default:        return .gray
        }
    }
}
