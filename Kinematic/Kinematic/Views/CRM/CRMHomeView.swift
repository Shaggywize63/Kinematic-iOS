import SwiftUI

/// Tab container for the CRM module. Surfaces the most-used screens as a
/// bottom-pill TabView and lets ParityViews/SideMenu push it as a single
/// destination.
struct CRMHomeView: View {
    @State private var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { CRMDashboardView() }
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
                .tag(0)
            NavigationStack { LeadsListView() }
                .tabItem { Label("Leads", systemImage: "person.crop.circle.badge.plus") }
                .tag(1)
            NavigationStack { DealKanbanView() }
                .tabItem { Label("Pipeline", systemImage: "square.stack.3d.up.fill") }
                .tag(2)
            NavigationStack { ContactsListView() }
                .tabItem { Label("Contacts", systemImage: "person.2.fill") }
                .tag(3)
            NavigationStack { KiniChatView() }
                .tabItem { Label("KINI", systemImage: "sparkles") }
                .tag(4)
        }
        .accentColor(.indigo)
    }
}
