import SwiftUI

struct PipelineView: View {
    @State private var pipelines: [Pipeline] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading { ProgressView() }
                ForEach(pipelines) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(p.name).font(.headline)
                            Spacer()
                            if p.isDefault == true {
                                Text("DEFAULT").font(.system(size: 10, weight: .black))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green).cornerRadius(4)
                            }
                        }
                        if let stages = p.stages {
                            Text("\(stages.count) stages").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
                }
            }
            .padding()
        }
        .navigationTitle("Pipelines")
        .task {
            isLoading = true
            pipelines = (try? await CRMService.shared.listPipelines()) ?? []
            isLoading = false
        }
    }
}
