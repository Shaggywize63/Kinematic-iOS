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
                        case .paymentCollect:
                            PaymentCollectView(outletId: "", outletName: nil)
                        case .returns:
                            ReturnView(outletId: "", originalInvoiceId: "")
                        case .distributorStock, .secondarySales:
                            // Distributor-stock + secondary-sales lightweight UIs ship in a follow-up patch.
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

