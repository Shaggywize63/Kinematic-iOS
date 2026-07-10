import SwiftUI

/**
 * Forced "set a new password" screen. ContentView shows this instead of the
 * app whenever the signed-in user's `must_change_password` flag is true — new
 * accounts, and everyone still on their initial/shared password after the
 * backfill. The only way out is to set a fresh password (or sign out).
 *
 * On success we POST /auth/change-password (which clears the flag server-side),
 * refresh /auth/me so the cached session reflects it, then call onSuccess()
 * (KiniAppState.checkAuth) which flips the root view onto the home tab.
 */
struct SetPasswordView: View {
    var onSuccess: () -> Void = {}

    @EnvironmentObject var appState: KiniAppState

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    KinematicBrandMark(size: 44)
                        .padding(.top, 8)

                    Text("Set a new password")
                        .font(Brand.Display.bold(24))
                        .foregroundColor(Brand.ink)

                    Text("For your security, please choose a new password before continuing.")
                        .font(Brand.Body.regular(14))
                        .foregroundColor(.secondary)

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
                        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.stone))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.rule, lineWidth: 1))
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
                        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.stone))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.rule, lineWidth: 1))
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
                                Text("Update password and continue")
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

                    Spacer().frame(minHeight: 40)
                }
                .padding(24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { appState.logout() }
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
        let (ok, err) = await KinematicRepository.shared.changePassword(newPassword: newPassword)
        if ok {
            // Pull the cleared flag back into the cached session, then flip the
            // root view onto the app.
            await KinematicRepository.shared.refreshMe()
            busy = false
            onSuccess()
        } else {
            busy = false
            errorMessage = err ?? "Couldn't update your password. Try again."
        }
    }
}
