//
//  AppLock.swift
//  Kinematic
//
//  Biometric App Lock.
//
//  When the user turns on "App Lock" in Settings, the app is covered by an
//  opaque, brand-styled lock screen every time it becomes active — cold launch
//  or return from the background — while a session exists. Unlocking requires
//  Face ID / Touch ID, with an automatic device-passcode fallback
//  (`.deviceOwnerAuthentication` covers both). On success the app is revealed;
//  on backgrounding the lock re-arms so the next foreground re-prompts.
//
//  The lock stores NO credentials of its own. The auth token already lives in
//  the Keychain (see `Session` / `KeychainTokenStore`); this feature only gates
//  *access* to the already-authenticated app. It does not change auth at all.
//
//  Gate: the lock applies only when `app_lock_enabled == true` (UserDefaults,
//  default OFF) AND `Session.isAuthenticated` is true (a real session exists).
//  It never covers the login screen and never prompts when the toggle is off.
//
//  Graceful degradation: `.deviceOwnerAuthentication` still allows the device
//  passcode when no biometry is enrolled. Only when the device has no passcode
//  set at all can the policy not be evaluated — in that case we FAIL OPEN
//  (unlock) so the user is never trapped out of their own data, and log it.
//

import SwiftUI
import Combine
import LocalAuthentication

@MainActor
final class LockManager: ObservableObject {
    static let shared = LockManager()

    /// UserDefaults flag toggled from Settings. Default OFF. `@AppStorage` in
    /// the Settings toggle writes to `UserDefaults.standard` under this same key.
    static let enabledDefaultsKey = "app_lock_enabled"

    /// Timestamp (seconds since 1970) of the last successful unlock. Used to cap
    /// the prompt at once per CALENDAR DAY: after unlocking once today, minimising
    /// and reopening the app neither re-prompts nor re-covers it until tomorrow.
    static let lastUnlockDefaultsKey = "app_lock_last_unlocked_at"

    /// True when the last successful unlock was earlier today — so we should not
    /// prompt / cover again until the next calendar day.
    private func unlockedToday() -> Bool {
        let ts = UserDefaults.standard.double(forKey: Self.lastUnlockDefaultsKey)
        guard ts > 0 else { return false }
        return Calendar.current.isDateInToday(Date(timeIntervalSince1970: ts))
    }

