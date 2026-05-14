import SwiftUI

/// CRM-scoped settings: pipelines, templates, automation rules. Real edits
/// are deferred to the web console; this view is informational + linkable.
///
/// Also hosts the global app-appearance toggle (Light / Dark / System)
/// for CRM-only deployments — the toggle that already lives on the
/// field-force `SettingsView` isn't reachable from inside CRMTabView,
/// so reps stuck in CRM-only mode previously had no way to switch
/// themes.
struct CRMSettingsView: View {
    @EnvironmentObject var appState: KiniAppState

    var body: some View {
        List {
            Section("Appearance") {
                themeRow("System", appTheme: .system, icon: "circle.lefthalf.filled")
                themeRow("Light",  appTheme: .light,  icon: "sun.max.fill")
                themeRow("Dark",   appTheme: .dark,   icon: "moon.stars.fill")
            }
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

    @ViewBuilder
    private func themeRow(_ label: String, appTheme: AppTheme, icon: String) -> some View {
        Button {
            appState.theme = appTheme
        } label: {
            HStack {
                Image(systemName: icon).foregroundColor(.red).frame(width: 24)
                Text(label).foregroundColor(.primary)
                Spacer()
                if appState.theme == appTheme {
                    Image(systemName: "checkmark").foregroundColor(.red).fontWeight(.bold)
                }
            }
        }
    }
}
