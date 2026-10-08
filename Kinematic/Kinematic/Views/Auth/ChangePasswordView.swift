import SwiftUI
import UIKit

/// The password rules the app applies before it calls the server.
///
/// Mirrors the backend's `validatePassword` (Kinematic repo,
/// `src/middleware/security.ts`) for the one rule that is cheap and certain to
/// check on the device: the length. The other rules (common-password list,
/// 4+ identical characters in a row, keyboard / numeric sequences such as
/// 123456 or qwerty) stay server-side, and the server's own `error` text is
/// what the user sees when one of them trips — see
/// `KinematicRepository.changePassword(current:new:)`.
///
/// Kept free of UI and networking so it can be unit tested
/// (`ChangePasswordTests`).
enum PasswordPolicy {
    /// Shortest password the server accepts.
    static let minLength = 10
    /// Longest password the server accepts.
    static let maxLength = 200

    /// Placeholder for a "new password" field.
    static let placeholder = "Min 10 characters"

    /// Shown under every "new password" field.
    static let hint = "At least 10 characters. Avoid common passwords, 4 or more of the same character in a row, and sequences like 123456 or qwerty."

    static let tooShortMessage = "Password must be at least 10 characters."
    static let tooLongMessage = "Password is too long (max 200 characters)."

    /// What is wrong with a candidate new password on its own, or nil when it
    /// is acceptable to send. Length is counted in UTF-16 code units because
    /// that is what the server counts (JavaScript `string.length`).
    static func newPasswordProblem(_ new: String) -> String? {
        let length = new.utf16.count
        if length < minLength { return tooShortMessage }
        if length > maxLength { return tooLongMessage }
        return nil
    }

    /// The first problem with a voluntary password change (current / new /
    /// confirm), or nil when it is ready to send. Order matters: it is the
    /// order the fields appear on screen, so the message always points at the
    /// first thing the user still has to fix.
    static func passwordProblem(current: String, new: String, confirm: String) -> String? {
        if current.isEmpty { return "Enter your current password." }
        if let problem = newPasswordProblem(new) { return problem }
        if new == current { return "Your new password must be different from the current one." }
        if new != confirm { return "Passwords do not match." }
        return nil
    }
}

/**
 * Voluntary "Change password" screen, reached from Settings, the profile
 * screen and the CRM More menu. Unlike the forced first-login screen
 * (`SetPasswordView`) the user must prove who they are by typing their current
 * password; the server verifies it before it touches anything.
 *
 * POST /auth/change-password {current_password, new_password}. Failures come
 * back as HTTP 400 with a human-readable `error` (wrong current password,
 * same password, password-policy rejection) which is shown inline as-is.
 */
struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showCurrent = false
    @State private var showNew = false
    @State private var showConfirm = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    /// Inline feedback only once the user has typed something, so the screen
    /// does not open covered in red.
    private var newIsTooShort: Bool {
        !newPassword.isEmpty && PasswordPolicy.newPasswordProblem(newPassword) != nil
    }
    private var sameAsCurrent: Bool {
        !newPassword.isEmpty && newPassword == currentPassword
    }
    private var confirmMismatch: Bool {
        !confirmPassword.isEmpty && confirmPassword != newPassword
    }
    private var canSubmit: Bool {
        !busy && PasswordPolicy.passwordProblem(
            current: currentPassword, new: newPassword, confirm: confirmPassword
        ) == nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Enter your current password, then choose a new one.")
                    .font(Brand.Body.regular(14))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 18) {
                    PasswordField(
                        label: "CURRENT PASSWORD",
                        placeholder: "Your current password",
                        text: $currentPassword,
                        isRevealed: $showCurrent,
                        contentType: .password
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        PasswordField(
                            label: "NEW PASSWORD",
                            placeholder: PasswordPolicy.placeholder,
                            text: $newPassword,
                            isRevealed: $showNew,
                            contentType: .newPassword
                        )
                        Text(PasswordPolicy.hint)
                            .font(Brand.Body.regular(12))
                            .foregroundColor(newIsTooShort ? Brand.red : .secondary)
                        if sameAsCurrent {
                            Text("Your new password must be different from the current one.")
                                .font(Brand.Body.regular(12))
                                .foregroundColor(Brand.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        PasswordField(
                            label: "CONFIRM NEW PASSWORD",
                            placeholder: "Re-type to confirm",
                            text: $confirmPassword,
                            isRevealed: $showConfirm,
                            contentType: .newPassword
                        )
                        if confirmMismatch {
                            Text("Passwords do not match.")
                                .font(Brand.Body.regular(12))
                                .foregroundColor(Brand.red)
                        }
                    }
                }
                .disabled(busy)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(Brand.Body.regular(12))
                        .foregroundColor(Brand.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.red.opacity(0.08))
                        .cornerRadius(8)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if busy {
                            ProgressView().tint(.white)
                            Text("Updating…")
                        } else {
                            Text("Update password")
                        }
                    }
                    .font(Brand.Body.medium(15).weight(.bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.red)
                    .cornerRadius(12)
                }
                .disabled(!canSubmit)
                .opacity(busy ? 0.7 : (canSubmit ? 1 : 0.5))

                Spacer().frame(minHeight: 40)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .alert("Password updated", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your password has been changed. Use the new one the next time you sign in.")
        }
    }

    private func submit() async {
        if let problem = PasswordPolicy.passwordProblem(
            current: currentPassword, new: newPassword, confirm: confirmPassword
        ) {
            errorMessage = problem
            return
        }
        busy = true
        errorMessage = nil
        let (ok, err) = await KinematicRepository.shared.changePassword(
            current: currentPassword, new: newPassword
        )
        busy = false
        if ok {
            // Do not leave the secrets sitting in view state behind the alert.
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            showSuccess = true
        } else {
            errorMessage = err ?? "Couldn't update your password. Try again."
        }
    }
}

/// One labelled password input with its own show / hide eye toggle. Swaps
/// SecureField for TextField the same way the sign-in and forced-reset screens
/// do.
private struct PasswordField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @Binding var isRevealed: Bool
    let contentType: UITextContentType

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Brand.Mono.bold(10))
                .tracking(1.4)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Group {
                    if isRevealed {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(uiColor: .separator), lineWidth: 1))
        }
    }
}
