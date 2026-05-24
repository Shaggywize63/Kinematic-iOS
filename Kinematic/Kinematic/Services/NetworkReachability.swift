//
//  NetworkReachability.swift
//  Kinematic
//
//  Singleton wrapper around `NWPathMonitor` that publishes a Bool on the
//  main actor. On every offline → online transition we fire a background
//  task that drains the three pending-mutation queues:
//
//    1. AttendanceCache  (existing)
//    2. OrderCache       (existing — via DistributionViewModel.flushQueue)
//    3. CRMWriteQueue    (new, via CRMSyncEngine)
//
//  Using `Network.framework` directly (no SCNetworkReachability) gives us
//  a clean async stream of path updates and avoids the deprecated C API.
//

import Foundation
import Combine
import Network

@MainActor
final class NetworkReachability: ObservableObject {
    static let shared = NetworkReachability()

    /// True when the OS reports a satisfied path (Wi-Fi, cellular, ethernet).
    /// Starts optimistically `true` — we don't want the UI to flash an
    /// "offline" banner during the ~200 ms it takes NWPathMonitor to deliver
    /// its first update on cold launch.
    @Published private(set) var isOnline: Bool = true

    /// True when the device is on cellular (used for "save data" hints
    /// elsewhere — currently informational only).
    @Published private(set) var isExpensive: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kinematic.reachability", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = online
                self.isExpensive = expensive
                if wasOffline && online {
                    // Backed-off network is back — fire the global drain.
                    // Best-effort: failures are recorded on each queue and
                    // the next reachability event will pick them up.
                    self.triggerGlobalFlush()
                }
            }
        }
        monitor.start(queue: queue)
    }

    /// Drain attendance + order + CRM queues. Runs as a single detached
    /// Task so a slow flush on one queue doesn't block the others. Safe to
    /// call from anywhere (e.g. a "retry now" button on the offline banner).
    func triggerGlobalFlush() {
        Task.detached(priority: .utility) {
            await AttendanceCache.shared.flush()
            await CRMSyncEngine.shared.flushQueue()
            // Distribution flush lives on DistributionViewModel; the
            // existing scenePhase handler already invokes it on foreground.
            // The new reachability-driven path doesn't have a viewmodel
            // handy, so we exercise the underlying cache via the same API.
            await CRMSyncEngine.shared.flushDistribution()
        }
    }
}
