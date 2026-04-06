import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isAuthenticating = false
    
    var body: some View {
        ZStack {
            // 1. Vibrant Animated Background
            VibrantBackgroundView()
            
            // 2. Main Login Liquid Glass Card
            VStack(spacing: 30) {
                // Logo & Header
                VStack(spacing: 12) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(colors: [.kGradient3, .kGradient4], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .kGradient3.opacity(0.5), radius: 15, x: 0, y: 10)
                    
                    Text("Kinematic")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Field Executive Portal")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.bottom, 10)
                
                // Input Fields
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.white.opacity(0.6))
                        TextField("Email Address", text: $email)
                            .foregroundColor(.white)
                            .accentColor(.kRed)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                    }
                    .padding()
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(16)
                    
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.white.opacity(0.6))
                        SecureField("Password", text: $password)
                            .foregroundColor(.white)
                            .accentColor(.kRed)
                    }
                    .padding()
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(16)
                }
                
                // Sign In Button
                Button(action: {
                    authenticateUser()
                }) {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Sign In")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(colors: [.kRed, Color(hex: "B31220")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .shadow(color: .kRed.opacity(0.4), radius: 15, x: 0, y: 8)
                }
                .disabled(email.isEmpty || password.isEmpty || isAuthenticating)
                .opacity((email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                
            }
            .padding(32)
            // Apply the Liquid Glass aesthetic
            .liquidGlass(cornerRadius: 32, opacity: 0.1, shadowRadius: 30)
            .padding(.horizontal, 24)
        }
    }
    
    // Stub for Supabase Auth integration logic
    private func authenticateUser() {
        isAuthenticating = true
        // TODO: Integrate Supabase Auth
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isAuthenticating = false
            print("Authentication triggered for: \(email)")
        }
    }
}

#Preview {
    LoginView()
}
