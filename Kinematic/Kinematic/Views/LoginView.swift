import SwiftUI

// MARK: - Theme-aware tokens

private struct LoginTheme {
    let isDark: Bool
    var background: Color  { isDark ? Brand.navy  : Brand.paper }
    var surface:    Color  { isDark ? Color.white.opacity(0.04) : Brand.stone }
    var border:     Color  { isDark ? Color.white.opacity(0.10) : Brand.rule }
    var text:       Color  { isDark ? Brand.paper : Brand.ink }
    var textDim:    Color  { isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.55) }
    var textMuted:  Color  { isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.40) }
    var placeholder:Color  { isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.30) }
    var fieldText:  Color  { isDark ? Brand.paper : Brand.ink }
}

struct VibrantBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            (isDark ? Brand.navy : Brand.paper).ignoresSafeArea()

            ZStack {
                Circle()
                    .fill(Brand.red.opacity(isDark ? 0.10 : 0.05))
                    .frame(width: 500, height: 500)
                    .offset(x: -180, y: -300)
                    .blur(radius: 80)

                Circle()
                    .fill(Brand.red.opacity(isDark ? 0.06 : 0.03))
                    .frame(width: 400, height: 400)
                    .offset(x: 180, y: 350)
                    .blur(radius: 70)

                Circle()
                    .fill(Brand.info.opacity(isDark ? 0.05 : 0.03))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
            }
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }
}

private struct BrandFieldChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let theme = LoginTheme(isDark: colorScheme == .dark)
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}

private extension View {
    func brandFieldChrome() -> some View { modifier(BrandFieldChrome()) }
}

struct LoginView: View {
    let onSuccess: () -> Void
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showPassword = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        loginContent
    }

    private var loginContent: some View {
        let theme = LoginTheme(isDark: colorScheme == .dark)
        return ZStack {
            VibrantBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    Spacer().frame(height: 120)

                    Text("Welcome back")
                        .font(Brand.Display.bold(30))
                        .tracking(-0.3)
                        .foregroundColor(theme.text)
                        .padding(.bottom, 12)

                    Text("Sign in to your Kinematic account.")
                        .font(Brand.Body.regular(15))
                        .foregroundColor(theme.textDim)
                        .padding(.bottom, 48)

                    Text("EMAIL")
                        .font(Brand.Mono.bold(Brand.Scale.eyebrow))
                        .tracking(0.8)
                        .foregroundColor(theme.textMuted)
                        .padding(.bottom, 10)

                    HStack(spacing: 12) {
                        Image(systemName: "envelope")
                            .foregroundColor(Brand.red)
                            .font(.system(size: 15, weight: .medium))
                        TextField(
                            "",
                            text: $email,
                            prompt: Text("you@company.com").foregroundColor(theme.placeholder)
                        )
                        .foregroundColor(theme.fieldText)
                        .font(Brand.Body.medium(15))
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                    }
                    .brandFieldChrome()
                    .padding(.bottom, 24)

                    Text("PASSWORD")
                        .font(Brand.Mono.bold(Brand.Scale.eyebrow))
                        .tracking(0.8)
                        .foregroundColor(theme.textMuted)
                        .padding(.bottom, 10)

                    HStack(spacing: 12) {
                        Image(systemName: "lock")
                            .foregroundColor(Brand.red)
                            .font(.system(size: 15, weight: .medium))
                        if showPassword {
                            TextField(
                                "",
                                text: $password,
                                prompt: Text("Enter your password").foregroundColor(theme.placeholder)
                            )
                            .foregroundColor(theme.fieldText)
                            .font(Brand.Body.medium(15))
                            .textFieldStyle(.plain)
                            .textContentType(.password)
                        } else {
                            SecureField(
                                "",
                                text: $password,
                                prompt: Text("Enter your password").foregroundColor(theme.placeholder)
                            )
                            .foregroundColor(theme.fieldText)
                            .font(Brand.Body.medium(15))
                            .textFieldStyle(.plain)
                            .textContentType(.password)
                        }
                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(theme.textMuted)
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .brandFieldChrome()

                    if !errorMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(Brand.red)
                                .font(.system(size: 14))
                            Text(errorMessage)
                                .font(Brand.Body.medium(13))
                                .foregroundColor(Brand.red)
                        }
                        .padding(.top, 12)
                    }

                    Button(action: performLogin) {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView().tint(Brand.paper)
                            } else {
                                Text("Sign in")
                                    .font(Brand.Display.semiBold(16))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundColor(Brand.paper)
                        .background(Brand.red)
                        .cornerRadius(14)
                        .shadow(color: Brand.red.opacity(0.30), radius: 18, y: 8)
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.7 : 1.0)
                    .padding(.top, 28)

                    Text("Forgot your password? Contact your administrator.")
                        .font(Brand.Body.regular(12))
                        .foregroundColor(theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)

                    Spacer().frame(height: 80)

                    VStack(spacing: 8) {
                        Text("KINEMATIC v1.0")
                            .font(Brand.Mono.bold(10))
                            .tracking(2)
                            .foregroundColor(theme.textMuted)

                        Text("Role-based access controlled by your administrator.")
                            .font(Brand.Body.regular(11))
                            .foregroundColor(theme.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 28)
            }
            .ignoresSafeArea(.keyboard)
        }
    }

    private func performLogin() {
        isLoading = true
        errorMessage = ""
        Task {
            let phone = email.allSatisfy({ $0.isNumber }) ? email : nil
            let em = phone == nil ? email : ""
            let (success, error) = await KinematicRepository.shared.login(email: em, phone: phone, pass: password)
            await MainActor.run {
                isLoading = false
                if success {
                    onSuccess()
                } else {
                    errorMessage = error ?? "Sign in failed. Check your credentials."
                }
            }
        }
    }
}
