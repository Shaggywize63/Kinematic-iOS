//
//  AppDelegate.swift
//  Kinematic
//
//  SwiftUI app uses @UIApplicationDelegateAdaptor to bridge into this
//  delegate so we can:
//    - Configure Firebase before any SwiftUI view runs
//    - Receive the APNs device token
//    - Forward background notification fetches
//
//  This is the iOS counterpart to the Android KinematicApp class +
//  KinematicFirebaseMessagingService.
//
import UIKit
import UserNotifications

#if canImport(FirebaseCore)
import FirebaseCore
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("🚀 [AppDelegate] didFinishLaunching — bootstrapping push.")
        PushNotificationService.shared.bootstrap(application: application)
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationService.shared.setAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationService.shared.didFailToRegisterForRemoteNotifications(error: error)
    }

    /// Silent / data-only pushes land here. Forward to UNUserNotificationCenter
    /// path so PushNotificationService can apply the same deep-link routing.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📨 [AppDelegate] Background remote notification: \(userInfo)")
        completionHandler(.newData)
    }
}