    private func markUnlockedToday() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastUnlockDefaultsKey)
    }

    /// True while the opaque lock overlay must cover the whole app.
    @Published private(set) var isLocked: Bool
    /// True while a biometric / passcode prompt is on screen. Suppresses a
    /// second overlapping prompt and swaps the Unlock button for a spinner.
    @Published private(set) var isAuthenticating = false
    /// Set after a failed / cancelled attempt so the overlay shows "Retry".
    @Published private(set) var didFail = false

    private init() {
        // Cold launch: start locked if the feature is on AND a session exists —
        // unless the user already unlocked today (the once-per-day cap).
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        let ts = UserDefaults.standard.double(forKey: Self.lastUnlockDefaultsKey)
        let already = ts > 0 && Calendar.current.isDateInToday(Date(timeIntervalSince1970: ts))
        isLocked = enabled && Session.isAuthenticated && !already
    }

    /// App Lock is on (Settings toggle) AND the user is signed in. Reads the
    /// live values each time so a toggle change / logout is respected instantly.
    private var shouldGate: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) && Session.isAuthenticated
    }

    /// Scene became active — also called once at cold launch (from the root
    /// `.onAppear`). Prompts if we are currently locked, otherwise no-op.
    func handleForeground() {
        guard shouldGate else {
            // Toggle turned off, or the user logged out while backgrounded —
            // never leave a stale lock covering the app.
            if isLocked { isLocked = false }
            return
        }
        // Once-per-day cap: if the user already unlocked today, don't prompt or
        // cover again — just reveal the app.
        if unlockedToday() {
            if isLocked { isLocked = false }
            return
        }
        // Auto-prompt when we become active and are locked — but NOT right after
        // a failed / cancelled attempt. Presenting the LA prompt briefly bounces
        // the scene through `.inactive` → `.active`; without this guard a cancel
        // would instantly re-present the prompt in a loop. After a failure the
        // user drives the retry from the overlay's Retry button instead.
        if isLocked && !isAuthenticating && !didFail { authenticate() }
    }

    /// The app was really sent to the background. Re-arm the lock so the next
    /// foreground re-prompts. A no-op when the feature is off / logged out, so
    /// the login screen and opted-out users are never covered.
    func handleBackground() {
        guard shouldGate else { return }
        // Already unlocked today → leave it revealed so reopening won't re-cover
        // or re-prompt (the once-per-day cap).
        if unlockedToday() { return }
        isLocked = true
        didFail = false
        // Any prompt in flight is invalidated by the system when we background;
        // clear the flag so returning to the foreground can prompt again.
        isAuthenticating = false
    }

    /// Present Face ID / Touch ID with automatic device-passcode fallback.
    func authenticate() {
        guard isLocked, !isAuthenticating else { return }

        let context = LAContext()
        var policyError: NSError?

        // `.deviceOwnerAuthentication` == biometry OR device passcode. It is
        // NOT evaluable only when the device has no passcode set at all (and
        // therefore no biometry) — there is nothing to authenticate against, so
        // fail OPEN rather than trap the user out.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            print("🔓 [AppLock] Cannot evaluate device authentication (no passcode/biometry set) — failing open. \(policyError?.localizedDescription ?? "")")
            isLocked = false
            didFail = false
            isAuthenticating = false
            return
        }

        isAuthenticating = true
        didFail = false

        let reason = "Unlock Kinematic to continue."
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, error in
            // evaluatePolicy's completion runs on a private queue — hop to the
            // main actor before touching any @Published state.
            Task { @MainActor in
                guard let self else { return }
                self.isAuthenticating = false
                if success {
                    self.markUnlockedToday()   // once-per-day cap
                    self.isLocked = false
                    self.didFail = false
                } else {
                    // Keep the app covered and surface a Retry button.
                    print("🔒 [AppLock] Authentication failed/cancelled: \(error?.localizedDescription ?? "unknown")")
                    self.isLocked = true
                    self.didFail = true
                }
            }
        }
    }

    /// The overlay's "Log out" escape. Clears the lock; the caller performs the
    /// actual sign-out via the existing `KiniAppState.logout()`.
    func clearForLogout() {
        isLocked = false
        isAuthenticating = false
        didFail = false
    }
}

// MARK: - Lock overlay

/// Full-screen, opaque, brand-styled cover shown above everything while
/// `LockManager.isLocked` is true. Offers Unlock / Retry and a Log-out escape.
struct AppLockOverlay: View {
    @ObservedObject var lock: LockManager
    /// Existing app-wide logout (routes through `Session.logout()`).
    var onLogout: () -> Void

    var body: some View {
        ZStack {
            // Opaque brand backdrop so no app content shows through.
            Brand.navy.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 132, height: 132)
                    Image(systemName: lock.didFail ? "lock.trianglebadge.exclamationmark" : "faceid")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundColor(.white)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 8) {
                    Text("Kinematic Locked")
                        .font(Brand.Display.bold(24))
                        .foregroundColor(.white)
                    Text(lock.didFail
                         ? "Authentication failed. Try again to continue."
                         : "Unlock with Face ID, Touch ID, or your device passcode.")
                        .font(Brand.Body.regular(15))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                VStack(spacing: 14) {
                    Button(action: { lock.authenticate() }) {
                        HStack(spacing: 10) {
                            if lock.isAuthenticating {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "lock.open.fill")
                            }
                            Text(lock.isAuthenticating ? "Authenticating…" : (lock.didFail ? "Retry" : "Unlock"))
                        }
                        .font(Brand.Body.semiBold(16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Brand.red)
                        .cornerRadius(16)
                    }
                    .disabled(lock.isAuthenticating)

                    Button(action: onLogout) {
                        Text("Log out")
                            .font(Brand.Body.medium(15))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .transition(.opacity)
    }
}
