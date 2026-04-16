import SwiftUI

struct SecondaryScreenHost: View {
    let route: SecondaryRoute
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    
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
        .sheet(isPresented: $appState.attendanceVM.showCamera) {
            ImagePicker(image: $appState.attendanceVM.selfie)
                .ignoresSafeArea()
        }
    }
}
