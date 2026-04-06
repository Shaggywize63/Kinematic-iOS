import SwiftUI

struct VisitLogsView: View {
    @State private var selectedFilter = "Today"
    let filters = ["Today", "Yesterday", "This Week"]
    
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            
            VStack(spacing: 0) {
                // Header & Filters
                VStack(alignment: .leading, spacing: 16) {
                    Text("Visit History")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                        .padding(.top, 40)
                    
                    // Liquid Glass Segmented Picker
                    HStack {
                        ForEach(filters, id: \.self) { filter in
                            Button(action: {
                                withAnimation { selectedFilter = filter }
                            }) {
                                Text(filter)
                                    .font(.subheadline.bold())
                                    .foregroundColor(selectedFilter == filter ? .white : .white.opacity(0.5))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedFilter == filter ? Color.kRed : Color.clear)
                                            .shadow(color: selectedFilter == filter ? .kRed.opacity(0.3) : .clear, radius: 5, y: 2)
                                    )
                            }
                        }
                    }
                    .padding(4)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(16)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                
                // Feed
                ScrollView {
                    VStack(spacing: 16) {
                        VisitLogCard(
                            clientName: "Horizon Tech",
                            location: "Sector 44, Gurgaon",
                            timeIn: "10:00 AM",
                            timeOut: "11:45 AM",
                            status: "Verified Check-in"
                        )
                        
                        VisitLogCard(
                            clientName: "Nexus Solutions",
                            location: "Cyber City",
                            timeIn: "12:15 PM",
                            timeOut: "In Progress",
                            status: "Active"
                        )
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 120) // Tab bar clearance
                }
            }
        }
    }
}

struct VisitLogCard: View {
    let clientName: String
    let location: String
    let timeIn: String
    let timeOut: String
    let status: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clientName)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.kRed)
                        Text(location)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(status)
                        .font(.caption.bold())
                        .foregroundColor(status == "Active" ? .kGradient4 : .green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background((status == "Active" ? Color.kGradient4 : Color.green).opacity(0.2))
                        .cornerRadius(8)
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Check In")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(timeIn)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                }
                
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Check Out")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(timeOut)
                        .font(.subheadline.bold())
                        .foregroundColor(timeOut == "In Progress" ? .gray : .white)
                }
            }
        }
        .padding()
        .liquidGlass(cornerRadius: 20, opacity: 0.1)
    }
}

#Preview {
    VisitLogsView()
}
