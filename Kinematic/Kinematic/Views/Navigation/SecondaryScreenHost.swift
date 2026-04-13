import SwiftUI

struct SecondaryScreenHost: View {
    let route: SecondaryRoute
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                switch route {
                case .profile:
                    ProfileView()
                case .broadcast:
                    BroadcastHubView()
                case .learning:
                    LearningHubView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
        }
    }
}
