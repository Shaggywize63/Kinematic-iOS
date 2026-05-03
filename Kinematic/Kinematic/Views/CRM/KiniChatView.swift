import SwiftUI

struct KiniChatView: View {
    @StateObject var vm = KINIChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.messages) { m in
                            ChatBubble(message: m).id(m.id)
                        }
                        if vm.isSending {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("KINI is thinking…")
                                    .font(.caption).foregroundColor(.gray)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .onChange(of: vm.messages.count) { _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask KINI anything…", text: $vm.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)

                Button {
                    Task { await vm.send() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                        Image(systemName: "arrow.up")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .black))
                    }
                }
                .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSending)
                .opacity(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding()
        }
        .navigationTitle("KINI")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}
