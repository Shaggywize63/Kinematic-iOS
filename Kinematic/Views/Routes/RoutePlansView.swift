import SwiftUI

struct RoutePlansView: View {
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Today's Assigned Route")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                        .padding(.top, 40)
                        .padding(.horizontal)
                    
                    // Route Task Card 1
                    RouteCard(
                        title: "Retail Merchandising Audit",
                        client: "Horizon Tech",
                        time: "09:00 AM",
                        status: .completed
                    )
                    
                    // Route Task Card 2
                    RouteCard(
                        title: "Restock Verification",
                        client: "Nexus Solutions",
                        time: "11:30 AM",
                        status: .inProgress
                    )
                    
                    // Route Task Card 3
                    RouteCard(
                        title: "Manager Check-in",
                        client: "Quantum Retail",
                        time: "02:00 PM",
                        status: .pending
                    )
                }
                .padding(.bottom, 120) // Tab bar clearance
            }
        }
    }
}

enum RouteStatus {
    case completed
    case inProgress
    case pending
    
    var color: Color {
        switch self {
        case .completed: return .green
        case .inProgress: return .kGradient4 // Orange/Red
        case .pending: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "arrow.triangle.2.circlepath.circle.fill"
        case .pending: return "clock.fill"
        }
    }
}

struct RouteCard: View {
    let title: String
    let client: String
    let time: String
    let status: RouteStatus
    
    var body: some View {
        HStack(spacing: 16) {
            // Timeline line & icon
            VStack {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 2, height: 20)
                
                Image(systemName: status.icon)
                    .foregroundColor(status.color)
                    .font(.title2)
                    .background(Circle().fill(Color.black).padding(2)) // Mask out line below
                
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 2, height: 20)
            }
            
            // Glass Content Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Text(time)
                        .font(.caption)
                        .bold()
                        .foregroundColor(status.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(status.color.opacity(0.2))
                        .cornerRadius(8)
                }
                
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(.gray)
                        .font(.caption)
                    Text(client)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .liquidGlass(cornerRadius: 16, opacity: 0.1)
        }
        .padding(.horizontal)
    }
}

#Preview {
    RoutePlansView()
}
