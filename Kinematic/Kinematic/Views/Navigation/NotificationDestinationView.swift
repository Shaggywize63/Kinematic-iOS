import SwiftUI

/// The screen a notification opens.
///
/// Used by both a tapped push (hosted by `SecondaryScreenHost`'s `.notificationTarget`
/// route) and by a row in the in-app notification list, so the two always land in the same
/// place. Which target a payload maps to is decided in `NotificationRoute`.
struct NotificationDestinationView: View {
    let target: NotificationTarget
    @EnvironmentObject var appState: KiniAppState

    var body: some View {
        switch target {
        case .lead(let id):
            LeadDetailView(leadId: id)
        case .deal(let id):
            DealDetailView(dealId: id)
        case .expenseClaim(let id):
            // Expenses ship per client; a tenant without them lands on the list instead.
            if ClientFeatures.showsExpenses {
                // ExpenseClaimsView opens `pendingExpenseClaimId` once its claims load.
                ExpenseClaimsView()
                    .onAppear { appState.pendingExpenseClaimId = id }
            } else {
                NotificationsView()
            }
        case .crmHome:
            CrmHomeMissionView()
        case .deals:
            DealsListView()
        case .activities:
            ActivitiesView()
        case .leaveApprovals:
            LeaveApprovalsView()
        case .leave:
            LeaveHomeView()
        case .regularization:
            RegularizationView()
        case .routePlans:
            RoutePlansView()
        case .sos:
            SOSView()
        case .broadcast:
            BroadcastHubView()
        case .stock:
            StockView()
        case .chatThread(let id):
            ChatThreadView(threadId: id)
        case .chatInbox:
            ChatListView()
        case .checkIn, .notificationList:
            // `.checkIn` switches tabs (see `KiniAppState.open`) and never reaches a host;
            // the list is its own route. Either way, the list is a safe thing to show.
            NotificationsView()
        }
    }
}
