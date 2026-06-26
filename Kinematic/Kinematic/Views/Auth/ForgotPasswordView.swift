import SwiftUI

/**
 * Forgot-password — sheet presented from LoginView.
 *
 * Single email field → POST /auth/forgot-password → success card.
 * Backend's anti-enumeration guarantee means we ALWAYS show
 * "If this email is on file, a reset link is on its way." on
 * 2xx, regardless of whether the address matched a real user.
 */
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var busy = false
    @State private var sent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    KinematicBrandMark(size: 44)
                        .padding(.top, 8)

                    if !sent {
                        Text("Reset your password")
                            .font(Brand.Display.bold(24))
                            .foregroundColor(Brand.ink)

                        Text("Type the email tied to your account and we'll send you a link to set a new password.")
                            .font(Brand.Body.regular(14))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMAIL")
                                .font(Brand.Mono.bold(10))
                                .tracking(1.4)
                                .foregroundColor(.secondary)
                            TextField("you@company.com", text: $email)
                                .keyboardType(.emailAddress)
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
                                    Text("Sending…")
                                } else {
                                    Text("Send reset link")
                                }
                            }
                            .font(Brand.Body.medium(15).weight(.bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Brand.red)
                            .cornerRadius(12)
                        }
                        .disabled(busy || email.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(busy || email.trimmingCharacters(in: .whitespaces).isEmpty ? 0.7 : 1)
                    } else {
                        Text("Check your inbox")
                            .font(Brand.Display.bold(24))
                            .foregroundColor(Brand.ink)

                        Text("If \(email) is tied to a Kinematic account, a reset link is on its way. It expires in 60 minutes and can be used only once.")
                            .font(Brand.Body.regular(14))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Tap the link on this device — the app will open straight to the new-password screen. Didn't get it? Check spam, then resend.")
                            .font(Brand.Body.regular(13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)

                        Button {
                            sent = false
                        } label: {
                            Text("Resend reset link")
                                .font(Brand.Body.medium(14).weight(.semibold))
                                .foregroundColor(Brand.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Brand.rule, lineWidth: 1)
                                )
                        }
                        .padding(.top, 12)
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
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            errorMessage = "Enter your email."
            return
        }
        busy = true
        errorMessage = nil
        let (ok, err) = await KinematicRepository.shared.forgotPassword(email: trimmed)
        busy = false
        if ok {
            sent = true
        } else {
            // Network errors surface here. Backend's anti-enumeration
            // guard means a "user not found" never lands as an error —
            // it would have come back as a 2xx.
            errorMessage = err ?? "Couldn't send the reset email. Try again in a minute."
        }
    }
}
