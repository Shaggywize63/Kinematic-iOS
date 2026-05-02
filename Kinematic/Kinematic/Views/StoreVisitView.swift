import SwiftUI
import CoreLocation

struct StoreVisitView: View {
    @EnvironmentObject var appState: KiniAppState
    @State private var isStartingVisit = false
    @State private var showingPlanogramCapture = false

    var isVisitActive: Bool {
        appState.activeVisitOutletId == appState.selectedOutlet?.id
    }

    var resolvedActivities: [RouteActivity] {
        // Priority 1: Backend aggregated activities array (newly supported)
        let explicit = appState.selectedOutlet?.activities ?? []
        if !explicit.isEmpty { return explicit }

        // Priority 2: Dashboard Linkage: Synth one if activityId is present at outlet level (legacy fallback)
        if let activityId = appState.selectedOutlet?.activityId {
            return [RouteActivity(id: activityId, name: "Store Activity", status: "pending")]
        }

        // Priority 3: Testing Fallback: Ensure user can ALWAYS test the Test Form even if linkage is missing
        return [
            RouteActivity(id: "test_audit_001", name: "Test Product Audit", status: "pending")
        ]
    }

    var isClockedIn: Bool {
        guard let today = appState.today else { return false }
        return today.checkinAt != nil && today.checkoutAt == nil
    }

    // Single source of truth for the page gutter. 20pt phones, 28pt larger.
    private let H: CGFloat = 20

