import SwiftUI

struct EmailsView: View {
    @StateObject var vm = EmailsViewModel()
    @State private var showCompose = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if vm.emails.isEmpty {
                    Text("No emails sent.").foregroundColor(.gray).padding(.top, 60)
                } else {
                    ForEach(vm.emails) { e in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(e.subject ?? "(no subject)").font(.system(size: 14, weight: .semibold))
                                Spacer()
                                if let s = e.status {
                                    Text(s.uppercased()).font(.system(size: 9, weight: .black))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15)).foregroundColor(.blue).cornerRadius(4)
                                }
                            }
                            if let to = e.toAddress { Text("To: \(to)").font(.caption).foregroundColor(.secondary) }
                            if let body = e.body { Text(body).font(.caption).foregroundColor(.secondary).lineLimit(2) }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Emails")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCompose = true } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $showCompose) {
            EmailComposeView(templates: vm.templates) { to, subject, body, templateId in
                await vm.send(to: to, subject: subject, body: body, templateId: templateId)
            }
        }
        .refreshable { await vm.refresh() }
        .task { await vm.refresh() }
    }
}
