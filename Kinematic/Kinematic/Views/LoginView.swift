import SwiftUI

struct VibrantBackgroundView: View {
    var body: some View {
        ZStack {
            Brand.navy.ignoresSafeArea()

            // Atmospheric glows — restrained per the 60-30-10 brand rule.
            ZStack {
                Circle()
                    .fill(Brand.red.opacity(0.10))
                    .frame(width: 500, height: 500)
                    .offset(x: -180, y: -300)
                    .blur(radius: 80)

                Circle()
                    .fill(Brand.red.opacity(0.06))
                    .frame(width: 400, height: 400)
                    .offset(x: 180, y: 350)
                    .blur(radius: 70)

                Circle()
                    .fill(Brand.info.opacity(0.05))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
            }
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }
}

private struct BrandFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
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
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
                        }
                    }
            } else {
                loginContent.transition(.opacity)
            }
        }
    }

    private var loginContent: some View {
        ZStack {
            VibrantBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    Spacer().frame(height: 64)

                    // Brand mark — anchors the screen as the first thing the user sees.
                    HStack {
                        Spacer()
                        KinematicMark(.reverse, size: 80)
                        Spacer()
                    }
                    .padding(.bottom, 24)

                    // Wordmark + tagline
                    VStack(alignment: .center, spacing: 8) {
                        Text("Kinematic")
                            .font(Brand.Display.extraBold(40))
                            .tracking(-0.5)
                            .foregroundColor(Brand.paper)

                        Text("FIELD FORCE MANAGEMENT")
                            .font(Brand.Mono.bold(Brand.Scale.eyebrow))
                            .tracking(2.0)
                            .foregroundColor(Brand.red)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 48)

                    // Welcome heading + lead
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome back")
                            .font(Brand.Display.bold(28))
                            .tracking(-0.3)
                            .foregroundColor(Brand.paper)

                        Text("Sign in to your Kinematic account.")
                            .font(Brand.Body.regular(15))
                            .foregroundColor(Color.white.opacity(0.65))
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)

                    // Form
                    VStack(alignment: .leading, spacing: 22) {

                        // Email
                        VStack(alignment: .leading, spacing: 10) {
                            Text("EMAIL")
                                .font(Brand.Mono.bold(Brand.Scale.eyebrow))
                                .tracking(0.8)
                                .foregroundColor(Color.white.opacity(0.55))

                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .foregroundColor(Brand.red)
                                    .font(.system(size: 15, weight: .medium))
                                TextField(
                                    "",
                                    text: $email,
                                    prompt: Text("you@company.com").foregroundColor(Color.white.opacity(0.35))
                                )
                                .foregroundColor(Brand.paper)
                                .font(Brand.Body.medium(15))
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .textContentType(.username)
                            }
                            .brandFieldChrome()
                        }

                        // Password
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PASSWORD")
                                .font(Brand.Mono.bold(Brand.Scale.eyebrow))
                                .tracking(0.8)
                                .foregroundColor(Color.white.opacity(0.55))

                            HStack(spacing: 12) {
                                Image(systemName: "lock")
                                    .foregroundColor(Brand.red)
                                    .font(.system(size: 15, weight: .medium))
                                if showPassword {
                                    TextField(
                                        "",
                                        text: $password,
                                        prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.35))
                                    )
                                    .foregroundColor(Brand.paper)
                                    .font(Brand.Body.medium(15))
                                    .textFieldStyle(.plain)
                                    .textContentType(.password)
                                } else {
                                    SecureField(
                                        "",
                                        text: $password,
                                        prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.35))
                                    )
                                    .foregroundColor(Brand.paper)
                                    .font(Brand.Body.medium(15))
                                    .textFieldStyle(.plain)
                                    .textContentType(.password)
                                }
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(Color.white.opacity(0.55))
                                        .font(.system(size: 14, weight: .medium))
                                }
                            }
                            .brandFieldChrome()
                        }

                        if !errorMessage.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(Brand.red)
                                    .font(.system(size: 14))
                                Text(errorMessage)
                                    .font(Brand.Body.medium(13))
                                    .foregroundColor(Brand.red)
                            }
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
                            .frame(height: 54)
                            .foregroundColor(Brand.paper)
                            .background(Brand.red)
                            .cornerRadius(14)
                            .shadow(color: Brand.red.opacity(0.30), radius: 18, y: 8)
                        }
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.7 : 1.0)

                        Text("Forgot your password? Contact your administrator.")
                            .font(Brand.Body.regular(12))
                            .foregroundColor(Color.white.opacity(0.50))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 28)

                    Spacer().frame(height: 56)

                    // Footer — minimal, on-brand. No "shield", no "manpower".
                    VStack(alignment: .center, spacing: 6) {
                        Text("KINEMATIC v1.0")
                            .font(Brand.Mono.bold(10))
                            .tracking(2)
                            .foregroundColor(Color.white.opacity(0.30))

                        Text("Role-based access controlled by your administrator.")
                            .font(Brand.Body.regular(11))
                            .foregroundColor(Color.white.opacity(0.30))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 32)
                }
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
