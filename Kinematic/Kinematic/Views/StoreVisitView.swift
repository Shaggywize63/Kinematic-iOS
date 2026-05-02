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

    var body: some View {
        // GeometryReader pins the layout to the actual visible screen width.
        // The previous attempts kept failing because StoreVisitView is mounted
        // as a sibling inside MainTabView's ZStack — that ZStack also holds a
        // horizontal-paging ScrollView whose LazyHStack has 3 screens of
        // intrinsic width, and SwiftUI was leaking that wider context into
        // sibling layout. Explicitly constraining to `geo.size.width` stops
        // the leak in every case.
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VibrantBackgroundView()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()

                // Single content column — explicit width so children always
                // know what canvas they're working against.
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    scrollContent
                }
                .frame(width: geo.size.width, alignment: .topLeading)

                // Loading Overlay
                if isStartingVisit {
                    ZStack {
                        Color(uiColor: .systemBackground).opacity(0.8).ignoresSafeArea()
                        VStack(spacing: 20) {
                            ProgressView().tint(.red).scaleEffect(1.5)
                            Text("Starting Visit & Validating Location...")
                                .foregroundColor(Color(uiColor: .label))
                                .font(.headline)
                            Button("CANCEL") { isStartingVisit = false }
                                .font(.caption).fontWeight(.bold).foregroundColor(.red)
                                .padding(.top, 10)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                // Activity Form Overlay
                if let activity = appState.selectedActivity {
                    ActivitySubmissionView(activity: activity)
                        .transition(.move(edge: .trailing))
                        .zIndex(10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showingPlanogramCapture) {
            PlanogramCaptureView(
                storeId: appState.selectedOutlet?.id,
                visitId: appState.activeVisitId,
                planogramId: nil
            )
        }
    }

    // MARK: - Sub-views

    /// Top header row: back chevron + outlet name/address.
    /// Uses explicit `.padding(.leading, 20)` so the chevron is never
    /// flush against the screen edge.
    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 12) {
            Button(action: { appState.selectedOutlet = nil }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10)
                    .background(Color(uiColor: .label).opacity(0.06))
                    .clipShape(Circle())
                    .foregroundColor(Color(uiColor: .label))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.selectedOutlet?.storeName ?? "Store Visit")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(uiColor: .label))
                    .lineLimit(1)
                Text(appState.selectedOutlet?.address ?? "No address provided")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .padding(.top, 56)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Scrolling content column. Uses explicit `.padding(.leading, 20)` and
    /// `.padding(.trailing, 20)` so left and right edges are independently
    /// controlled (some `.padding(.horizontal, …)` propagation issues we
    /// hit earlier).
    @ViewBuilder
    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                if isVisitActive {
                    HStack {
                        Image(systemName: "location.fill").foregroundColor(.green)
                        Text("Visit Active")
                            .font(.caption).fontWeight(.bold).foregroundColor(.green)
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

                // Section heading — explicit alignment so it never sizes to
                // intrinsic content width.
                VStack(alignment: .leading, spacing: 6) {
                    Text("ASSIGNED TASKS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Complete the following activities")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(Color(uiColor: .label))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !isClockedIn {
                    VStack(spacing: 14) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 52))
                            .foregroundColor(.secondary)
                        Text("Clock-in Required")
                            .font(.title3).fontWeight(.bold)
                            .foregroundColor(Color(uiColor: .label))
                        Text("Please mark your daily attendance first to perform activities.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
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
                                .font(.system(size: 56))
                                .foregroundColor(.white.opacity(0.12))
                            Text("All caught up!\nNo specific tasks assigned for this outlet.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                    }
                }

                Spacer().frame(height: 120)
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func startVisit(andOpen activity: RouteActivity? = nil) {
        guard let outletId = appState.selectedOutlet?.id else { return }
        let lat = LocationTrackingService.shared.lastLocation?.coordinate.latitude ?? 0
        let lng = LocationTrackingService.shared.lastLocation?.coordinate.longitude ?? 0

        isStartingVisit = true
        KiniAppState.shared.visitErrorMessage = nil

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

        Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
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
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(activity.status == "completed" ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: activity.status == "completed" ? "checkmark.circle.fill" : "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundColor(activity.status == "completed" ? .green : .red)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.name ?? "Unknown Activity")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(uiColor: .label))
                    Text((activity.status ?? "pending").uppercased())
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(activity.status == "completed" ? .green : .orange)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
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
        .buttonStyle(.plain)
    }
}

private struct PlanogramAuditCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Planogram audit")
                        .font(.system(size: 16, weight: .semibold))
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
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
        .buttonStyle(.plain)
    }
}
