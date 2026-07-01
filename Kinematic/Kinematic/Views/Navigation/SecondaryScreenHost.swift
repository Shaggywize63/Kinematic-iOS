import SwiftUI

struct SecondaryScreenHost: View {
    let route: ModalRoute
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: KiniAppState
    
    var body: some View {
        Group {
            // Per-client SKU gate. Block sheets for any module the client hasn't purchased.
            if !route.route.isAvailable(for: Session.currentUser) {
                NavigationView {
                    VStack(spacing: 14) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 56))
                            .foregroundColor(.secondary)
                        Text("Module not enabled")
                            .font(.title3.bold())
                        Text("This feature isn't part of your account's plan. Contact your administrator to enable it.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: { dismiss() }) {
                                HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("Close") }
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } else if route.route == .camera {
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
                        case .leave:
                            LeaveHomeView()
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

