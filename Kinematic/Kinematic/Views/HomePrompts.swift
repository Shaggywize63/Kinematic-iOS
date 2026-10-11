//
//  HomePrompts.swift
//  Kinematic
//
//  What Home hosts that appears only for clients that opted in BY DATA, attached to HomeView with one modifier:
//
//   • "Add today's travel to expenses?" after the final check-out (expense policy `gps_distance`, see TravelPrompt);
//   • the rate-the-app prompt ("Enjoying Kinematic?", `app_ui_config.features.rate_prompt`, see RatePrompt) — shown only
//     from Home, only when nothing else on Home asks for attention, and answered at most once per session.
//
//  A client that configured neither sees nothing: no request is made, no counter moves, no dialog opens.
//

import SwiftUI
import StoreKit

struct HomePromptsModifier: ViewModifier {
    @ObservedObject private var appState = KiniAppState.shared
    @ObservedObject private var attendanceVM: AttendanceViewModel = KiniAppState.shared.attendanceVM
    @ObservedObject private var rulesStore = AttendanceRulesStore.shared
    @ObservedObject private var travel = TravelPromptModel.shared
    @ObservedObject private var rate = RatePromptCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    /// Today's shift has a check-out.
    private var shiftCompleted: Bool {
        appState.today?.checkinAt != nil && appState.today?.checkoutAt != nil
    }

    /// Today's mode of transport (for a client whose attendance rule asks for one): pre-selects the travel vehicle.
    private var transportModeId: String? {
        rulesStore.rules.transportPromptActive ? appState.today?.transportMode : nil
    }

    /// Nothing on Home is asking for the rep's attention: the tab is showing and no menu, sheet, cover, prompt or
    /// "turn on location" alert is up. (A dialog drawn over the wrong screen is the thing this exists to avoid.)
    private var homeIsQuiet: Bool {
        appState.selectedTab == 0
            && !appState.showSideMenu
            && appState.activeSecondaryRoute == nil
            && appState.selectedOutlet == nil
            && appState.locationGatePrompt == nil
            && !appState.showGlobalSuccess
            && !travel.sheetOpen
            && !travel.checkoutPending
            && !travel.creating
            && attendanceVM.freshCheckoutDate == nil
            && !attendanceVM.isLoading
    }

    private var travelSheetBinding: Binding<Bool> {
        Binding<Bool>(
            get: { travel.sheetOpen },
            set: { shown in if !shown { travel.closeSheet() } }
        )
    }

    private var ratePromptBinding: Binding<Bool> {
        Binding<Bool>(
            get: { rate.showingPrompt },
            // Dismissed any way but a button (nothing else closes an alert, but be safe) counts as "Maybe later".
            set: { shown in if !shown && rate.showingPrompt { rate.maybeLater() } }
        )
    }

    func body(content: Content) -> some View {
        content
            // ── Add today's travel to expenses ──
            .task(id: shiftCompleted) {
                await travel.refresh(shiftCompleted: shiftCompleted, expensesEnabled: ClientFeatures.showsExpenses)
            }
            .onChange(of: attendanceVM.freshCheckoutDate, initial: true) { _, date in
                guard let day = date else { return }
                // Taken once, whatever happens next.
                attendanceVM.consumeFreshCheckout()
                // A successful online check-out is a good moment for the rate-the-app prompt (clients that opted in).
                rate.notePositiveMoment()
                Task { await travel.onFreshCheckout(date: day, expensesEnabled: ClientFeatures.showsExpenses) }
            }
            .onChange(of: transportModeId, initial: true) { _, id in
                travel.setTransportMode(id)
            }
            .sheet(isPresented: travelSheetBinding) {
                TravelPromptSheet(model: travel)
                    .presentationDetents([.medium, .large])
            }
            // ── Rate the app ──
            .onAppear { rate.noteAppOpened() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { rate.noteAppOpened() }
            }
            .task(id: homeIsQuiet) {
                if homeIsQuiet {
                    // Wait a moment after Home settles, so a sheet or dialog that opens just after wins.
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if !Task.isCancelled && homeIsQuiet { rate.offer() }
                } else {
                    rate.withdraw()
                }
            }
            .onDisappear { rate.withdraw() }
            .alert("Enjoying Kinematic?", isPresented: ratePromptBinding) {
                Button("Rate now") {
                    rate.rated()
                    // The system decides whether to show its review dialog (it limits how often it does).
                    requestReview()
                }
                Button("Don't ask again", role: .destructive) { rate.never() }
                Button("Maybe later", role: .cancel) { rate.maybeLater() }
            } message: {
                Text("A quick rating on the App Store helps us improve.")
            }
    }
}

extension View {
    /// Hosts the opt-in prompts of Home (travel-to-expenses after check-out, rate the app). See `HomePromptsModifier`.
    func homePrompts() -> some View {
        modifier(HomePromptsModifier())
    }
}

/// The "Rate this app" row of Settings: opt-in per client (`app_ui_config.features.rate_prompt`) and still hideable by an
/// admin (`settings.rate_app == false`). Asks the system for its review dialog, like "Rate now".
struct RateThisAppRow: View {
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        if ClientFeatures.featureOn(RatePrompt.featureId) && ClientFeatures.settingsVisible("rate_app") {
            Button {
                RatePromptCoordinator.shared.rated()
                requestReview()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rate this app").font(.headline).foregroundColor(.primary)
                        Text("Tell us how we're doing on the App Store").font(.caption).foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.gray).font(.caption)
                }
                .padding(16)
                .background(Color.white.opacity(0.03))
                .cornerRadius(20)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
        }
    }
}
