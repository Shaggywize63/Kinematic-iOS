import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isUser {
                KiniMascotView(size: 32)
            } else { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 8) {
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(isUser ? .white : Color(uiColor: .label))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? AnyShapeStyle(LinearGradient(colors: [Brand.red, Brand.red], startPoint: .topLeading, endPoint: .bottomTrailing))
                                          : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)))
                    )

                if let cards = message.cards, !cards.isEmpty {
                    ForEach(cards) { c in
                        KiniToolResultCard(card: c)
                    }
                }
            }

            if isUser {
                ZStack {
                    Circle().fill(Brand.red.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Text(Session.currentUser?.name.prefix(1).uppercased() ?? "U")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Brand.red)
                }
            } else { Spacer(minLength: 40) }
        }
    }
}
