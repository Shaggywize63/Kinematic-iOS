import SwiftUI

/// Tab container for the CRM module. Surfaces the most-used screens as a
/// bottom-pill TabView and lets ParityViews/SideMenu push it as a single
/// destination. KINI is reachable as a floating red action button at the
/// bottom-right of every CRM tab.
struct CRMHomeView: View {
    @State private var tab: Int = 0
    @State private var showKini = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                LocationFilter()
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
                    NavigationStack { ProductsListView() }
                        .tabItem { Label("Products", systemImage: "shippingbox.fill") }
                        .tag(4)
                }
                .accentColor(.indigo)
            }

            // Sticky red KINI button — only entry point.
            Button { showKini = true } label: {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 56, height: 56)
                        .shadow(color: .red.opacity(0.4), radius: 12, x: 0, y: 4)
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.trailing, 18)
            .padding(.bottom, 70)
            .sheet(isPresented: $showKini) {
                NavigationStack { KiniChatView() }
            }
        }
    }
}
