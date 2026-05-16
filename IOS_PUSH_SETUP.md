# iOS Push Notification Setup (Firebase Cloud Messaging)

The Swift sources for push notifications have been committed:

- `Kinematic/Kinematic/Services/PushNotificationService.swift`
- `Kinematic/Kinematic/Services/AppDelegate.swift`
- `Kinematic/Kinematic/KinematicApp.swift` (wires `@UIApplicationDelegateAdaptor`)

This document covers the **manual Xcode steps** that cannot be done
from CI / scripted commits. You should expect to spend ~10 minutes in
Xcode to finish the integration.

---

## 1. Add Firebase iOS SDK via Swift Package Manager

1. Open `Kinematic/Kinematic.xcodeproj` in Xcode.
2. **File → Add Package Dependencies…**
3. Paste this URL into the search box:

   ```
   https://github.com/firebase/firebase-ios-sdk
   ```

4. Dependency rule: **Up to Next Major Version** — `11.0.0` (or newer).
5. When Xcode prompts for products, add the following to the **Kinematic** target:

   - `FirebaseMessaging`
   - `FirebaseAnalytics` (optional but Firebase recommends it for FCM delivery diagnostics)

The Swift sources are guarded with `#if canImport(FirebaseMessaging)`,
so the project will continue to compile even before this step — the
FCM code will simply no-op until the SDK is wired in.

## 2. Drop in `GoogleService-Info.plist`

1. In the [Firebase console](https://console.firebase.google.com/), open the **Kinematic** project (same one used for the Android app).
2. **Project settings → General → Your apps → Add app → iOS**.
3. Bundle ID: `com.shaggywize63.kinematic` (must match the value in `project.pbxproj`).
4. Download `GoogleService-Info.plist`.
5. Drag it into Xcode under the `Kinematic/Kinematic/` group **with "Copy items if needed" ticked and the Kinematic target checked**.

This file contains the real API key and project number, so it is
**gitignored** — do not commit it. Each developer / CI runner needs
their own copy.

## 3. Enable Push Notifications capability

1. Select the **Kinematic** target → **Signing & Capabilities** tab.
2. Click **+ Capability** and add:
   - **Push Notifications**
   - **Background Modes** — then tick **Remote notifications**.

This writes the `aps-environment` and `UIBackgroundModes:[remote-notification]`
entitlements. Note: the **Push Notifications** capability requires a
paid Apple Developer Program account; free Apple IDs cannot sign
builds with it (the same constraint that gates the `location`
background mode — see `Info.plist` comment).

## 4. Upload your APNs Auth Key to Firebase

FCM bridges to APNs server-side using an APNs Auth Key.

1. [Apple developer portal](https://developer.apple.com/account/resources/authkeys/list) → **Keys → +** → enable **Apple Push Notifications service (APNs)**, download the `.p8`.
2. Note the **Key ID** and your **Team ID** (`K7PLGT7499`).
3. Firebase console → **Project settings → Cloud Messaging → Apple app configuration → Upload** the `.p8`, key ID and team ID.

Without this step, the backend's `messaging.sendEachForMulticast(…)`
will report `messaging/registration-token-not-registered` for every
iOS token.

## 5. Verify end-to-end

1. Run the app on a **physical device** (push notifications do not
   deliver to the iOS Simulator unless you're on macOS 13+/iOS 16+
   with the simulator push-payload feature).
2. Watch the Xcode console:

   ```
   🚀 [AppDelegate] didFinishLaunching — bootstrapping push.
   📲 [Push] Permission granted=true
   📲 [Push] APNs token: 0a1b2c3d4e5f…
   📲 [Push] FCM token (after APNs): cQ7uXR2g…
   📡 [Push] Token POST status: 200
   ```

3. From the admin web app, send a broadcast to your user with
   **Send push** ticked. The notification should appear on the device.

## 6. Notification types currently supported

The backend places one of these `type` values into the FCM `data`
payload. Tap-routing in `PushNotificationService.routeDeepLink(…)`
handles each:

| `type`                    | Entity id key   | iOS routes to                       |
|---------------------------|-----------------|-------------------------------------|
| `lead_assigned`           | `lead_id`       | CRM lead detail (queued via UserDefaults) |
| `lead_update`             | `lead_id`       | CRM lead detail                     |
| `deal_stage_change`       | `deal_id`       | CRM deal detail                     |
| `deal_update`             | `deal_id`       | CRM deal detail                     |
| `task_due`                | `task_id`       | Task detail                         |
| `task_assigned`           | `task_id`       | Task detail                         |
| `attendance_reminder`     | —               | Home / attendance tab               |
| `broadcast` (default)     | —               | In-app notifications list           |

Add a new type → add a `case` in `routeDeepLink`.

## 7. Open items / future work

- **Per-platform FCM config in the backend**: today the server sends
  a single `{ notification, data, tokens }` multicast. To unlock
  iOS-specific behaviour (collapse-id, mutable-content, content-available),
  wrap each iOS token in `apns: { headers, payload }` per
  [Firebase Admin v11 docs](https://firebase.google.com/docs/cloud-messaging/send-message#admin).
  The accompanying backend commit on this branch already accepts a
  `platform` field, but the send path still treats tokens uniformly
  — follow-up work.
- **Notification Service Extension** for rich notifications (image
  attachments, mutable content). Not required for parity with the
  current Android stack.
- **Live Activities** are already enabled in `Info.plist`
  (`NSSupportsLiveActivities=true`); we can drive them from a
  notification when shifts start / end.
