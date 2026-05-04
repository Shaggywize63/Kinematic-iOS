import SwiftUI

struct EmailTemplatesView: View {
    @State private var templates: [EmailTemplate] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if isLoading { ProgressView() }
                ForEach(templates) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t.name).font(.headline)
                        Text(t.subject).font(.caption).foregroundColor(.secondary)
                        Text(t.body).font(.caption2).foregroundColor(.gray).lineLimit(3)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
                }
            }
            .padding()
        }
        .navigationTitle("Templates")
        .task {
            isLoading = true
            templates = (try? await CRMService.shared.listEmailTemplates()) ?? []
            isLoading = false
        }
    }
}
