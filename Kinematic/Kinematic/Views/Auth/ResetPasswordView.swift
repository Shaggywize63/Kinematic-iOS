import SwiftUI

/**
 * Reset-password — presented as a sheet by KinematicApp when a
 * `kinematic://reset-password?email=…&token=…` deep link arrives via
 * `.onOpenURL`. Email + token are pre-filled from the URL; user types
 * the new password twice and we POST /auth/reset-password.
 *
 * Auto-login: the backend's response includes a fresh session that
 * KinematicRepository.resetPassword saves to UserDefaults, then
 * KiniAppState.checkAuth() flips the app onto the home tab without
 * a second sign-in step.
 */
struct ResetPasswordView: View {
    let email: String
    let token: String
    var onComplete: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var errorMessage: String?

    var linkValid: Bool { !email.isEmpty && !token.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    KinematicBrandMark(size: 44)
                        .padding(.top, 8)

                    Text("Set a new password")
                        .font(Brand.Display.bold(24))
                        .foregroundColor(Brand.ink)

                    if !email.isEmpty {
                        Text("for \(email)")
                            .font(Brand.Body.regular(14))
                            .foregroundColor(.secondary)
                    }

                    if !linkValid {
                        Text("This reset link is incomplete. Open the link from the email exactly as it was sent, or request a fresh one.")
                            .font(Brand.Body.regular(13))
                            .foregroundColor(Brand.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Brand.red.opacity(0.06))
                            .cornerRadius(8)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NEW PASSWORD")
                                .font(Brand.Mono.bold(10))
                                .tracking(1.4)
                                .foregroundColor(.secondary)
                            HStack {
                                Group {
                                    if showPassword {
                                        TextField("Min 6 characters", text: $newPassword)
                                    } else {
                                        SecureField("Min 6 characters", text: $newPassword)
                                    }
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                Button { showPassword.toggle() } label: {
                                    Text(showPassword ? "HIDE" : "SHOW")
                                        .font(Brand.Mono.bold(10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Brand.stone)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Brand.rule, lineWidth: 1)
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("CONFIRM NEW PASSWORD")
                                .font(Brand.Mono.bold(10))
                                .tracking(1.4)
                                .foregroundColor(.secondary)
                            Group {
                                if showPassword {
                                    TextField("Re-type to confirm", text: $confirmPassword)
                                } else {
                                    SecureField("Re-type to confirm", text: $confirmPassword)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Brand.stone)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Brand.rule, lineWidth: 1)
                            )
                        }

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
                                    Text("Update password and sign me in")
                                }
                            }
                            .font(Brand.Body.medium(15).weight(.bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Brand.red)
                            .cornerRadius(12)
                        }
                        .disabled(busy)
                        .opacity(busy ? 0.7 : 1)
                    }

                    Spacer().frame(minHeight: 40)
                }
                .padding(24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Brand.ink)
                }
            }
        }
    }

    private func submit() async {
        guard newPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        busy = true
        errorMessage = nil
        let (ok, err) = await KinematicRepository.shared.resetPassword(
            email: email,
            token: token,
            newPassword: newPassword
        )
        busy = false
        if ok {
            // KiniAppState.checkAuth() inside the repo's MainActor run
            // already flipped the root view onto the home tab.
            onComplete()
            dismiss()
        } else {
            errorMessage = err ?? "Reset link is invalid or has expired. Request a new one."
        }
    }
}
