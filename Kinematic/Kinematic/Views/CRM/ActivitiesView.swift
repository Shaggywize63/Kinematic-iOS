import SwiftUI

struct ActivitiesView: View {
    @StateObject var vm = ActivitiesViewModel()
    @State private var showCompose = false
    let typeOptions = ["all", "call", "email", "meeting", "note", "task"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(typeOptions, id: \.self) { t in
                        Button { vm.typeFilter = t } label: {
                            Text(t.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(vm.typeFilter == t ? Color.blue : Color(uiColor: .secondarySystemBackground))
                                .foregroundColor(vm.typeFilter == t ? .white : .gray)
                                .cornerRadius(8)
                        }
                    }
                }.padding()
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.filtered.isEmpty {
                        Text("No activity yet.").foregroundColor(.gray).padding(.top, 60)
                    } else {
                        ForEach(vm.filtered) { a in
                            ActivityTimelineItem(activity: a)
                        }
                    }
                }.padding()
            }
            .refreshable { await vm.refresh() }
        }
        .navigationTitle("Activities")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCompose = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCompose) {
            ActivityComposeView { type, subject, desc in
                await vm.log(type: type, subject: subject, description: desc, dealId: nil, leadId: nil)
            }
        }
        .task { await vm.refresh() }
    }
}
