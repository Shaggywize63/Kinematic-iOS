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
                        case .orderHistory:
                            OrderHistoryView()
                        case .orderCart:
                            OrderCartView(outletId: "", outletName: nil, visitId: nil)
                        case .orderReview:
                            // Reached only via NavigationLink from OrderCartView; placeholder for direct opens.
                            OrderHistoryView()
                        case .orderDetail:
                            OrderHistoryView()
                        case .paymentCollect, .returns, .distributorStock, .secondarySales:
                            // M2/M3 modules — UI ships in those milestones.
                            ComingSoonView()
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

