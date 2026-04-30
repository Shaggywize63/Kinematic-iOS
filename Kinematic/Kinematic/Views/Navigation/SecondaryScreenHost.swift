import SwiftUI

struct SecondaryScreenHost: View {
    let route: ModalRoute
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: KiniAppState
    
    var body: some View {
        Group {
            if route.route == .camera {
                ImagePicker(image: $appState.capturedSelfie)
                    .ignoresSafeArea()
            } else {
                NavigationView {
                    Group {
                        switch route.route {
                        case .profile:
                            ProfileView()
                        case .broadcast:
                            BroadcastHubView()
                        case .learning:
                            LearningHubView()
                        case .settings:
                            SettingsView()
                        case .leaderboard:
                            LeaderboardView()
                        case .notifications:
                            NotificationsView()
                        case .grievance:
                            GrievanceView()
                        case .visitlog:
                            VisitLogView()
                        case .stock:
                            StockView()
                        case .sos:
                            SOSView()
                        case .activity:
                            ActivityFeedView()
                        case .camera:
                            EmptyView() // Handled above
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
    }
    }

