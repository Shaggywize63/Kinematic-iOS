import SwiftUI
import CoreLocation

struct StoreVisitView: View {
    @EnvironmentObject var appState: KiniAppState
    @State private var isStartingVisit = false
    
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
        ZStack {
            VibrantBackgroundView()
            
            VStack(spacing: 0) {
                // Header (Same as before)
                HStack {
                    Button(action: { appState.selectedOutlet = nil }) {
                        Image(systemName: "chevron.left")
                            .padding(12).background(Color(uiColor: .label).opacity(0.05)).clipShape(Circle()).foregroundColor(Color(uiColor: .label))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.selectedOutlet?.storeName ?? "Store Visit").font(.headline).foregroundColor(Color(uiColor: .label))
                        Text(appState.selectedOutlet?.address ?? "No address provided").font(.caption).foregroundColor(.gray)
                    }
                    .padding(.leading, 8)
                    Spacer()
                }
                .padding(.horizontal, 28).padding(.top, 60).padding(.bottom, 20)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        
                        // Active Session Indicator (Optional top bar)
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
                            .padding(12).background(Color.green.opacity(0.1)).cornerRadius(10).padding(.horizontal, 28)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("ASSIGNED TASKS").font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(1)
                            Text("Complete the following activities").font(.title3).fontWeight(.black).foregroundColor(Color(uiColor: .label))
                        }
                        .padding(.horizontal, 28)

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
                                    .padding(.horizontal, 32)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                        } else if !resolvedActivities.isEmpty {
                            VStack(spacing: 15) {
                                ForEach(resolvedActivities) { activity in
                                    TaskCard(activity: activity) {
                                        if isVisitActive {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                appState.selectedActivity = activity
                                            }
                                        } else {
                                            // Trigger check-in prompt
                                            self.isStartingVisit = true
                                            startVisit(andOpen: activity)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                        } else {
                            VStack(spacing: 20) {
                                Image(systemName: "checklist.checked").font(.system(size: 80)).foregroundColor(.white.opacity(0.1))
                                Text("All caught up!\nNo specific tasks assigned for this outlet.").font(.subheadline).multilineTextAlignment(.center).foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 40)
                        }
                        
                        // Footer padding
                        Spacer().frame(height: 100)
                    }
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
            // Activity form is presented via fullScreenCover (see modifier below).
        }
        .fullScreenCover(item: $appState.selectedActivity) { activity in
            ActivitySubmissionView(activity: activity)
                .environmentObject(appState)
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
