import SwiftUI

struct VibrantBackgroundView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            // Atmospheric Glows
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 500, height: 500)
                    .offset(x: -180, y: -300)
                    .blur(radius: 80)
                
                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 400, height: 400)
                    .offset(x: 180, y: 350)
                    .blur(radius: 70)
                
                // Deep Accent Glow
                Circle()
                    .fill(Color.red.opacity(0.05))
                    .frame(width: 300, height: 300)
                    .offset(x: 0, y: 0)
                    .blur(radius: 100)
            }
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }
}

private struct LoginFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
    }
}

private extension View {
    func loginFieldChrome() -> some View {
        modifier(LoginFieldChrome())
    }
}

struct LoginView: View {
    let onSuccess: () -> Void
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showPassword = false
    
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    
                    Spacer().frame(height: 100)
                    
                    // Header Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("SECURED")
                                .font(.system(size: 10, weight: .black))
                                .tracking(2)
                                .foregroundColor(.red)
                        }
                        
                        Text("Welcome to\nKinematic")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundColor(Color(uiColor: .label))
                            .lineSpacing(-8)
                            .tracking(-1)
                        
                        Text("Field Operations Hub")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 60)
                    
                    Spacer().frame(height: 80)
                    
                    // Form Section
                    VStack(alignment: .leading, spacing: 32) {
                        
                        // Identification
                        VStack(alignment: .leading, spacing: 12) {
                            Text("IDENTIFICATION")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(2)
                            
                            HStack {
                                Image(systemName: "at").foregroundColor(.red).font(.system(size: 16, weight: .bold))
                                TextField("", text: $email, prompt: Text("Mobile or Email").foregroundColor(Color(uiColor: .label).opacity(0.3)))
                                    .foregroundColor(Color(uiColor: .label))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .textFieldStyle(.plain)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.emailAddress)
                                    .textContentType(.username)
                            }
                            .padding(20)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        
                        // Security Key
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SECURITY KEY")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(2)
                            
                            HStack {
                                Image(systemName: "lock.fill").foregroundColor(.red).font(.system(size: 16, weight: .bold))
                                if showPassword {
                                    TextField("", text: $password, prompt: Text("Enter password").foregroundColor(Color(uiColor: .label).opacity(0.3)))
                                        .foregroundColor(Color(uiColor: .label))
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .textFieldStyle(.plain)
                                        .textContentType(.password)
                                } else {
                                    SecureField("", text: $password, prompt: Text("Enter password").foregroundColor(Color(uiColor: .label).opacity(0.3)))
                                        .foregroundColor(Color(uiColor: .label))
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .textFieldStyle(.plain)
                                        .textContentType(.password)
                                }
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 14))
                                }
                            }
                            .padding(20)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        
                        if !errorMessage.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.shield.fill").foregroundColor(.red)
                                Text(errorMessage).font(.caption).fontWeight(.bold).foregroundColor(.red)
                            }
                            .padding(.top, 4)
                        }
                        
                        Button(action: performLogin) {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    HStack(spacing: 12) {
                                        Text("Authorize Session")
                                        Image(systemName: "arrow.right.circle.fill")
                                    }
                                    .font(.headline)
                                    .fontWeight(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                LinearGradient(colors: [.red, Color(red: 0.8, green: 0, blue: 0)], startPoint: .top, endPoint: .bottom)
                            )
                            .cornerRadius(20)
                            .foregroundColor(.white)
                            .shadow(color: Color.red.opacity(0.3), radius: 20, y: 10)
                        }
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        
                    }
                    .padding(.horizontal, 60)
                    
                    Spacer().frame(height: 80)
                    
                    VStack(alignment: .center, spacing: 6) {
                        Text("KINEMATIC SHIELD PROTECTED")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                            .tracking(2)
                            .frame(maxWidth: .infinity)
                        
                        Text("Secured Multi-Manpower Management Platform")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(uiColor: .tertiaryLabel).opacity(0.6))
                    }
                    .padding(.bottom, 40)
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
                    errorMessage = error ?? "Access denied"
                }
            }
        }
    }
}
