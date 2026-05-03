import SwiftUI

/// CRM-scoped settings: pipelines, templates, automation rules. Real edits
/// are deferred to the web console; this view is informational + linkable.
struct CRMSettingsView: View {
    var body: some View {
        List {
            Section("CRM Configuration") {
                NavigationLink("Pipelines") { PipelineView() }
                NavigationLink("Email templates") { EmailTemplatesView() }
                NavigationLink("Reports") { ReportsView() }
            }
            Section("Advanced") {
                Label("Assignment rules", systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundColor(.secondary)
                Label("Custom fields", systemImage: "square.and.pencil")
                    .foregroundColor(.secondary)
                Label("Automations", systemImage: "bolt.horizontal")
                    .foregroundColor(.secondary)
                Text("Manage these from the web console.")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .navigationTitle("CRM Settings")
    }
}
