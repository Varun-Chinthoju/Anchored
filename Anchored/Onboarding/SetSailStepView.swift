import SwiftUI

struct SetSailStepView: View {
    let onComplete: () -> Void
    @State private var animateGlow = false
    @ObservedObject private var langManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Large Glowing Wheel/Compass with breathing animation
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
                    .frame(width: 160, height: 160)
                    .blur(radius: animateGlow ? 24 : 12)
                    .opacity(animateGlow ? 0.35 : 0.15)
                
                // Frosted card backing
                Circle()
                    .fill(PirateTheme.darkWood.opacity(0.6))
                    .frame(width: 130, height: 130)
                    .overlay(
                        Circle()
                            .stroke(
                                PirateTheme.gold.opacity(0.4),
                                lineWidth: 2
                            )
                    )
                
                // Ship wheel / steering wheel icon (or large compass)
                Image(systemName: "compass.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(PirateTheme.gold)
                    .shadow(color: PirateTheme.darkGold.opacity(0.6), radius: 12, x: 0, y: 4)
                
                // Pirate flag offset
                Text("🏴‍☠️")
                    .font(.system(size: 44))
                    .offset(x: 0, y: -70)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
            }
            .padding(.bottom, 12)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
                ) {
                    animateGlow = true
                }
            }
            
            VStack(spacing: 12) {
                GlowingText(
                    text: t("sail_title"),
                    font: .system(size: 38, weight: .bold, design: .serif),
                    colors: [PirateTheme.gold, PirateTheme.parchment]
                )
                
                Text(t("sail_desc"))
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundColor(PirateTheme.parchment.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 500)
            }
            
            Spacer()
            
            Button(action: {
                AudioEngine.shared.play(.chime)
                onComplete()
            }) {
                Text("\(t("sail_btn")) ⚓")
                    .font(.system(size: 16, weight: .bold, design: .serif))
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
                    .shadow(color: PirateTheme.gold.opacity(0.4), radius: 15, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            
            Spacer()
                .frame(height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
