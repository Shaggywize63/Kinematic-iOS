import SwiftUI
import SwiftData

@main
struct KinematicApp: App {
    @State private var isAuthenticated = false
    
    // Create the SwiftData container for our offline storage
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            OfflineSubmission.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                        .preferredColorScheme(.dark)
                }
            }
            .environmentObject(NetworkMonitor.shared)
        }
        .modelContainer(sharedModelContainer)
    }
}
