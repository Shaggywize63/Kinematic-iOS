import SwiftUI
import CoreLocation

struct StoreVisitView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedActivity: RouteActivity? = nil
    @State private var isStartingVisit = false
    
    var isVisitActive: Bool {
        appState.activeVisitOutletId == appState.selectedOutlet?.id
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
                .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 20)
                
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
                            .padding(12).background(Color.green.opacity(0.1)).cornerRadius(10).padding(.horizontal, 20)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("ASSIGNED TASKS").font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(1)
                            Text("Complete the following activities").font(.title3).fontWeight(.black).foregroundColor(Color(uiColor: .label))
                        }
                        .padding(.horizontal, 20)
                        
                        if let activities = appState.selectedOutlet?.activities, !activities.isEmpty {
                            VStack(spacing: 15) {
                                ForEach(activities) { activity in
                                    TaskCard(activity: activity) {
                                        if isVisitActive {
                                            self.selectedActivity = activity
                                        } else {
                                            // Trigger check-in prompt
                                            self.isStartingVisit = true
                                            startVisit(andOpen: activity)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
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
        }
        .sheet(item: $selectedActivity) { activity in
            ActivitySubmissionView(activity: activity)
        }
    }
    
    private func startVisit(andOpen activity: RouteActivity? = nil) {
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
                        if let activity = activity {
                            self.selectedActivity = activity
                        }
                    }
                }
            } else {
                await MainActor.run { isStartingVisit = false }
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
            .padding(20).liquidGlass()
        }
    }
}