    var body: some View {
        ZStack(alignment: .topLeading) {
            VibrantBackgroundView()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Button(action: { appState.selectedOutlet = nil }) {
                        Image(systemName: "chevron.left")
                            .padding(12)
                            .background(Color(uiColor: .label).opacity(0.05))
                            .clipShape(Circle())
                            .foregroundColor(Color(uiColor: .label))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.selectedOutlet?.storeName ?? "Store Visit")
                            .font(.headline)
                            .foregroundColor(Color(uiColor: .label))
                            .lineLimit(1)
                        Text(appState.selectedOutlet?.address ?? "No address provided")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, H)
                .padding(.top, 60)
                .padding(.bottom, 20)

                // Single ScrollView with one outer horizontal padding —
                // children no longer set their own `.padding(.horizontal,…)`,
                // which is what was producing the inconsistent left edge
                // (text vs. card vs. header).
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {

                        if isVisitActive {
                            HStack {
                                Image(systemName: "location.fill").foregroundColor(.green)
                                Text("Visit Active").font(.caption).fontWeight(.bold).foregroundColor(.green)
                                Spacer()
                                Button("END VISIT") {
                                    appState.activeVisitId = nil
                                    appState.activeVisitOutletId = nil
                                }
                                .font(.caption).fontWeight(.bold).foregroundColor(.red)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("ASSIGNED TASKS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                                .tracking(1)
                            Text("Complete the following activities")
                                .font(.title3)
                                .fontWeight(.black)
                                .foregroundColor(Color(uiColor: .label))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if !isClockedIn {
                            VStack(spacing: 16) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 56))
                                    .foregroundColor(.secondary)
                                Text("Clock-in Required")
                                    .font(.title3).fontWeight(.bold)
                                    .foregroundColor(Color(uiColor: .label))
                                Text("Please mark your daily attendance first to perform activities.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                        } else {
                            PlanogramAuditCard {
                                if isVisitActive {
                                    showingPlanogramCapture = true
                                } else {
                                    self.isStartingVisit = true
                                    startVisit()
                                    showingPlanogramCapture = true
                                }
                            }

                            if !resolvedActivities.isEmpty {
                                VStack(spacing: 12) {
                                    ForEach(resolvedActivities) { activity in
                                        TaskCard(activity: activity) {
                                            if isVisitActive {
                                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                    appState.selectedActivity = activity
                                                }
                                            } else {
                                                self.isStartingVisit = true
                                                startVisit(andOpen: activity)
                                            }
                                        }
                                    }
                                }
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "checklist.checked")
                                        .font(.system(size: 64))
                                        .foregroundColor(.white.opacity(0.12))
                                    Text("All caught up!\nNo specific tasks assigned for this outlet.")
                                        .font(.subheadline)
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 32)
                            }
                        }

                        Spacer().frame(height: 100)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, H)
                    .padding(.top, 4)
                }
            }

            // Loading Overlay when starting visit
            if isStartingVisit {
                ZStack {
                    Color(uiColor: .systemBackground).opacity(0.8).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView().tint(.red).scaleEffect(1.5)
                        Text("Starting Visit & Validating Location...")
                            .foregroundColor(Color(uiColor: .label))
                            .font(.headline)

                        Button("CANCEL") {
                            isStartingVisit = false
                        }
                        .font(.caption).fontWeight(.bold).foregroundColor(.red)
                        .padding(.top, 10)
                    }
                }
            }
            // Activity Form Overlay (Proper Screen Transition)
            if let activity = appState.selectedActivity {
                ActivitySubmissionView(activity: activity)
                    .transition(.move(edge: .trailing)) // "Push" from right
                    .zIndex(10)
            }
        }
        // Pin to the full screen explicitly. StoreVisitView is presented
        // as an overlay inside MainTabView's ZStack (which also contains a
        // horizontal-paging ScrollView whose intrinsic width is multiple
        // screens wide). Without these constraints the inner content can
        // inherit a wider sizing context and end up clipped on the left.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showingPlanogramCapture) {
            PlanogramCaptureView(
                storeId: appState.selectedOutlet?.id,
                visitId: appState.activeVisitId,
                planogramId: nil // backend resolves from store assignment
            )
        }
    }

    private func startVisit(andOpen activity: RouteActivity? = nil) {
        guard let outletId = appState.selectedOutlet?.id else { return }
        let lat = LocationTrackingService.shared.lastLocation?.coordinate.latitude ?? 0
        let lng = LocationTrackingService.shared.lastLocation?.coordinate.longitude ?? 0

        isStartingVisit = true
        KiniAppState.shared.visitErrorMessage = nil // Reset error

        let visitTask = Task {
            let result = await KinematicRepository.shared.logVisit(outletId: outletId, lat: lat, lng: lng)
            if !Task.isCancelled {
                await MainActor.run {
                    if let visitId = result {
                        withAnimation {
                            KiniAppState.shared.activeVisitId = visitId
                            KiniAppState.shared.activeVisitOutletId = outletId
                            self.isStartingVisit = false
                        }
                        // Non-animated state change for the sheet to ensure reliability
                        if let activity = activity {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                appState.selectedActivity = activity
                            }
                        }
                    } else {
                        self.isStartingVisit = false
                        KiniAppState.shared.visitErrorMessage = "Server rejected visit log. Please check GPS."
                    }
                }
            }
        }

        // Timeout Task
        Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000) // 12 seconds
            if self.isStartingVisit {
                visitTask.cancel()
                await MainActor.run {
                    withAnimation {
                        self.isStartingVisit = false
                        KiniAppState.shared.visitErrorMessage = "Connection timed out. Please try again."
                    }
                }
            }
        }
    }

    private func startVisit() {
        guard let outletId = appState.selectedOutlet?.id else { return }
        let lat = LocationTrackingService.shared.lastLocation?.coordinate.latitude ?? 0
        let lng = LocationTrackingService.shared.lastLocation?.coordinate.longitude ?? 0

        isStartingVisit = true
        Task {
            if let visitId = await KinematicRepository.shared.logVisit(outletId: outletId, lat: lat, lng: lng) {
                await MainActor.run {
                    withAnimation {
                        appState.activeVisitId = visitId
                        appState.activeVisitOutletId = outletId
                        isStartingVisit = false
                    }
                }
            } else {
                await MainActor.run { isStartingVisit = false }
            }
        }
    }
}

struct TaskCard: View {
    let activity: RouteActivity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                ZStack {
                    Circle().fill(activity.status == "completed" ? Color.green.opacity(0.1) : Color.red.opacity(0.1)).frame(width: 50, height: 50)
                    Image(systemName: activity.status == "completed" ? "checkmark.circle.fill" : "doc.text.fill").font(.title3).foregroundColor(activity.status == "completed" ? .green : .red)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.name ?? "Unknown Activity").font(.headline).foregroundColor(Color(uiColor: .label))
                    Text((activity.status ?? "pending").uppercased()).font(.system(size: 10, weight: .black)).foregroundColor(activity.status == "completed" ? .green : .orange)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .clear, .black.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
    }
}

private struct PlanogramAuditCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Planogram audit")
                        .font(.headline)
                        .foregroundColor(Color(uiColor: .label))
                    Text("CAPTURE SHELF · AI COMPLIANCE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.blue)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .clear, .black.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
    }
}
