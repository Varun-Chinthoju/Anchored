import SwiftUI

struct WelcomeStepView: View {
    let onNext: () -> Void
    @State private var animateGlow = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Large Glowing Anchor Logo with breathing animation
            ZStack {
                // Outer breathing halo
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(red: 0.1, green: 0.5, blue: 1.0), Color(red: 0.9, green: 0.3, blue: 0.7)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .blur(radius: animateGlow ? 20 : 10)
                    .opacity(animateGlow ? 0.3 : 0.15)
                
                // Frosted card backing
                Circle()
                    .fill(Color.primary.opacity(0.03))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue.opacity(0.3), .pink.opacity(0.3)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                
                // SVG / Vector-like Anchor Symbol
                Image(systemName: "anchor")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.95, green: 0.35, blue: 0.75)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .pink.opacity(0.4), radius: 12, x: 0, y: 4)
            }
            .padding(.bottom, 12)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.2)
                    .repeatForever(autoreverses: true)
                ) {
                    animateGlow = true
                }
            }
            
            VStack(spacing: 12) {
                GlowingText(
                    text: "Welcome to Anchored",
                    font: .system(size: 38, weight: .bold, design: .rounded),
                    colors: [Color(red: 0.1, green: 0.6, blue: 1.0), Color(red: 0.95, green: 0.4, blue: 0.8)]
                )
                
                Text("Ambient flow state protection for macOS. Stay locked into your deep work.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            
            Spacer()
            
            Button(action: {
                AudioEngine.shared.play(.tick)
                onNext()
            }) {
                Text("Set Up Anchored")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 260)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(red: 0.1, green: 0.5, blue: 1.0), Color(red: 0.9, green: 0.3, blue: 0.7)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.pink.opacity(0.3), radius: 15, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            
            Spacer()
                .frame(height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
