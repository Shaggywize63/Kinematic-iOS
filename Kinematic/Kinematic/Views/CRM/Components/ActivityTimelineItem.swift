import SwiftUI

struct ActivityTimelineItem: View {
    let activity: Activity

    var body: some View {
        let isEmail = (activity.type ?? "").lowercased() == "email"
        let mailto: URL? = isEmail ? mailtoURL() : nil

        let row = HStack(alignment: .top, spacing: 12) {
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
                // Attachment preview — only renders when the activity carries
                // an image_url (e.g. planogram capture). AsyncImage handles
                // the fetch + placeholder lifecycle for us.
                if let url = activity.imageUrl, let parsed = URL(string: url) {
                    AsyncImage(url: parsed) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: 180)
                                .clipped()
                                .cornerRadius(8)
                        case .empty:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 120)
                                .overlay(ProgressView())
                        case .failure:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )

        // Tap-to-mail on email activities — opens the default mail composer
        // with the activity's subject/body pre-filled. Falls back to a plain
        // mailto: when we couldn't parse contact info.
        if let mailto {
            Button(action: { UIApplication.shared.open(mailto) }) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    /// Build a `mailto:` URL with the subject and body URL-encoded. We don't
    /// have the recipient address on the activity row in this model, so we
    /// leave it blank — the mail composer will prompt for one.
    private func mailtoURL() -> URL? {
        let subject = activity.subject ?? ""
        let body = activity.description ?? ""
        let s = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let b = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:?subject=\(s)&body=\(b)")
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
