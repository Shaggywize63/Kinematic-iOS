import SwiftUI

/// A custom ViewModifier that applies a premium Liquid Glass aesthetic.
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: Double
    var shadowRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .background(Color.white.opacity(opacity))
            .cornerRadius(cornerRadius)
            // Delicate inner border for realism
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .clear, .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            // Ambient soft shadow
            .shadow(color: .black.opacity(0.15), radius: shadowRadius, x: 0, y: 10)
    }
}

extension View {
    /// Applies a premium Liquid Glass (glassmorphism) effect matching modern Apple Design Guidelines.
    func liquidGlass(cornerRadius: CGFloat = 24, opacity: Double = 0.1, shadowRadius: CGFloat = 20) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, opacity: opacity, shadowRadius: shadowRadius))
    }
}

/// A vibrant, animated background designed to sit beneath Liquid Glass elements.
struct VibrantBackgroundView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Color.kDark.ignoresSafeArea()
            
            // Abstract floating gradients
            Circle()
                .fill(Color.kGradient1)
                .frame(width: 300, height: 300)
                .offset(x: animate ? -100 : 100, y: animate ? -150 : 0)
                .blur(radius: 90)
            
            Circle()
                .fill(Color.kGradient3)
                .frame(width: 400, height: 400)
                .offset(x: animate ? 150 : -100, y: animate ? 200 : -100)
                .blur(radius: 120)
                
            Circle()
                .fill(Color.kGradient2)
                .frame(width: 250, height: 250)
                .offset(x: animate ? -50 : 100, y: animate ? 300 : 150)
                .blur(radius: 90)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}
