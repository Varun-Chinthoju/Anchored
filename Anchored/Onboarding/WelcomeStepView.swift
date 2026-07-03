import SwiftUI

struct WelcomeStepView: View {
    let onNext: () -> Void
    @State private var animateGlow = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Large Glowing Anchor Logo with a pirate hat on top!
            ZStack {
                // Outer breathing halo
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .blur(radius: animateGlow ? 22 : 12)
                    .opacity(animateGlow ? 0.3 : 0.15)
                
                // Frosted card backing
                Circle()
                    .fill(PirateTheme.darkWood.opacity(0.6))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(
                                PirateTheme.gold.opacity(0.4),
                                lineWidth: 1.5
                            )
                    )
                
                // SVG / Vector-like Anchor Symbol
                Image(systemName: "anchor")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundColor(PirateTheme.gold)
                    .shadow(color: PirateTheme.darkGold.opacity(0.6), radius: 12, x: 0, y: 4)
                
                // Pirate flag offset on top of the anchor to act as a pirate hat!
                Text("🏴‍☠️")
                    .font(.system(size: 40))
                    .offset(x: 0, y: -60)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
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
                    text: "Ahoy, Captain!",
                    font: .system(size: 38, weight: .bold, design: .serif),
                    colors: [PirateTheme.gold, PirateTheme.parchment]
                )
                
                Text("Commandeer your focus and guard your flow state from the mutinous distractions of the deep web. Stand ready to anchor your vessel.")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundColor(PirateTheme.parchment.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 500)
            }
            
            Spacer()
            
            Button(action: {
                AudioEngine.shared.play(.tick)
                onNext()
            }) {
                Text("Board the Vessel & Set Sail")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundColor(PirateTheme.darkWood)
                    .frame(width: 280)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: PirateTheme.gold.opacity(0.35), radius: 15, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            
            Spacer()
                .frame(height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
