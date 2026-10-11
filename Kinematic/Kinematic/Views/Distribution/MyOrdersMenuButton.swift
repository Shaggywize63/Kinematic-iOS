import SwiftUI

/// The side-menu "My Orders" row. Next to its label it shows how many orders / payments / returns are saved on the
/// phone waiting to upload (or were refused) — e.g. "My Orders (2 waiting)" — because that list lives behind it.
/// Only distribution clients get this row, so only they ever observe the queue.
struct MyOrdersMenuButton: View {
    @Binding var isOpen: Bool
    @ObservedObject private var appState = KiniAppState.shared
    @ObservedObject private var cache = OrderCache.shared

    var body: some View {
        let summary = DistributionQueuePolicy.summary(of: cache.queueItemsForCurrentUser())
        let title = ClientFeatures.labelFor("menu", "my_orders", default: "My Orders") + DistributionQueuePolicy.badgeSuffix(summary)
        MenuButton(icon: "cart.fill", title: title, isSelected: false, color: .indigo) {
            withAnimation { isOpen = false }
            appState.activeSecondaryRoute = ModalRoute(route: .orderHistory)
        }
    }
}
