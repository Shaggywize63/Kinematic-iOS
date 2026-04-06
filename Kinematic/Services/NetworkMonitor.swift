import Foundation
import Network

/// Monitors real-time network connectivity changes for the Kinematic app.
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "KinematicNetworkMonitor")
    
    @Published var isConnected: Bool = true
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            // UI updates must be on the main thread
            DispatchQueue.main.async {
                self.isConnected = path.status == .satisfied
                
                if self.isConnected {
                    print("Kinematic iOS: Online — Re-triggering sync...")
                } else {
                    print("Kinematic iOS: Offline — Switch to storage mode")
                }
            }
        }
        monitor.start(queue: queue)
    }
}
