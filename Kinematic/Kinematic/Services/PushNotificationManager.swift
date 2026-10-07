import UIKit
import UserNotifications

/// Native APNs push for iOS.
///
/// The app registers for remote notifications and uploads its APNs device
/// token to the backend (`PATCH /notifications/fcm-token` with
/// `platform:"ios"`). The backend then sends alerts directly over APNs/HTTP-2
/// (see `Kinematic/src/lib/apns.ts`). Android continues to use FCM — the two
/// transports are routed by the `fcm_platform` column server-side.
///
/// IMPORTANT — the paid Apple Developer Program is required to actually
/// deliver. Remote push needs the "Push Notifications" capability + an
/// `aps-environment` entitlement which — exactly like `UIBackgroundModes:location`
/// — is gated behind the paid program. On a free-Apple-ID dev build
/// `registerForRemoteNotifications()` fails cleanly via
/// `didFailToRegisterForRemoteNotificationsWithError` and we just log it: the
/// app never crashes and no token is uploaded. To activate:
///   1. Enable the "Push Notifications" capability on the Kinematic target and
///      sign with a paid-program provisioning profile.
///   2. Create an APNs Auth Key (.p8) in the Apple Developer portal and set the
///      backend env vars APNS_AUTH_KEY_P8 / APNS_KEY_ID / APNS_TEAM_ID /
///      APNS_BUNDLE_ID / APNS_PRODUCTION.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// APNs handed us a device token — hex-encode and upload it (only when the
    /// user is signed in, since the upload call needs an auth token).
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📲 [Push] APNs device token: \(hex.prefix(12))…")
        guard Session.isAuthenticated else {
            print("📲 [Push] Not signed in yet — token uploads after login re-triggers registration.")
            return
        }
        Task { _ = await KinematicRepository.shared.registerPushToken(token: hex, platform: "ios") }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on free-Apple-ID dev builds (no aps-environment entitlement).
        print("📲 [Push] Remote registration failed: \(error.localizedDescription)")
    }

    /// Foreground: still surface the banner + sound so reps don't miss a
    /// stagnant-lead nudge while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Tap: open the exact screen the notification is about. `NotificationRoute` maps the
    /// payload's `kind` + entity ids to a screen (lead, deal, expense claim, leave, chat
    /// thread, SOS, …) — the same table the in-app list uses. A push with no screen of its
    /// own opens the in-app notification list, as every push did before.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let data = NotificationRoute.payload(fromUserInfo: response.notification.request.content.userInfo)
        let target = NotificationRoute.forPush(data) ?? .notificationList
        DispatchQueue.main.async {
            KiniAppState.shared.pendingPushData = data
            KiniAppState.shared.open(target)
        }
        completionHandler()
    }
}

enum PushNotificationManager {
    /// Ask for notification permission (safe on any build) and, if granted,
    /// register for remote notifications. Idempotent — safe to call on every
    /// launch / resume / login; iOS returns the cached token quickly so the
    /// upload runs again once the user is authenticated.
    static func requestAuthorizationAndRegister() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("📲 [Push] Authorization error: \(error.localizedDescription)")
            }
            guard granted else {
                print("📲 [Push] Notification permission not granted.")
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}
