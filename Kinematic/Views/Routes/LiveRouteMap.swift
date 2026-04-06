import SwiftUI
import MapKit

struct RouteLocation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let storeName: String
    let isCompleted: Bool
}

struct LiveRouteMap: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090), // Default to New Delhi
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    // Mock data based on the Backend Android payload
    let routePlan = [
        RouteLocation(coordinate: CLLocationCoordinate2D(latitude: 28.6149, longitude: 77.2090), storeName: "Connaught Place Outlet", isCompleted: true),
        RouteLocation(coordinate: CLLocationCoordinate2D(latitude: 28.6200, longitude: 77.2150), storeName: "Retail Kiosk A", isCompleted: false)
    ]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. MapKit Layer
            Map(coordinateRegion: $region, annotationItems: routePlan) { location in
                MapAnnotation(coordinate: location.coordinate) {
                    VStack {
                        Image(systemName: location.isCompleted ? "checkmark.circle.fill" : "mappin.circle.fill")
                            .font(.title)
                            .foregroundColor(location.isCompleted ? .green : .kRed)
                            .background(Circle().fill(Color.white))
                        
                        Text(location.storeName)
                            .font(.caption2)
                            .bold()
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                }
            }
            .ignoresSafeArea()
            
            // 2. Liquid Glass Information Panel Overlay
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Active Route")
                            .font(.headline)
                        Text("2 locations remaining")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    
                    Button(action: {
                        // Recenter Map
                        print("Center map on current location")
                    }) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.kRed.opacity(0.8))
                            .clipShape(Circle())
                    }
                }
                
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .kRed))
                    Text("Tracking Location...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            // Using the GlassKit component built in Phase 1
            .liquidGlass(cornerRadius: 24, opacity: 0.15, shadowRadius: 30)
            .padding(.horizontal)
            .padding(.bottom, 100) // Padding for the floating Tab bar
        }
    }
}

#Preview {
    LiveRouteMap()
}
