//
//  PushNotificationService.swift
//  Kinematic
//
//  Mirrors the Android KinematicFirebaseMessagingService:
//   - Requests notification permission
//   - Forwards FCM token to the backend (/notifications/fcm-token)
//   - Presents foreground notifications
//   - Routes taps to the relevant detail screen via KiniAppState
//
//  IMPORTANT: This file compiles only after `FirebaseMessaging` has been
//  added to the Xcode target via Swift Package Manager. See
//  IOS_PUSH_SETUP.md at the repo root for the manual steps.
//
//  Until the SPM dependency is added, the `#if canImport(FirebaseMessaging)`
//  guard keeps the rest of the app buildable.
//
import Foundation
import UserNotifications
import UIKit

#if canImport(FirebaseMessaging)
import FirebaseMessaging
import FirebaseCore
#endif

// MARK: - Deep-link payload

/// Notification payload contract shared with the backend.
/// The backend `sendNotification` controller already places `type`, `title`,
/// `body` and optional entity ids (`lead_id`, `deal_id`, `task_id`,
/// `attendance_id`) into the `data` payload of every FCM message.
struct PushDeepLink {
    let type: String
    let leadId: String?
    let dealId: String?
    let taskId: String?
    let attendanceId: String?

    init(userInfo: [AnyHashable: Any]) {
        self.type = (userInfo["type"] as? String) ?? ""
        self.leadId = userInfo["lead_id"] as? String
        self.dealId = userInfo["deal_id"] as? String
        self.taskId = userInfo["task_id"] as? String
        self.attendanceId = userInfo["attendance_id"] as? String
    }
}

// MARK: - Service

final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    /// Cached APNs device token (hex string). Populated after
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    private(set) var apnsTokenHex: String?

    /// Most-recent FCM token. Sent to the backend whenever it changes
    /// and again on login / app foreground.
    private(set) var lastFcmToken: String?

    private override init() {
        super.init()
    }

    // MARK: Bootstrap

    /// Called from `AppDelegate.application(_:didFinishLaunching...)`.
    /// Configures Firebase, wires up the UN center delegate, and asks the
    /// user for permission. Safe to call multiple times.
    func bootstrap(application: UIApplication) {
        #if canImport(FirebaseMessaging)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        Messaging.messaging().delegate = self
        #endif

        UNUserNotificationCenter.current().delegate = self
        requestAuthorization(application: application)
    }

    private func requestAuthorization(application: UIApplication) {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, error in
            if let error = error {
                print("❌ [Push] Authorization error: \(error.localizedDescription)")
                return
            }
            print("📲 [Push] Permission granted=\(granted)")
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    // MARK: APNs -> FCM bridge

    /// Called from `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    func setAPNsToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.apnsTokenHex = hex
        print("📲 [Push] APNs token: \(hex.prefix(12))…")

        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        // Touch the FCM token so the delegate fires.
        Messaging.messaging().token { token, error in
            if let token = token {
                print("📲 [Push] FCM token (after APNs): \(token.prefix(16))…")
                self.sendTokenToBackend(token)
            } else if let error = error {
                print("❌ [Push] Failed to fetch FCM token: \(error.localizedDescription)")
            }
        }
        #endif
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("❌ [Push] APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: Backend sync

    /// Post the FCM token to the existing PATCH /notifications/fcm-token endpoint.
    /// Sends `platform: "ios"` so the backend can route APNs config in the
    /// future. Auth uses the bearer token already in `Session.sharedToken`.
    func sendTokenToBackend(_ token: String) {
        self.lastFcmToken = token
        guard !Session.sharedToken.isEmpty else {
            print("⚠️ [Push] Skipping token sync — not authenticated yet.")
            return
        }

        let baseURL = "https://kinematic-production.up.railway.app/api/v1"
        guard let url = URL(string: "\(baseURL)/notifications/fcm-token") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.timeoutInterval = 15
        req.setValue("Bearer \(Session.sharedToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let orgId = Session.currentUser?.orgId {
            req.setValue(orgId, forHTTPHeaderField: "X-Org-Id")
        }

        let payload: [String: Any] = [
            "token": token,
            "platform": "ios"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error {
                print("❌ [Push] Token POST failed: \(error.localizedDescription)")
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("📡 [Push] Token POST status: \(code)")
        }.resume()
    }

    /// Call this after a successful login (e.g. from your login VM)
    /// to make sure the freshly-issued token reaches the backend even if
    /// it was already cached before the user signed in.
    func resendTokenAfterLogin() {
        if let token = lastFcmToken {
            sendTokenToBackend(token)
        }
    }

    // MARK: Deep-link routing

    private func routeDeepLink(_ link: PushDeepLink) {
        DispatchQueue.main.async {
            let app = KiniAppState.shared
            // The KinematicApp uses `selectedTab` + `activeSecondaryRoute`
            // for sheet-style routing. Notifications open the matching
            // detail screen if an id is present; otherwise they fall back
            // to the in-app notifications list.
            switch link.type {
            case "lead_assigned", "lead_update":
                // Lead detail lives inside the CRM tab. We surface the
                // notifications list as a fallback so the rep can still
                // jump into the lead from there if deep routing isn't
                // wired for a given build.
                app.selectedTab = 0
                app.activeSecondaryRoute = ModalRoute(route: .notifications)
                if let leadId = link.leadId {
                    UserDefaults.standard.set(leadId, forKey: "pending_push_lead_id")
                }
            case "deal_stage_change", "deal_update":
                app.selectedTab = 0
                app.activeSecondaryRoute = ModalRoute(route: .notifications)
                if let dealId = link.dealId {
                    UserDefaults.standard.set(dealId, forKey: "pending_push_deal_id")
                }
            case "task_due", "task_assigned":
                app.selectedTab = 0
                app.activeSecondaryRoute = ModalRoute(route: .notifications)
                if let taskId = link.taskId {
                    UserDefaults.standard.set(taskId, forKey: "pending_push_task_id")
                }
            case "attendance_reminder":
                // Attendance is the default Home tab.
                app.selectedTab = 0
            case "broadcast":
                fallthrough
            default:
                app.activeSecondaryRoute = ModalRoute(route: .notifications)
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {
    /// Foreground notification presentation. Show banner + sound so the
    /// rep doesn't miss alerts while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        print("📥 [Push] Foreground notification: \(userInfo)")

        // Forward the data dict to FIRMessaging for analytics parity.
        #if canImport(FirebaseMessaging)
        Messaging.messaging().appDidReceiveMessage(userInfo)
        #endif

        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    /// Tap handler. Parses the deep-link entity id and routes via KiniAppState.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("👆 [Push] Tap: \(userInfo)")

        #if canImport(FirebaseMessaging)
        Messaging.messaging().appDidReceiveMessage(userInfo)
        #endif

        let link = PushDeepLink(userInfo: userInfo)
        routeDeepLink(link)
        completionHandler()
    }
}

// MARK: - MessagingDelegate

#if canImport(FirebaseMessaging)
extension PushNotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("🔄 [Push] FCM token refreshed: \(token.prefix(16))…")
        sendTokenToBackend(token)
    }
}
#endif
