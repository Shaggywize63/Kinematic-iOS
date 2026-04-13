import SwiftUI

struct VibrantBackgroundView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            // Atmospheric Glows
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 450, height: 450)
                    .offset(x: -150, y: -250)
                    .blur(radius: 60)
                
                Circle()
                    .fill(Color.red.opacity(0.05))
                    .frame(width: 350, height: 350)
                    .offset(x: 150, y: 300)
                    .blur(radius: 50)
            }
        }
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
                    
                    Spacer().frame(height: 80)
                    
                    // Header Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to")
                            .font(.title3)
                            .foregroundColor(Color(uiColor: .secondaryLabel))
                        
                        Text("Kinematic")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundColor(Color(uiColor: .label))
                            .tracking(-1)
                        
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 40, height: 4)
                            .cornerRadius(2)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer().frame(height: 64)
                    
                    // Form Section
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // Identification
                        VStack(alignment: .leading, spacing: 12) {
                            Text("IDENTIFICATION")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .tracking(2)
                            
                            HStack {
                                Image(systemName: "at").foregroundColor(.white.opacity(0.3))
                                TextField("", text: $email, prompt: Text("Mobile or Email").foregroundColor(Color(uiColor: .label).opacity(0.2)))
                                    .foregroundColor(Color(uiColor: .label))
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                            }
                            .padding()
                            .liquidGlass(cornerRadius: 16, opacity: 0.1)
                        }
                        
                        // Security Key
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SECURITY KEY")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(uiColor: .secondaryLabel))
                                .tracking(2)
                            
                            HStack {
                                Image(systemName: "lock.open.fill").foregroundColor(Color(uiColor: .label).opacity(0.3))
                                if showPassword {
                                    TextField("", text: $password, prompt: Text("Enter password").foregroundColor(Color(uiColor: .label).opacity(0.2)))
                                        .foregroundColor(Color(uiColor: .label))
                                } else {
                                    SecureField("", text: $password, prompt: Text("Enter password").foregroundColor(Color(uiColor: .label).opacity(0.2)))
                                        .foregroundColor(Color(uiColor: .label))
                                }
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(Color(uiColor: .label).opacity(0.3))
                                }
                            }
                            .padding()
                            .liquidGlass(cornerRadius: 16, opacity: 0.1)
                        }
                        
                        if !errorMessage.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.octagon.fill").foregroundColor(.red)
                                Text(errorMessage).font(.caption).foregroundColor(.red)
                            }
                            .padding(.top, 4)
                        }
                        
                        Spacer().frame(height: 16)
                        
                        Button(action: performLogin) {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Login")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.red.opacity(isLoading ? 0.6 : 1.0))
                            )
                            .foregroundColor(.white)
                            .shadow(color: Color.red.opacity(0.3), radius: 20, y: 10)
                        }
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer().frame(height: 100)
                    
                    VStack(alignment: .center, spacing: 4) {
                        Text("KINEMATIC SHIELD PROTECTED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                            .tracking(1)
                            .frame(maxWidth: .infinity)
                        
                        Text("v1.1 (Redesigned)")
                            .font(.system(size: 8))
                            .foregroundColor(Color(uiColor: .tertiaryLabel).opacity(0.5))
                    }
                    .padding(.bottom, 20)
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
