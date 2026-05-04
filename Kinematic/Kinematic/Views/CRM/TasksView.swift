import SwiftUI

struct TasksView: View {
    @State private var tasks: [CRMTask] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if isLoading { ProgressView() }
                ForEach(tasks) { t in
                    HStack {
                        Image(systemName: t.status == "done" ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(t.status == "done" ? .green : .gray)
                            .onTapGesture { Task { await complete(t) } }
                        VStack(alignment: .leading) {
                            Text(t.title).font(.system(size: 14, weight: .semibold))
                            if let due = t.dueAt?.prefix(10) {
                                Text("Due \(due)").font(.caption).foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        if let p = t.priority {
                            Text(p.uppercased()).font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(priorityColor(p).opacity(0.15))
                                .foregroundColor(priorityColor(p))
                                .cornerRadius(4)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
                }
            }
            .padding()
        }
        .navigationTitle("Tasks")
        .refreshable { await load() }
        .task { await load() }
    }

    private func priorityColor(_ p: String) -> Color {
        switch p.lowercased() { case "high": return .red; case "medium": return .orange; default: return .blue }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        tasks = (try? await CRMService.shared.listTasks()) ?? []
    }

    private func complete(_ t: CRMTask) async {
        if t.status == "done" { return }
        if let updated = try? await CRMService.shared.completeTask(id: t.id),
           let idx = tasks.firstIndex(where: { $0.id == updated.id }) {
            tasks[idx] = updated
        }
    }
}
